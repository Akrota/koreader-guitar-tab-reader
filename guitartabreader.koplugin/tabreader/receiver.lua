--[[--
Receiving tabs from the phone (or a computer) over the home Wi-Fi.

The e-reader serves a small web page while the library is open. The phone
opens it (QR code or address) and sends files (PDF, text tabs, ChordPro),
pasted text or a link. Nothing goes through a server outside the home network.

Safety (same approach as Story Recall's key setup): a secret token in every
address, so only devices that know it can send; fixed limits per request
(time, size, header count), because this runs on the UI thread; the server
only runs while the library is open and stops on sleep.

The address comes from the QR code each time, so a new IP address from the
router does not matter. (The iOS shortcut was removed on 25.10.2026: it needed
a fixed address.)
--]]

local socket = require("socket")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("tabreader/i18n")
local T = require("ffi/util").template

local Receiver = {}
Receiver.__index = Receiver

local FIRST_PORT = 8746
local PORT_TRIES = 10
local POLL_INTERVAL = 1           -- seconds; the phone waits at most this long, the e-reader sleeps more
local HEADER_DEADLINE = 3          -- seconds for request line and headers
local BODY_DEADLINE = 30           -- seconds for the body (uploads)
local MAX_LINE = 4096
local MAX_HEADERS = 50
local MAX_BODY = 12 * 1024 * 1024  -- bytes
local TEXT_EXT = { txt = true, tab = true, crd = true, cho = true, chopro = true, chordpro = true, pro = true }

-- The device's address on the local network. Connecting a UDP socket sends no
-- packet; it only makes the system pick the outgoing interface.
function Receiver.localIP()
    local udp = socket.udp()
    if not udp then return end
    udp:settimeout(0.5)
    pcall(udp.setpeername, udp, "8.8.8.8", 80)
    local ip = udp:getsockname()
    udp:close()
    if ip and ip ~= "0.0.0.0" and ip ~= "127.0.0.1" then return ip end
end

function Receiver.randomToken()
    local file = io.open("/dev/urandom", "rb")
    local bytes = file and file:read(12)
    if file then file:close() end
    if not bytes or #bytes < 12 then
        math.randomseed(os.time() + math.floor(os.clock() * 1e6))
        local parts = {}
        for i = 1, 12 do parts[i] = string.char(math.random(0, 255)) end
        bytes = table.concat(parts)
    end
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function htmlEscape(text)
    return (tostring(text):gsub("[&<>\"]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ["\""] = "&quot;" }))
end

local function urlDecode(text)
    text = text:gsub("+", " ")
    return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function parseQuery(query)
    local fields = {}
    for pair in (query or ""):gmatch("[^&]+") do
        local k, v = pair:match("^([^=]*)=(.*)$")
        if k then fields[urlDecode(k)] = urlDecode(v) end
    end
    return fields
end

