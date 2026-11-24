-- Test: deleting tabs in the library (one by long press, several with check marks),
-- plus the "How does it work?" entry. Runs in German (test environment).
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local lfs = require("libs/libkoreader-lfs")
local OUT = os.getenv("GTR_TEST_OUT") or "."
local f = io.open(OUT .. "/gtr-delete.txt", "w")
local function log(...) local p = {} for i = 1, select("#", ...) do p[#p+1] = tostring(select(i, ...)) end f:write(table.concat(p, " ") .. "\n"); f:flush() end
local function check(n, ok) log(ok and "PASS" or "FAIL", n) end
local function top() return UIManager:getTopmostVisibleWidget() end
local function shot(name) UIManager:forceRePaint(); Screen:shot(OUT .. "/" .. name .. ".png") end
local function find(lib, text)
  for _, it in ipairs(lib.item_table) do if it.file and it.text:find(text, 1, true) then return it end end
end
local function button(dialog, text)
  for _r, row in ipairs(dialog.buttons) do for _b, b in ipairs(row) do
    if b.text:find(text, 1, true) == 1 then return b end end end
end
UIManager:scheduleIn(4, function()
  local ok, e = pcall(function()
    local FM = require("apps/filemanager/filemanager").instance
    local p = FM and FM.guitartabreader
    local folder = os.getenv("GTR_TABS")
    p:setSetting("folder", folder)
    -- help entry is the last one in the Tools menu
    local items = {}
    p:addToMainMenu(items)
    local sub = items.guitar_tab_reader.sub_item_table
    check("help is the last menu entry", sub[#sub].text == "Wie funktioniert das?")
    sub[#sub].callback()
    check("help text opens", top() and top().text and top().text:find("Tab gedrückt halten", 1, true) ~= nil)
    UIManager:close(top())

    -- UG search: the last search stays, "Leeren" empties the field
    p:setSetting("ug_last_query", "hallelujah")
    require("tabreader/ugmenu").showSearch(p, function() end)
    local search = top()
    check("search keeps the last query", search.getInputText and search:getInputText() == "hallelujah")
    shot("del-00-search")
    local clear
    for _r, row in ipairs(search.buttons or {}) do for _b, b in ipairs(row) do if b.text == "Leeren" then clear = b end end end
    check("search has a clear button", clear ~= nil)
    if clear then clear.callback() end
    check("clear empties the field", search:getInputText() == "")
    search:onCloseKeyboard()
    UIManager:close(search)

    local lib = p:openLibrary()
    local before = #lib.item_table
    log("tabs:", before)

    -- font size: "Reset to default" next to "Set as default"
    lib.openFile(find(lib, "Amazing Grace").file)
    local v = top()
    local default = v.font_size
    v:setFontSize(default + 3)
    v:showMenu()
    local m = top()
    local reset = button(m, "Auf Standard zurücksetzen")
    check("reset button sits next to set as default", reset and button(m, "Als Standard setzen") and reset.enabled ~= false)
    shot("del-00b-font-menu")
    reset.callback()
    check("reset goes back to the default size", v.font_size == default and v.own_size == false)
    UIManager:close(top())
    v:onClose()
    -- a setlist with two songs, one of them gets deleted
    local Setlists = require("tabreader/setlists")
    local grace = find(lib, "Amazing Grace")
    local riff = find(lib, "Übungsriff")
    Setlists.save(p, { { name = "Probe", items = { grace.file.rel, riff.file.rel } } })
    -- the tab remembers something (state) before it is deleted
    local state = require("tabreader/library").openState(folder)
    local entries = state:readSetting("tabs") or {}
    entries[grace.file.rel] = { last_opened = 5, last_page = 2 }
    state:saveSetting("tabs", entries); state:flush()

    -- long press: actions dialog
    p:showTabActions(grace.file, grace.text)
    local d = top()
    check("hold shows add / delete / select", button(d, "Zu einer Setlist") and button(d, "Löschen") and button(d, "Mehrere auswählen"))
    shot("del-01-hold")
    button(d, "Löschen").callback()
    local box = top()
    check("asks before deleting one", box.text and box.text:find("Amazing Grace", 1, true) and box.text:find("löschen?", 1, true))
    shot("del-02-confirm")
    box.ok_callback(); UIManager:close(box)
    check("file is gone", lfs.attributes(grace.file.path, "mode") == nil)
    check("list has one entry less", #lib.item_table == before - 1 and find(lib, "Amazing Grace") == nil)
    entries = require("tabreader/library").openState(folder):readSetting("tabs") or {}
    check("remembered state is gone", entries[grace.file.rel] == nil)
    local lists = Setlists.load(p)
    check("deleted tab left the setlist, the other stays", #lists[1].items == 1 and lists[1].items[1] == riff.file.rel)

    -- several at once
    local sel = lib.showSelect(riff.file.rel)
    check("selection starts with the held tab checked", sel.item_table[1] and (function()
      for _i, it in ipairs(sel.item_table) do if it.text:find("☑", 1, true) then return it.text:find("Übungsriff", 1, true) ~= nil end end
    end)())
    shot("del-03-select")
    sel.onLeftButtonTap()
    d = top()
    button(d, "Alle auswählen").callback()
    local all_checked = true
    for _i, it in ipairs(sel.item_table) do if not it.text:find("☑", 1, true) then all_checked = false end end
    check("select all checks every tab", all_checked)
    -- uncheck one by tapping
    local keep = sel.item_table[1]
    sel.onMenuChoice(sel, keep)
    check("tap unchecks", sel.item_table[1].text:find("☐", 1, true) == 1)
    sel.onLeftButtonTap()
    d = top()
    local del = button(d, "Ausgewählte löschen")
    check("delete button counts the selection", del and del.text:find("(" .. (#sel.item_table - 1) .. ")", 1, true))
    del.callback()
    box = top()
    check("asks before deleting several", box.text and box.text:find("Tabs löschen?", 1, true))
    box.ok_callback(); UIManager:close(box)
    check("only the unchecked tab is left", #lib.item_table == 1 and lib.item_table[1].file.rel == keep.file.rel)
    check("selection view closed", top() == lib)
    shot("del-04-after")
  end)
  if not ok then log("ERROR", e) end
  f:close(); UIManager:quit()
end)
