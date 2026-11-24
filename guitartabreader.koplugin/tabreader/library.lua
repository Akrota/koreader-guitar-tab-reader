--[[--
The tab library: every tab file in the tab folder (and its subfolders),
newest-played first. Files dropped into the folder (USB or from the phone)
show up automatically. The plugin's own data (last page, font size per tab)
lives in a hidden subfolder, so the user's files stay untouched.
--]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local Parser = require("tabreader/parser")
local PdfImport = require("tabreader/pdfimport")
local Extra = require("tabreader/extra")
local _ = require("tabreader/i18n")
local T = require("ffi/util").template

local Library = {}

Library.DATA_DIR = ".tabreader"
local TEXT_FORMATS = { txt = true, tab = true, crd = true, cho = true, chopro = true, chordpro = true, pro = true }
local MAX_DEPTH = 4
local MAX_FILES = 5000

--- Make sure the folder exists.
function Library.ensureFolder(folder)
    if lfs.attributes(folder, "mode") ~= "directory" then
        local ok = util.makePath(folder)
        if not ok then return false end
    end
    return true
end

--- All tab files below the folder.
-- @return list of { path, rel, name, ext }
function Library.scan(folder)
    local files = {}
    local function walk(dir, rel, depth)
        if depth > MAX_DEPTH or #files >= MAX_FILES then return end
        local ok, iter, state = pcall(lfs.dir, dir)
        if not ok then return end
        for entry in iter, state do
            if entry:sub(1, 1) ~= "." then
                local path = dir .. "/" .. entry
                local mode = lfs.attributes(path, "mode")
                local rel_path = rel == "" and entry or (rel .. "/" .. entry)
                if mode == "directory" then
                    walk(path, rel_path, depth + 1)
                elseif mode == "file" then
                    local ext = entry:match("%.([%w]+)$")
                    ext = ext and ext:lower()
                    if ext and (TEXT_FORMATS[ext] or ext == "pdf") then
                        files[#files + 1] = { path = path, rel = rel_path, name = entry, ext = ext }
                    end
                end
            end
        end
    end
    walk(folder, "", 1)
    return files
end

local function readFile(path, limit)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read(limit or "*a")
    f:close()
    return s
end

-- PDF cache: reading a PDF takes a moment on the e-reader, so the result is
-- kept (as text plus details) until the file changes.
local function cachePath(folder, file)
    local key = file.rel:gsub("[/\\]", "__")
    return folder .. "/" .. Library.DATA_DIR .. "/cache/" .. key .. ".lua"
end

--- Read a PDF, from the cache if the file is unchanged.
-- @return model or nil, error
function Library.loadPdf(folder, file)
    local attr = lfs.attributes(file.path) or {}
    local stamp = tostring(attr.size) .. ":" .. tostring(attr.modification)
    local path = cachePath(folder, file)
    local cache = LuaSettings:open(path)
    if cache:readSetting("stamp") == stamp then
        if cache:readSetting("text") then
            return Parser.fromText(cache:readSetting("text"), cache:readSetting("meta") or {})
        end
        -- this very file could not be read before: do not try again and again
        if cache:readSetting("failed") then return nil, cache:readSetting("failed") end
    end
    local model, err, text = PdfImport.read(file.path)
    Library.ensureFolder(folder .. "/" .. Library.DATA_DIR .. "/cache")
    if not model then
        cache:saveSetting("stamp", stamp)
        cache:saveSetting("failed", tostring(err))
        cache:flush()
        return nil, err
    end
    cache:delSetting("failed")
    local meta = {}
    for k, v in pairs(model.meta) do meta[k] = v end
    cache:saveSetting("stamp", stamp)
    cache:saveSetting("text", text)
    cache:saveSetting("meta", meta)
    cache:flush()
    return model
end

--- Title and artist for the list, cheaply: ChordPro header, PDF cache or "Artist - Title" file name.
-- @param pdf_meta optional: the PDF's cached details, if already at hand
function Library.quickInfo(file, folder, pdf_meta)
    local base = file.name:gsub("%.[^.]+$", "")
    local artist, title = base:match("^(.-)%s+%-%s+(.+)$")
    title, artist = title or base, artist
    if file.ext == "pdf" and folder then
        local meta = pdf_meta or LuaSettings:open(cachePath(folder, file)):readSetting("meta")
        if meta and meta.title then title, artist = meta.title, meta.artist or artist end
    end
    if file.ext ~= "pdf" then
        local head = readFile(file.path, 2048) or ""
        title = head:match("{%s*title%s*:%s*(.-)%s*}") or head:match("{%s*t%s*:%s*(.-)%s*}") or title
        artist = head:match("{%s*artist%s*:%s*(.-)%s*}") or head:match("{%s*subtitle%s*:%s*(.-)%s*}") or artist
    end
    return title, artist
end

--- Per-tab state (last page, font size, last opened), stored in the tab folder.
function Library.openState(folder)
    Library.ensureFolder(folder .. "/" .. Library.DATA_DIR)
    return LuaSettings:open(folder .. "/" .. Library.DATA_DIR .. "/state.lua")
end

--- Parse a tab file.
-- @return model or nil, error text
function Library.load(file, folder)
    local model
    if file.ext == "pdf" then
        local err
        model, err = Library.loadPdf(folder, file)
        if not model then return nil, T(_("The PDF could not be read (%1)."), tostring(err)) end
    else
        local content = readFile(file.path)
        if not content then return nil, _("The file could not be read.") end
        content = util.fixUtf8(content, "?")
        model = Parser.parse(content, file.name)
    end
    -- chord shapes etc. (tabs from Ultimate Guitar)
    local extra = folder and Extra.load(folder, file.rel)
    if extra then model.chords = extra.chords end
    return model
end

--- Delete tab files together with what the plugin kept about them
-- (last page etc., PDF cache, chord shapes).
-- @return set of deleted rel paths, number of files that could not be deleted
function Library.deleteFiles(folder, files)
    local state = Library.openState(folder)
    local entries = state:readSetting("tabs") or {}
    local gone, failed = {}, 0
    for _i, file in ipairs(files) do
        if os.remove(file.path) then
            gone[file.rel] = true
            entries[file.rel] = nil
            os.remove(cachePath(folder, file))
            Extra.remove(folder, file.rel)
        else
            failed = failed + 1
        end
    end
    state:saveSetting("tabs", entries)
    state:flush()
    return gone, failed
end

-- Recently played first, then alphabetically.
local function byRecent(a, b)
    if a.last_opened ~= b.last_opened then return a.last_opened > b.last_opened end
    return a.sort_title < b.sort_title
end

--- Show the library.
-- @param opts { folder, open = function(file, model, state_entry, on_close),
--               on_menu = function(menu) (☰ button), on_close = function(),
--               on_hold = function(file, title), on_deleted = function(gone) }
-- @return menu, with menu.refresh() to rescan the folder
function Library.show(opts)
    local folder = opts.folder
    if not Library.ensureFolder(folder) then
        UIManager:show(InfoMessage:new{ text = T(_("The tab folder could not be created:\n%1"), folder) })
        return
    end
    local state = Library.openState(folder)
    local menu

    local function buildItems()
        local files = Library.scan(folder)
        local entries = state:readSetting("tabs") or {}
        local items = {}
        local warmed = 0
        for _i, file in ipairs(files) do
            -- PDFs read for the first time get their real title (a few per opening)
            local meta
            if file.ext == "pdf" then
                local cache = LuaSettings:open(cachePath(folder, file))
                meta = cache:readSetting("meta")
                if not meta and not cache:readSetting("failed") and warmed < 10 then
                    warmed = warmed + 1
                    local ok, model = pcall(Library.loadPdf, folder, file)
                    meta = ok and model and model.meta or nil
                end
            end
            local title, artist = Library.quickInfo(file, folder, meta)
            local entry = entries[file.rel] or {}
            items[#items + 1] = {
                text = artist and (title .. " – " .. artist) or title,
                mandatory = file.ext == "pdf" and "PDF" or nil,
                file = file,
                sort_title = title:lower(),
                last_opened = entry.last_opened or 0,
            }
        end
        table.sort(items, byRecent)
        if #items == 0 then
            items[1] = { text = T(_("No tabs yet. Put text tabs (.txt) or ChordPro files (.cho) into:\n%1"), folder), select_enabled = false }
        end
        return items
    end

    menu = Menu:new{
        title = "Guitar Tab Reader",
        subtitle = folder,
        item_table = buildItems(),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function() if opts.on_menu then opts.on_menu(menu) end end,
        close_callback = function() if opts.on_close then opts.on_close() end end,
        onMenuChoice = function(_menu, item)
            if item.file then menu.openFile(item.file) end
            return true
        end,
        onMenuHold = function(_menu, item)
            if item.file and opts.on_hold then opts.on_hold(item.file, item.text) end
            return true
        end,
    }
    menu.refresh = function() menu:switchItemTable(nil, buildItems()) end
    --- Open a tab; extra = { next_title, on_next } for setlists.
    menu.openFile = function(file, extra)
        local model, err = Library.load(file, folder)
        if not model then
            UIManager:show(InfoMessage:new{ text = err })
            return
        end
        local entries = state:readSetting("tabs") or {}
        local entry = entries[file.rel] or {}
        opts.open(file, model, entry, function(result)
            entries = state:readSetting("tabs") or {}
            entries[file.rel] = {
                last_opened = os.time(),
                last_page = result.page,
                font_size = result.font_size,
                transpose = result.transpose ~= 0 and result.transpose or nil,
            }
            state:saveSetting("tabs", entries)
            state:flush()
            -- Move the tab to the top without rescanning the folder (this
            -- runs between two songs of a setlist, so it has to be quick).
            for _i, item in ipairs(menu.item_table) do
                if item.file and item.file.rel == file.rel then item.last_opened = entries[file.rel].last_opened end
            end
            table.sort(menu.item_table, byRecent)
            menu:switchItemTable(nil, menu.item_table)
        end, extra)
    end
    --- Open a tab by its path inside the folder (after loading it, or from a setlist).
    -- @return true if the file exists
    menu.openRel = function(rel, extra)
        for _i, item in ipairs(menu.item_table) do
            if item.file and item.file.rel == rel then
                menu.openFile(item.file, extra)
                return true
            end
        end
        return false
    end
    --- Title and artist of a tab, for lists.
    menu.titleOf = function(rel)
        for _i, item in ipairs(menu.item_table) do
            if item.file and item.file.rel == rel then return item.text end
        end
    end
    --- Ask, then delete the files and refresh the list.
    -- @param on_done optional, called after deleting
    menu.confirmDelete = function(files, on_done)
        if #files == 0 then return end
        local text
        if #files == 1 then
            text = T(_("Delete \"%1\"?"), menu.titleOf(files[1].rel) or files[1].name)
        else
            text = T(_("Delete %1 tabs?"), #files)
        end
        UIManager:show(ConfirmBox:new{
            text = text .. "\n\n" .. _("The files are removed from the e-reader."),
            ok_text = _("Delete"),
            ok_callback = function()
                local gone, failed = Library.deleteFiles(folder, files)
                if opts.on_deleted then opts.on_deleted(gone) end
                menu.refresh()
                if failed > 0 then
                    UIManager:show(InfoMessage:new{ text = T(_("%1 file(s) could not be deleted."), failed) })
                end
                if on_done then on_done() end
            end,
        })
    end
    --- Pick several tabs with check marks, then delete them.
    -- @param preselect optional rel path that starts checked
    menu.showSelect = function(preselect)
        local checked = {}
        if preselect then checked[preselect] = true end
        local select_menu
        local function count()
            local n = 0
            for _rel in pairs(checked) do n = n + 1 end
            return n
        end
        local function items()
            local t = {}
            for _i, item in ipairs(menu.item_table) do
                if item.file then
                    t[#t + 1] = {
                        text = (checked[item.file.rel] and "☑ " or "☐ ") .. item.text,
                        mandatory = item.mandatory,
                        file = item.file,
                    }
                end
            end
            return t
        end
        local function update()
            -- -1: stay on the current page
            select_menu:switchItemTable(T(_("Selected: %1"), count()), items(), -1)
        end
        local function selected()
            local files = {}
            for _i, item in ipairs(menu.item_table) do
                if item.file and checked[item.file.rel] then files[#files + 1] = item.file end
            end
            return files
        end
        select_menu = Menu:new{
            title = T(_("Selected: %1"), count()),
            subtitle = _("Tap tabs to check them, then ☰ → Delete."),
            item_table = items(),
            covers_fullscreen = true,
            is_borderless = true,
            is_popout = false,
            title_bar_left_icon = "appbar.menu",
            onMenuChoice = function(_m, item)
                checked[item.file.rel] = not checked[item.file.rel] or nil
                update()
                return true
            end,
            onLeftButtonTap = function()
                local dialog
                local n = count()
                dialog = ButtonDialog:new{ buttons = {
                    {{ text = T(_("Delete selected (%1)"), n), enabled = n > 0, callback = function()
                        UIManager:close(dialog)
                        menu.confirmDelete(selected(), function() UIManager:close(select_menu) end)
                    end }},
                    {{ text = _("Select all"), callback = function()
                        UIManager:close(dialog)
                        for _i, item in ipairs(menu.item_table) do
                            if item.file then checked[item.file.rel] = true end
                        end
                        update()
                    end }},
                    {{ text = _("Clear selection"), enabled = n > 0, callback = function()
                        UIManager:close(dialog)
                        checked = {}
                        update()
                    end }},
                }}
                UIManager:show(dialog)
            end,
        }
        UIManager:show(select_menu)
        return select_menu
    end
    UIManager:show(menu)
    return menu
end

return Library