--- multipart/form-data body -> list of parts { name, filename, content_type, data }
function Receiver.parseMultipart(body, boundary)
    local parts = {}
    local delimiter = "--" .. boundary
    local pos = body:find(delimiter, 1, true)
    while pos do
        local start = pos + #delimiter
        if body:sub(start, start + 1) == "--" then break end -- closing delimiter
        start = start + 2 -- skip CRLF
        local header_end = body:find("\r\n\r\n", start, true)
        if not header_end then break end
        local headers = body:sub(start, header_end - 1)
        local next_pos = body:find("\r\n" .. delimiter, header_end + 4, true)
        if not next_pos then break end
        local data = body:sub(header_end + 4, next_pos - 1)
        local name = headers:match('name="([^"]*)"')
        local filename = headers:match('filename="([^"]*)"')
        local content_type = headers:match("[Cc]ontent%-[Tt]ype:%s*([^\r\n]+)")
        parts[#parts + 1] = { name = name, filename = filename, content_type = content_type, data = data }
        pos = next_pos + 2
    end
    return parts
end

local function looksLikeLink(text)
    -- a link is short: do not copy and trim a whole uploaded file to find out
    if #text > 4000 then return false, text end
    local s = text:gsub("^%s+", ""):gsub("%s+$", "")
    return s:match("^https?://%S+$") ~= nil and #s < 2000, s
end

--- Start the receiver.
-- @param opts { folder, token, on_received = function(results) }
-- @return receiver or nil + error text
function Receiver.start(opts)
    local ip = Receiver.localIP()
    if not ip then return nil, _("No network address found. Is Wi-Fi on?") end
    local server, port
    for offset = 0, PORT_TRIES - 1 do
        server = socket.bind("*", FIRST_PORT + offset)
        if server then port = FIRST_PORT + offset break end
    end
    if not server then return nil, _("The receiver could not be started.") end
    server:settimeout(0)
    local self = setmetatable({
        server = server, ip = ip, port = port,
        folder = opts.folder, token = opts.token, on_received = opts.on_received,
    }, Receiver)
    self.base = string.format("http://%s:%d", ip, port)
    self.page_url = self.base .. "/?t=" .. self.token
    local UIManager = require("ui/uimanager")
    self.poll_task = function() self:poll() end
    UIManager:scheduleIn(POLL_INTERVAL, self.poll_task)
    logger.dbg("GuitarTabReader: receiver at", ip, port)
    return self
end

function Receiver:stop()
    local UIManager = require("ui/uimanager")
    if self.poll_task then UIManager:unschedule(self.poll_task) self.poll_task = nil end
    if self.server then self.server:close() self.server = nil end
end

function Receiver:poll()
    if not self.server then return end
    local client = self.server:accept()
    if client then
        local ok, err = pcall(self.handle, self, client)
        if not ok then logger.warn("GuitarTabReader receiver:", err) end
        client:close()
    end
    if self.server then
        require("ui/uimanager"):scheduleIn(POLL_INTERVAL, self.poll_task)
    end
end

-- Saving -------------------------------------------------------------------

local function uniquePath(dir, name)
    local base, ext = name:match("^(.*)(%.[^.]+)$")
    if not base then base, ext = name, "" end
    local path = dir .. "/" .. name
    local n = 2
    while lfs.attributes(path, "mode") do
        path = string.format("%s/%s (%d)%s", dir, base, n, ext)
        n = n + 1
    end
    return path
end

local function writeFile(path, data)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

local function safeName(name, dir)
    name = (name or ""):gsub("[/\\]", "-"):gsub("^%.+", ""):gsub("%c", "")
    if name == "" then name = "Tab" end
    return util.getSafeFilename and util.getSafeFilename(name, dir) or name
end

--- Save a received file. PDFs go into the "pdf" subfolder, the rest into the tab folder.
-- @return result { kind, name } or nil + reason
function Receiver:saveFile(filename, data)
    if #data == 0 then return nil, _("empty file") end
    local ext = (filename or ""):match("%.([%w]+)$")
    ext = ext and ext:lower()
    local is_pdf = data:sub(1, 5) == "%PDF-"
    if is_pdf then
        ext = "pdf"
        if not filename or not filename:lower():match("%.pdf$") then
            filename = os.date("Tab %Y-%m-%d %H-%M") .. ".pdf"
        end
    elseif not ext or not TEXT_EXT[ext] then
        -- unknown or missing extension: keep it as a text tab
        filename = (filename and filename:gsub("%.[^.]*$", "") or os.date("Tab %Y-%m-%d %H-%M")) .. ".txt"
        ext = "txt"
    end
    local dir = ext == "pdf" and (self.folder .. "/pdf") or self.folder
    util.makePath(dir)
    local path = uniquePath(dir, safeName(filename, dir))
    if not writeFile(path, data) then return nil, _("could not be saved") end
    return { kind = ext == "pdf" and "pdf" or "file", name = path:match("[^/]+$"), path = path }
end

--- Save pasted text as a tab file named "Artist - Title.txt".
function Receiver:saveText(text, title, artist)
    text = text:gsub("\r\n", "\n")
    if not title or title == "" then
        title = text:match("^%s*([^\n]+)") or "Tab"
        title = title:sub(1, 60)
    end
    local name = (artist and artist ~= "" and (artist .. " - ") or "") .. title .. ".txt"
    util.makePath(self.folder)
    local path = uniquePath(self.folder, safeName(name, self.folder))
    if not writeFile(path, text) then return nil, _("could not be saved") end
    return { kind = "text", name = path:match("[^/]+$"), path = path }
end

--- Remember a link; the Ultimate Guitar module loads the tab from it.
function Receiver:saveLink(url)
    local LuaSettings = require("luasettings")
    util.makePath(self.folder .. "/.tabreader")
    local queue = LuaSettings:open(self.folder .. "/.tabreader/links.lua")
    local links = queue:readSetting("links") or {}
    links[#links + 1] = { url = url, added = os.time() }
    queue:saveSetting("links", links)
    queue:flush()
    return { kind = "link", name = url }
end

-- HTTP ---------------------------------------------------------------------

local function respond(client, status, body, content_type)
    client:settimeout(5, "t")
    client:send(table.concat{
        "HTTP/1.1 ", status, "\r\n",
        "Content-Type: ", content_type or "text/html; charset=utf-8", "\r\n",
        "Content-Length: ", tostring(#body), "\r\n",
        "Cache-Control: no-store\r\n",
        "Connection: close\r\n\r\n",
        body,
    })
end

function Receiver:handle(client)
    -- Request line and headers with a short deadline, the body with a longer one.
    local deadline = socket.gettime() + HEADER_DEADLINE
    local function readLine()
        local left = deadline - socket.gettime()
        if left <= 0 then return nil end
        client:settimeout(left, "t")
        local line = client:receive("*l")
        if line and #line > MAX_LINE then return nil end
        return line
    end
    local line = readLine()
    if not line then return end
    local method, target = line:match("^(%u+)%s+(%S+)")
    if not method then return end
    local path, query = target:match("^([^?]*)%??(.*)$")
    local params = parseQuery(query)
    local headers, count = {}, 0
    while true do
        local header = readLine()
        count = count + 1
        if not header or count > MAX_HEADERS then return end
        if header == "" then break end
        local name, value = header:match("^([^:]+):%s*(.*)$")
        if name then headers[name:lower()] = value end
    end

    if params.t ~= self.token then
        return respond(client, "403 Forbidden", self:messagePage(_("Not allowed"),
            _("Open the address shown on the e-reader (Guitar Tab Reader → Add tab).")))
    end

    local body = ""
    local length = tonumber(headers["content-length"] or "0") or 0
    if method == "POST" then
        if length > MAX_BODY then
            return respond(client, "413 Payload Too Large", self:messagePage(_("Too large"), _("Files up to 12 MB.")))
        end
        local body_deadline = socket.gettime() + BODY_DEADLINE
        local chunks, got = {}, 0
        while got < length do
            local left = body_deadline - socket.gettime()
            if left <= 0 then return end
            client:settimeout(left, "t")
            local chunk, err, partial = client:receive(math.min(65536, length - got))
            chunk = chunk or partial
            if not chunk or #chunk == 0 then
                if err ~= "timeout" then return end
            else
                chunks[#chunks + 1] = chunk
                got = got + #chunk
            end
        end
        body = table.concat(chunks)
    end

    if method == "GET" and (path == "/" or path == "") then
        return respond(client, "200 OK", self:formPage())
    elseif method == "POST" and path == "/add" then
        local results, errors = self:receive(body, headers, params)
        if #results > 0 and self.on_received then
            require("ui/uimanager"):nextTick(function() self.on_received(results) end)
        end
        return respond(client, "200 OK", self:resultPage(results, errors))
    end
    respond(client, "404 Not Found", self:messagePage(_("Not found"), ""))
end

--- Turn a request body into saved tabs.
-- @return results, errors
function Receiver:receive(body, headers, params)
    local results, errors = {}, {}
    local function add(result, err, what)
        if result then results[#results + 1] = result else errors[#errors + 1] = (what or "?") .. ": " .. tostring(err) end
    end
    local content_type = headers["content-type"] or ""
    local boundary = content_type:match("boundary=\"?([^\";]+)\"?")
    if content_type:find("multipart/form-data", 1, true) and boundary then
        local fields = {}
        for _i, part in ipairs(Receiver.parseMultipart(body, boundary)) do
            if part.filename and part.filename ~= "" then
                if #part.data > 0 then
                    -- a link saved as a small file
                    local is_link, url = looksLikeLink(part.data)
                    if is_link and part.data:sub(1, 5) ~= "%PDF-" then
                        add(self:saveLink(url), nil, url)
                    else
                        add(self:saveFile(part.filename, part.data))
                    end
                end
            elseif part.name then
                fields[part.name] = part.data
            end
        end
        local link = fields.link and fields.link:gsub("^%s+", ""):gsub("%s+$", "")
        if link and link ~= "" then
            local is_link, url = looksLikeLink(link)
            if is_link then add(self:saveLink(url), nil, link) else add(nil, _("not a link"), link) end
        end
        local text = fields.text
        if text and text:match("%S") then
            local is_link, url = looksLikeLink(text)
            if is_link then
                add(self:saveLink(url), nil, url)
            else
                add(self:saveText(text, fields.title, fields.artist))
            end
        end
    end
    return results, errors
end

-- Pages ----------------------------------------------------------------------

local PAGE_STYLE = [[
body{font-family:-apple-system,system-ui,sans-serif;max-width:34rem;margin:0 auto;padding:1.2rem 1rem 2rem;color:#1f1d1a;background:#f5f3ee}
h1{font-size:1.5rem;margin:.2rem 0}h1 small{display:block;font-size:.9rem;font-weight:normal;color:#6b665e;margin-top:.2rem}
h2{font-size:1.1rem;margin:0 0 .6rem}
.card{background:#fff;border:1px solid #ddd8ce;border-radius:.6rem;padding:1rem;margin-top:1rem}
label{display:block;font-size:.85rem;color:#57524a;margin:.6rem 0 .25rem}
input[type=text],textarea{width:100%;box-sizing:border-box;font-size:1rem;padding:.65rem;border:1px solid #c9c2b5;border-radius:.4rem;background:#fffdf9}
textarea{min-height:9rem;font-family:ui-monospace,Menlo,monospace;font-size:.85rem}
input[type=file]{font-size:1rem;margin:.3rem 0}
.btn{display:block;width:100%;margin-top:.9rem;font-size:1.05rem;padding:.8rem;border:0;border-radius:2rem;background:#1f1d1a;color:#f5f3ee}
.hint{color:#6b665e;font-size:.85rem;margin:.5rem 0 0;line-height:1.4}
a.btn{display:block;text-align:center;text-decoration:none;box-sizing:border-box}
.ok{color:#2f6b3f}.err{color:#a33}
]]

local function page(title, inner)
    return table.concat{
        '<!doctype html><html><head><meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width,initial-scale=1">',
        '<title>Guitar Tab Reader</title><style>', PAGE_STYLE, '</style></head><body>',
        '<h1>Guitar Tab Reader<small>', htmlEscape(title), '</small></h1>', inner, '</body></html>',
    }
end

function Receiver:messagePage(title, text)
    return page(title, '<div class="card"><p>' .. htmlEscape(text) .. '</p></div>')
end

function Receiver:formPage()
    local action = "/add?t=" .. self.token
    return page(_("Send tabs to your e-reader"), table.concat{
        '<form method="post" enctype="multipart/form-data" action="', action, '">',
        '<div class="card"><h2>', htmlEscape(_("Files")), '</h2>',
        '<input type="file" name="files" multiple accept=".pdf,.txt,.tab,.cho,.chopro,.chordpro,.pro,.crd,application/pdf,text/plain">',
        '<p class="hint">', htmlEscape(_("PDFs (e.g. from the Ultimate Guitar app), text tabs or ChordPro files. Several at once are fine.")), '</p>',
        '<button class="btn" type="submit">', htmlEscape(_("Send")), '</button></div>',
        '</form>',
        '<form method="post" enctype="multipart/form-data" action="', action, '">',
        '<div class="card"><h2>', htmlEscape(_("Text")), '</h2>',
        '<label>', htmlEscape(_("Title")), '</label><input type="text" name="title" autocomplete="off">',
        '<label>', htmlEscape(_("Artist")), '</label><input type="text" name="artist" autocomplete="off">',
        '<label>', htmlEscape(_("Tab or chords")), '</label><textarea name="text" spellcheck="false" autocapitalize="off" autocorrect="off"></textarea>',
        '<button class="btn" type="submit">', htmlEscape(_("Send")), '</button></div>',
        '</form>',
        '<form method="post" enctype="multipart/form-data" action="', action, '">',
        '<div class="card"><h2>', htmlEscape(_("Link")), '</h2>',
        '<input type="text" name="link" inputmode="url" autocomplete="off" autocapitalize="off" placeholder="https://…">',
        '<p class="hint">', htmlEscape(_("Links are remembered. With the Ultimate Guitar module switched on (Tools → Guitar Tab Reader), the tab is loaded right away.")), '</p>',
        '<button class="btn" type="submit">', htmlEscape(_("Send")), '</button></div>',
        '</form>',
    })
end

function Receiver:resultPage(results, errors)
    local lines = {}
    for _i, r in ipairs(results) do
        local label = r.kind == "link" and _("Link remembered: %1") or _("Received: %1")
        lines[#lines + 1] = '<p class="ok">✓ ' .. htmlEscape(T(label, r.name)) .. '</p>'
    end
    for _i, e in ipairs(errors) do lines[#lines + 1] = '<p class="err">✗ ' .. htmlEscape(e) .. '</p>' end
    if #lines == 0 then lines[1] = '<p>' .. htmlEscape(_("Nothing received.")) .. '</p>' end
    return page(_("Sent"), '<div class="card">' .. table.concat(lines) ..
        '<a class="btn" style="text-align:center;text-decoration:none" href="/?t=' .. self.token .. '">' .. htmlEscape(_("Send more")) .. '</a></div>')
end

return Receiver
