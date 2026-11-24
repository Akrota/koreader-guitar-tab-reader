--[[--
The Ultimate Guitar module in the user interface: switching it on,
loading remembered links (from the phone page) and the search
on the e-reader. Requests go out one at a time with a pause in between.
--]]

local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local UG = require("tabreader/ug")
local _ = require("tabreader/i18n")
local T = require("ffi/util").template

local UGMenu = {}

local PAUSE = 1.5 -- seconds between two requests
local MAX_PER_RUN = 10

local REASONS = {
    network = _("no connection"),
    blocked = _("Ultimate Guitar blocked the request"),
    nodata = _("no tab found on the page"),
    pro = _("Pro or official tab (not supported)"),
    type = _("not a guitar tab"),
    write = _("could not save the file"),
}

function UGMenu.reason(err)
    return REASONS[err] or tostring(err)
end

--- Ask before switching the module on.
function UGMenu.confirmEnable(plugin, on_done)
    UIManager:show(ConfirmBox:new{
        text = _("Ultimate Guitar module\n\nLoads public tabs from ultimate-guitar.com: links you send and a search on the e-reader.\n\nPlease note: this is a grey area and not fully in line with Ultimate Guitar's terms of use. Use it at your own risk. Ultimate Guitar may block access at any time.\n\nSwitch it on?"),
        ok_text = _("Switch on"),
        ok_callback = function()
            plugin:setSetting("ug_enabled", true)
            if on_done then on_done() end
        end,
    })
end

local function openQueue(folder)
    return LuaSettings:open(folder .. "/.tabreader/links.lua")
end

