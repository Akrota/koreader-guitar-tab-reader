--[[--
Guitar Tab Reader: guitar tabs and chord sheets on the e-reader, laid out
for e-ink. Tabs come from a tab folder, from the phone (receiver page with QR
code), from Ultimate Guitar PDFs and, with the Ultimate Guitar module switched
on, from Ultimate Guitar links and search. This file wires the parts
together: menus, settings, receiver, library, viewer, setlists.
--]]

local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local AddDialog = require("tabreader/adddialog")
local ButtonDialog = require("ui/widget/buttondialog")
local Library = require("tabreader/library")
local Receiver = require("tabreader/receiver")
local UGMenu = require("tabreader/ugmenu")
local Setlists = require("tabreader/setlists")
local Viewer = require("tabreader/viewer")
local _ = require("tabreader/i18n")
local T = require("ffi/util").template

local SETTINGS_KEY = "guitar_tab_reader"
local DEFAULT_FONT_SIZE = 14

local HELP_TEXT = "Guitar Tab Reader shows guitar tabs and chord sheets, laid out for e-ink.\n\n"
    .. "Getting tabs in:\n"
    .. "• Copy text tabs (.txt), ChordPro files (.cho) or PDFs into the tab folder (GuitarTabs).\n"
    .. "• Library → ☰ → Add tab (phone): scan the QR code and send a file, text or link. Phone and e-reader need the same Wi-Fi.\n"
    .. "• Ultimate Guitar (experimental, off by default): load links and search.\n\n"
    .. "In the library: tap a tab to open it. Hold a tab to add it to a setlist, delete it or select several.\n\n"
    .. "While playing: tap right or left (or swipe) to turn pages. ☰ at the top left: font size, transpose, tab size, chord diagrams, automatic page turning. Tap a chord to see how to play it.\n\n"
    .. "Each tab remembers its page, font size and transposition."

local GuitarTabReader = WidgetContainer:extend{
    name = "guitartabreader",
    is_doc_only = false, -- available in the file browser and while reading
}

--- Default tab folder: "GuitarTabs" in the device's main folder (Kobo: /mnt/onboard).
local function defaultFolder()
    local home = Device.home_dir or G_reader_settings:readSetting("home_dir") or require("datastorage"):getDataDir()
    return home .. "/GuitarTabs"
end

function GuitarTabReader:init()
    self.settings = G_reader_settings:readSetting(SETTINGS_KEY, {})
    -- Our entry at the top of the Tools menu, both in the file browser and in
    -- the reader. The plugins used most often share one fixed order there,
    -- whichever is loaded first.
    local TOP = { "story_recall", "guitar_tab_reader", "comicdisplay" }
    for _i, order_name in ipairs({ "ui/elements/filemanager_menu_order", "ui/elements/reader_menu_order" }) do
        local ok, order = pcall(require, order_name)
        local tools = ok and order.tools
        if tools then
            for i = #tools, 1, -1 do if tools[i] == "guitar_tab_reader" then table.remove(tools, i) end end
            local my_rank, pos = util.arrayContains(TOP, "guitar_tab_reader"), 1
            for i, key in ipairs(tools) do
                local rank = util.arrayContains(TOP, key)
                if rank and rank < my_rank then pos = i + 1 end
            end
            table.insert(tools, pos, "guitar_tab_reader")
        end
    end
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
end

function GuitarTabReader:onDispatcherRegisterActions()
    Dispatcher:registerAction("guitartabreader_open", {
        category = "none", event = "GuitarTabReaderOpen", title = _("Guitar Tab Reader: open library"), general = true,
    })
    Dispatcher:registerAction("guitartabreader_setlists", {
        category = "none", event = "GuitarTabReaderSetlists", title = _("Guitar Tab Reader: setlists"), general = true,
    })
    Dispatcher:registerAction("guitartabreader_search", {
        category = "none", event = "GuitarTabReaderSearch", title = _("Guitar Tab Reader: search Ultimate Guitar"), general = true,
    })
