--[[--
Setlists: named lists of tabs in a fixed order, for practising or playing a
set. Long-press a tab in the library to add it. Played from a setlist, the
last page of a song leads straight to the next one. Stored in the hidden
data folder of the tab folder.
--]]

local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local util = require("util")
local _ = require("tabreader/i18n")
local T = require("ffi/util").template

local Setlists = {}

local function store(plugin)
    local dir = plugin:getFolder() .. "/.tabreader"
    util.makePath(dir)
    return LuaSettings:open(dir .. "/setlists.lua")
end

function Setlists.load(plugin)
    return store(plugin):readSetting("lists") or {}
end

function Setlists.save(plugin, lists)
    local s = store(plugin)
    s:saveSetting("lists", lists)
    s:flush()
end

--- Add a tab to a list (no duplicates).
-- @return true if added
function Setlists.add(lists, index, rel)
    local list = lists[index]
    for _i, r in ipairs(list.items) do if r == rel then return false end end
    table.insert(list.items, rel)
    return true
end

--- Take deleted tabs out of every setlist.
-- @param gone set of rel paths
function Setlists.removeTabs(plugin, gone)
    local lists = Setlists.load(plugin)
    local changed = false
    for _i, list in ipairs(lists) do
        for j = #list.items, 1, -1 do
            if gone[list.items[j]] then
                table.remove(list.items, j)
                changed = true
            end
        end
    end
    if changed then Setlists.save(plugin, lists) end
end

function Setlists.move(list, i, delta)
    local j = i + delta
    if j < 1 or j > #list.items then return end
    list.items[i], list.items[j] = list.items[j], list.items[i]
end