--- Links still waiting to be loaded.
function UGMenu.pendingLinks(folder)
    local links = openQueue(folder):readSetting("links") or {}
    local pending = {}
    for i, link in ipairs(links) do
        if not link.done then pending[#pending + 1] = i end
    end
    return pending, links
end

-- Write the state of the links handled in this run back. Re-reads the file first:
-- the receiver may have added new links in the meantime (between two loads).
local function saveHandled(folder, handled)
    local queue = openQueue(folder)
    local links = queue:readSetting("links") or {}
    for _i, link in ipairs(links) do
        for _j, h in ipairs(handled) do
            if link.url == h.url and link.added == h.added then
                link.done, link.file, link.error = h.done, h.file, h.error
            end
        end
    end
    queue:saveSetting("links", links)
    queue:flush()
end

--- Load remembered links one by one.
-- @param on_finished function(loaded, failed) or nil
function UGMenu.loadQueue(plugin, on_finished)
    local folder = plugin:getFolder()
    local pending, links = UGMenu.pendingLinks(folder)
    if #pending == 0 then
        if on_finished then on_finished({}, {}) end
        return
    end
    local loaded, failed, handled = {}, {}, {}
    local msg
    local idx = 0
    local function step()
        if msg then UIManager:close(msg); msg = nil end
        idx = idx + 1
        local i = pending[idx]
        if not i or idx > MAX_PER_RUN then
            saveHandled(folder, handled)
            if on_finished then on_finished(loaded, failed) end
            return
        end
        local link = links[i]
        handled[#handled + 1] = link
        if not UG.isTabLink(link.url) then
            link.done, link.error = true, "unsupported"
            failed[#failed + 1] = { url = link.url, reason = _("not an Ultimate Guitar tab link") }
            return step()
        end
        msg = InfoMessage:new{ text = T(_("Loading tab %1 of %2 …"), idx, math.min(#pending, MAX_PER_RUN)) }
        UIManager:show(msg)
        UIManager:forceRePaint()
        local tab, err = UG.fetchTab(link.url)
        local path, rel
        if tab then path, rel = UG.save(tab, folder) end
        if path then
            link.done, link.file, link.error = true, rel, nil
            loaded[#loaded + 1] = { name = rel:match("[^/]+$"), rel = rel }
        else
            err = err or "write"
            link.error = err
            -- try again later only if it may work then (network, block)
            if err ~= "network" and err ~= "blocked" then link.done = true end
            failed[#failed + 1] = { url = link.url, reason = UGMenu.reason(err) }
            if err == "blocked" or err == "network" then idx = MAX_PER_RUN end -- stop for now
        end
        saveHandled(folder, handled)
        UIManager:scheduleIn(PAUSE, step)
    end
    step()
end

--- Short report after loading.
function UGMenu.report(loaded, failed)
    if #loaded == 0 and #failed == 0 then return end
    local lines = {}
    for _i, l in ipairs(loaded) do lines[#lines + 1] = "✓ " .. l.name end
    for _i, f in ipairs(failed) do lines[#lines + 1] = "✗ " .. f.url .. "\n   " .. f.reason end
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n"), timeout = #failed > 0 and nil or 4 })
end

local function resultText(r)
    local parts = { r.type }
    if r.version and tonumber(r.version) and tonumber(r.version) > 1 then parts[#parts + 1] = "v" .. r.version end
    if r.rating and r.votes and r.votes > 0 then
        parts[#parts + 1] = string.format("★%.1f (%d)", r.rating, r.votes)
    end
    return table.concat(parts, " · ")
end

--- Search on the e-reader: query → results → load and open.
-- @param on_open function(rel) opens a saved tab
function UGMenu.showSearch(plugin, on_open)
    local dialog
    dialog = InputDialog:new{
        title = _("Search Ultimate Guitar"),
        input = plugin:getSetting("ug_last_query") or "",
        input_hint = _("Song or artist"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            -- the last search stays in the field (to pick another version);
            -- this empties it for a new one
            { text = _("Clear"), callback = function() dialog:setInputText("") end },
            { text = _("Search"), is_enter_default = true, callback = function()
                local query = dialog:getInputText():gsub("^%s+", ""):gsub("%s+$", "")
                if query == "" then return end
                UIManager:close(dialog)
                plugin:setSetting("ug_last_query", query)
                UGMenu.runSearch(plugin, query, 1, on_open)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function UGMenu.runSearch(plugin, query, page, on_open)
    local msg = InfoMessage:new{ text = _("Searching …") }
    UIManager:show(msg)
    UIManager:forceRePaint()
    local results, pages = UG.search(query, page)
    UIManager:close(msg)
    if not results then
        UIManager:show(InfoMessage:new{ text = T(_("Search failed: %1"), UGMenu.reason(pages)) })
        return
    end
    if #results == 0 then
        UIManager:show(InfoMessage:new{ text = T(_("No guitar tabs found for \"%1\"."), query) })
        return
    end
    local menu
    local items = {}
    for _i, r in ipairs(results) do
        items[#items + 1] = {
            text = (r.title or "?") .. " – " .. (r.artist or "?"),
            mandatory = resultText(r),
            result = r,
        }
    end
    if pages and page < pages then
        items[#items + 1] = { text = _("More results …"), more = true }
    end
    menu = Menu:new{
        title = T(_("Results for \"%1\""), query),
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        onMenuChoice = function(_m, item)
            if item.more then
                UIManager:close(menu)
                UGMenu.runSearch(plugin, query, page + 1, on_open)
                return true
            end
            local m = InfoMessage:new{ text = _("Loading tab …") }
            UIManager:show(m)
            UIManager:forceRePaint()
            local tab, err = UG.fetchTab(item.result.url)
            local path, rel
            if tab then path, rel = UG.save(tab, plugin:getFolder()) end
            UIManager:close(m)
            if not path then
                UIManager:show(InfoMessage:new{ text = T(_("The tab could not be loaded: %1"), UGMenu.reason(err or "write")) })
                return true
            end
            UIManager:close(menu)
            if on_open then on_open(rel) end
            return true
        end,
    }
    UIManager:show(menu)
end

return UGMenu