end

function GuitarTabReader:onGuitarTabReaderSetlists()
    if self:openLibrary() then Setlists.show(self) end
    return true
end

function GuitarTabReader:onGuitarTabReaderSearch()
    if not self:ugEnabled() then
        UIManager:show(InfoMessage:new{ text = _("Switch on the Ultimate Guitar module first (Tools → Guitar Tab Reader → Ultimate Guitar)."), timeout = 4 })
        return true
    end
    self:openLibrary()
    self:showSearch()
    return true
end

function GuitarTabReader:getSetting(key) return self.settings[key] end

function GuitarTabReader:setSetting(key, value)
    self.settings[key] = value
    G_reader_settings:saveSetting(SETTINGS_KEY, self.settings)
end

function GuitarTabReader:getFolder()
    return self:getSetting("folder") or defaultFolder()
end

function GuitarTabReader:onGuitarTabReaderOpen()
    self:openLibrary()
    return true
end

function GuitarTabReader:openLibrary()
    if self.ui.menu and self.ui.menu.onCloseFileManagerMenu then self.ui.menu:onCloseFileManagerMenu() end
    if self.ui.menu and self.ui.menu.onCloseReaderMenu then self.ui.menu:onCloseReaderMenu() end
    if self.library then return self.library end
    self.library = Library.show{
        folder = self:getFolder(),
        open = function(file, model, entry, on_close, extra)
            return self:openTab(model, entry, on_close, extra)
        end,
        on_hold = function(file, title) self:showTabActions(file, title) end,
        on_deleted = function(gone) Setlists.removeTabs(self, gone) end,
        on_menu = function() self:showLibraryMenu() end,
        on_close = function()
            self.library = nil
            self:stopReceiver()
        end,
    }
    if not self.library then return end
    self:startReceiver()
    return self.library
end

-- Receiving tabs from the phone: runs while the library is open.

function GuitarTabReader:getToken()
    local token = self:getSetting("receiver_token")
    if not token then
        token = Receiver.randomToken()
        self:setSetting("receiver_token", token)
    end
    return token
end

function GuitarTabReader:startReceiver()
    if self.receiver then return self.receiver end
    local NetworkMgr = require("ui/network/manager")
    if not NetworkMgr:isConnected() then return nil, "offline" end
    local receiver, err = Receiver.start{
        folder = self:getFolder(),
        token = self:getToken(),
        on_received = function(results) self:onTabsReceived(results) end,
    }
    self.receiver = receiver
    return receiver, err
end

function GuitarTabReader:stopReceiver()
    if self.receiver then
        self.receiver:stop()
        self.receiver = nil
    end
end

function GuitarTabReader:ugEnabled()
    return self:getSetting("ug_enabled") == true
end

--- Load remembered links (Ultimate Guitar module), then refresh and report.
function GuitarTabReader:loadLinks()
    if not self:ugEnabled() or self.loading_links then return end
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenConnected(function()
        self.loading_links = true
        UGMenu.loadQueue(self, function(loaded, failed)
            self.loading_links = false
            if self.library and #loaded > 0 then self.library.refresh() end
            UGMenu.report(loaded, failed)
        end)
    end)
end

--- UG search; a loaded tab opens right away.
function GuitarTabReader:showSearch()
    if not self:ugEnabled() then return end
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenConnected(function()
        UGMenu.showSearch(self, function(rel)
            local library = self:openLibrary()
            if library then
                library.refresh()
                library.openRel(rel)
            end
        end)
    end)
end