local function askName(title, value, on_ok)
    local dialog
    dialog = InputDialog:new{
        title = title,
        input = value or "",
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("OK"), is_enter_default = true, callback = function()
                local name = dialog:getInputText():gsub("^%s+", ""):gsub("%s+$", "")
                UIManager:close(dialog)
                if name ~= "" then on_ok(name) end
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

--- Long-press on a tab: add it to a setlist.
function Setlists.addDialog(plugin, rel, title)
    local lists = Setlists.load(plugin)
    local dialog
    local function added(i)
        if Setlists.add(lists, i, rel) then
            Setlists.save(plugin, lists)
            UIManager:show(InfoMessage:new{ text = T(_("Added to \"%1\"."), lists[i].name), timeout = 2 })
        else
            UIManager:show(InfoMessage:new{ text = T(_("Already in \"%1\"."), lists[i].name), timeout = 2 })
        end
    end
    local buttons = {}
    for i, list in ipairs(lists) do
        buttons[#buttons + 1] = {{ text = T("%1 (%2)", list.name, #list.items), callback = function()
            UIManager:close(dialog)
            added(i)
        end }}
    end
    buttons[#buttons + 1] = {{ text = _("New setlist …"), callback = function()
        UIManager:close(dialog)
        askName(_("Name of the new setlist"), nil, function(name)
            lists[#lists + 1] = { name = name, items = {} }
            added(#lists)
        end)
    end }}
    dialog = ButtonDialog:new{ title = T(_("Add \"%1\" to a setlist"), title or rel), title_align = "center", buttons = buttons }
    UIManager:show(dialog)
end

--- Play a setlist from song i on: each song leads to the next.
function Setlists.play(plugin, list, i)
    local library = plugin.library or plugin:openLibrary()
    if not library then return end
    -- skip songs whose file is gone
    while list.items[i] and not library.titleOf(list.items[i]) do i = i + 1 end
    local rel = list.items[i]
    if not rel then return end
    local next_i = i + 1
    while list.items[next_i] and not library.titleOf(list.items[next_i]) do next_i = next_i + 1 end
    local next_rel = list.items[next_i]
    library.openRel(rel, {
        setlist = true,
        next_title = next_rel and library.titleOf(next_rel) or nil,
        on_next = next_rel and function() Setlists.play(plugin, list, next_i) end or nil,
    })
end

--- The songs of one setlist.
--- @param on_change optional, called after the list was changed (refreshes the overview)
function Setlists.showList(plugin, index, on_change)
    local lists = Setlists.load(plugin)
    local list = lists[index]
    if not list then return end
    local library = plugin.library or plugin:openLibrary()
    local menu
    local function items()
        local t = {}
        if #list.items > 0 then
            t[#t + 1] = { text = "▶ " .. _("Play setlist"), play = 1 }
        else
            t[#t + 1] = { text = _("Empty. Long-press a tab in the library to add it."), select_enabled = false }
        end
        for i, rel in ipairs(list.items) do
            local title = library and library.titleOf(rel)
            t[#t + 1] = { text = T("%1. %2", i, title or (rel .. " " .. _("(missing)"))), song = i, dim = not title }
        end
        return t
    end
    menu = Menu:new{
        title = list.name,
        item_table = items(),
        covers_fullscreen = true, is_borderless = true, is_popout = false,
        onMenuChoice = function(_m, item)
            if item.play then Setlists.play(plugin, list, 1)
            elseif item.song then Setlists.play(plugin, list, item.song) end
            return true
        end,
        onMenuHold = function(_m, item)
            if not item.song then return true end
            local i = item.song
            local dialog
            local function change(fn)
                return function()
                    UIManager:close(dialog)
                    fn()
                    Setlists.save(plugin, lists)
                    menu:switchItemTable(nil, items())
                    if on_change then on_change() end
                end
            end
            dialog = ButtonDialog:new{ buttons = {
                {{ text = _("Move up"), enabled = i > 1, callback = change(function() Setlists.move(list, i, -1) end) }},
                {{ text = _("Move down"), enabled = i < #list.items, callback = change(function() Setlists.move(list, i, 1) end) }},
                {{ text = _("Remove from setlist"), callback = change(function() table.remove(list.items, i) end) }},
            }}
            UIManager:show(dialog)
            return true
        end,
    }
    UIManager:show(menu)
end

--- All setlists.
function Setlists.show(plugin)
    local lists = Setlists.load(plugin)
    local menu
    local function items()
        -- always from disk: the song list view saves its own changes
        lists = Setlists.load(plugin)
        local t = {}
        for i, list in ipairs(lists) do
            t[#t + 1] = { text = list.name, mandatory = tostring(#list.items), index = i }
        end
        t[#t + 1] = { text = _("New setlist …"), new = true }
        return t
    end
    menu = Menu:new{
        title = _("Setlists"),
        item_table = items(),
        covers_fullscreen = true, is_borderless = true, is_popout = false,
        onMenuChoice = function(_m, item)
            if item.new then
                askName(_("Name of the new setlist"), nil, function(name)
                    lists[#lists + 1] = { name = name, items = {} }
                    Setlists.save(plugin, lists)
                    menu:switchItemTable(nil, items())
                end)
            elseif item.index then
                Setlists.showList(plugin, item.index, function() menu:switchItemTable(nil, items(), -1) end)
            end
            return true
        end,
        onMenuHold = function(_m, item)
            if not item.index then return true end
            local dialog
            dialog = ButtonDialog:new{ buttons = {
                {{ text = _("Rename"), callback = function()
                    UIManager:close(dialog)
                    askName(_("Rename setlist"), lists[item.index].name, function(name)
                        lists[item.index].name = name
                        Setlists.save(plugin, lists)
                        menu:switchItemTable(nil, items())
                    end)
                end }},
                {{ text = _("Delete setlist"), callback = function()
                    UIManager:close(dialog)
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Delete the setlist \"%1\"? The tabs stay in the library."), lists[item.index].name),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            table.remove(lists, item.index)
                            Setlists.save(plugin, lists)
                            menu:switchItemTable(nil, items())
                        end,
                    })
                end }},
            }}
            UIManager:show(dialog)
            return true
        end,
    }
    UIManager:show(menu)
end

return Setlists