function GuitarTabReader:onTabsReceived(results)
    if self.library then self.library.refresh() end
    local names = {}
    for _i, r in ipairs(results) do
        names[#names + 1] = (r.kind == "link" and _("Link remembered: ") or "") .. r.name
    end
    local has_link = false
    for _i, r in ipairs(results) do if r.kind == "link" then has_link = true end end
    if has_link and self:ugEnabled() then
        -- load right away (after the phone got its answer)
        UIManager:scheduleIn(1, function() self:loadLinks() end)
    else
        local text = _("Received:") .. "\n" .. table.concat(names, "\n")
        if has_link then
            text = text .. "\n\n" .. _("Links are loaded once the Ultimate Guitar module is switched on (Tools → Guitar Tab Reader → Ultimate Guitar).")
        end
        UIManager:show(InfoMessage:new{ text = text, timeout = has_link and 6 or 3 })
    end
end

--- "Add tab": QR code and address of the receiver page.
function GuitarTabReader:showAddDialog()
    local receiver, err = self:startReceiver()
    if not receiver then
        if err == "offline" then
            local NetworkMgr = require("ui/network/manager")
            NetworkMgr:runWhenConnected(function() self:showAddDialog() end)
        else
            UIManager:show(InfoMessage:new{ text = err or _("The receiver could not be started.") })
        end
        return
    end
    UIManager:show(AddDialog:new{ url = receiver.page_url })
end

function GuitarTabReader:showLibraryMenu()
    local dialog
    local function button(text, fn, enabled)
        return {{ text = text, enabled = enabled ~= false, callback = function()
            UIManager:close(dialog)
            fn()
        end }}
    end
    local buttons = {}
    if self:ugEnabled() then
        local pending = #UGMenu.pendingLinks(self:getFolder())
        table.insert(buttons, button(_("Search Ultimate Guitar"), function() self:showSearch() end))
        table.insert(buttons, button(T(_("Load remembered links (%1)"), pending), function() self:loadLinks() end, pending > 0))
    end
    table.insert(buttons, button(_("Setlists"), function() Setlists.show(self) end))
    table.insert(buttons, button(_("Add tab (phone)"), function() self:showAddDialog() end))
    table.insert(buttons, button(_("Select and delete tabs"), function()
        if self.library then self.library.showSelect() end
    end))
    table.insert(buttons, button(_("Refresh list"), function()
        if self.library then self.library.refresh() end
    end))
    dialog = ButtonDialog:new{ buttons = buttons }
    UIManager:show(dialog)
end

--- Long press on a tab in the library.
function GuitarTabReader:showTabActions(file, title)
    local dialog
    local function button(text, fn)
        return {{ text = text, callback = function()
            UIManager:close(dialog)
            fn()
        end }}
    end
    dialog = ButtonDialog:new{
        title = title,
        title_align = "center",
        buttons = {
            button(_("Add to setlist"), function() Setlists.addDialog(self, file.rel, title) end),
            button(_("Delete"), function() if self.library then self.library.confirmDelete({ file }) end end),
            button(_("Select several…"), function() if self.library then self.library.showSelect(file.rel) end end),
        },
    }
    UIManager:show(dialog)
end

function GuitarTabReader:onSuspend()
    -- Wi-Fi goes away during sleep; the receiver restarts on wake-up.
    self.receiver_was_running = self.receiver ~= nil
    self:stopReceiver()
end

function GuitarTabReader:onResume()
    if self.receiver_was_running and self.library then
        self.receiver_was_running = false
        UIManager:scheduleIn(3, function()
            if self.library then self:startReceiver() end
        end)
    end
end

function GuitarTabReader:onNetworkConnected()
    if self.library and not self.receiver then self:startReceiver() end
end

function GuitarTabReader:onCloseWidget()
    self:stopReceiver()
end

--- How tabs are sized (older versions had an on/off switch "shrink_tabs").
function GuitarTabReader:getTabFit()
    local fit = self:getSetting("tab_fit")
    if fit then return fit end
    return self:getSetting("shrink_tabs") == false and "off" or "shrink"
end

function GuitarTabReader:openTab(model, entry, on_close, extra)
    extra = extra or {}
    local viewer = Viewer:new{
        model = model,
        font_size = entry.font_size or self:getSetting("font_size") or DEFAULT_FONT_SIZE,
        own_size = entry.font_size ~= nil,
        default_size = self:getSetting("font_size") or DEFAULT_FONT_SIZE,
        tab_fit = self:getTabFit(),
        transpose = entry.transpose or 0,
        show_diagrams = self:getSetting("show_diagrams") ~= false,
        page = extra.setlist and 1 or entry.last_page or 1,
        next_title = extra.next_title,
        on_next = extra.on_next,
        on_close = on_close,
        on_set_default = function(size) self:setSetting("font_size", size) end,
        on_tab_fit_changed = function(mode) self:setSetting("tab_fit", mode) end,
        on_diagrams_changed = function(on) self:setSetting("show_diagrams", on) end,
    }
    UIManager:show(viewer)
    return viewer
end

function GuitarTabReader:addToMainMenu(menu_items)
    menu_items.guitar_tab_reader = {
        text = "Guitar Tab Reader",
        sub_item_table = {
            {
                text = _("Open library"),
                callback = function() self:openLibrary() end,
            },
            {
                text = _("Add tab (phone)"),
                callback = function()
                    self:openLibrary()
                    self:showAddDialog()
                end,
            },
            {
                text = _("Ultimate Guitar (experimental)"),
                sub_item_table = {
                    {
                        text = _("Module switched on"),
                        checked_func = function() return self:ugEnabled() end,
                        callback = function(touchmenu_instance)
                            if self:ugEnabled() then
                                self:setSetting("ug_enabled", false)
                                touchmenu_instance:updateItems()
                            else
                                UGMenu.confirmEnable(self, function() touchmenu_instance:updateItems() end)
                            end
                        end,
                        keep_menu_open = true,
                    },
                    {
                        text = _("Search Ultimate Guitar"),
                        enabled_func = function() return self:ugEnabled() end,
                        callback = function() self:showSearch() end,
                    },
                    {
                        text_func = function()
                            return T(_("Load remembered links (%1)"), #UGMenu.pendingLinks(self:getFolder()))
                        end,
                        enabled_func = function() return self:ugEnabled() end,
                        callback = function()
                            self:openLibrary()
                            self:loadLinks()
                        end,
                    },
                },
            },
            {
                text_func = function() return T(_("Tab folder: %1"), self:getFolder()) end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local PathChooser = require("ui/widget/pathchooser")
                    local start = self:getFolder()
                    if not util.pathExists(start) then start = Device.home_dir or "/" end
                    UIManager:show(PathChooser:new{
                        select_directory = true,
                        select_file = false,
                        path = start,
                        onConfirm = function(path)
                            self:setSetting("folder", path)
                            touchmenu_instance:updateItems()
                        end,
                    })
                end,
                hold_callback = function(touchmenu_instance)
                    self:setSetting("folder", nil)
                    touchmenu_instance:updateItems()
                    UIManager:show(InfoMessage:new{ text = T(_("Tab folder reset to:\n%1"), self:getFolder()), timeout = 3 })
                end,
            },
            {
                text_func = function()
                    return T(_("Default font size: %1"), self:getSetting("font_size") or DEFAULT_FONT_SIZE)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    UIManager:show(SpinWidget:new{
                        title_text = _("Default font size"),
                        info_text = _("For tabs you have not opened yet. Each tab remembers its own size."),
                        value = self:getSetting("font_size") or DEFAULT_FONT_SIZE,
                        value_min = 8, value_max = 40, default_value = DEFAULT_FONT_SIZE,
                        callback = function(spin)
                            self:setSetting("font_size", spin.value)
                            touchmenu_instance:updateItems()
                        end,
                    })
                end,
                separator = true,
            },
            {
                text = _("How does it work?"),
                callback = function() UIManager:show(InfoMessage:new{ text = _(HELP_TEXT) }) end,
            },
        },
    }
end

return GuitarTabReader
