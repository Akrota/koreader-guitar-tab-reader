local UIManager = require("ui/uimanager")
local OUT = os.getenv("GTR_TEST_OUT") or "."
local f = io.open(OUT .. "/gtr-menu.txt", "w")
local function check(n, ok) f:write((ok and "PASS " or "FAIL ") .. n .. "\n"); f:flush() end
local function top() return UIManager:getTopmostVisibleWidget() end
UIManager:scheduleIn(4, function()
  local ok, e = pcall(function()
    local p = require("apps/filemanager/filemanager").instance.guitartabreader
    -- tab folder of this test run (run-tests.sh)
    if p and os.getenv("GTR_TABS") then p:setSetting("folder", os.getenv("GTR_TABS")) end
    local lib = p:openLibrary()
    local pdf
    for _, it in ipairs(lib.item_table) do if it.file and it.file.ext == "pdf" then pdf = it end end
    lib:onMenuChoice(pdf)
    local v = top()
    check("default font 14 for a new tab", v.font_size == 14)
    local full = 0
    local orig = UIManager.setDirty
    UIManager.setDirty = function(self, w, mode, ...) if w == v and mode == "full" then full = full + 1 end return orig(self, w, mode, ...) end
    v:showMenu()
    local d = top()
    -- find the "Schließen"/"Close" button
    local found
    for _, row in ipairs(d.buttons) do for _, b in ipairs(row) do if b.text == "Schließen" or b.text == "Close" then found = b end end end
    check("close button present", found ~= nil)
    found.callback()
    check("close button closes the menu", top() == v)
    check("close button triggers full refresh", full == 1)
    v:showMenu()
    d = top()
    d:onTapClose(nil, { pos = require("ui/geometry"):new{ x = 2, y = 2, w = 0, h = 0 } })
    check("tap outside closes the menu", top() == v)
    check("tap outside triggers full refresh", full == 2)
    UIManager.setDirty = orig
    -- size 18 -> own size; "Set as default" makes it the default, the tab follows it again
    v:setFontSize(18)
    check("changed size is the tab's own", v.own_size == true)
    v:showMenu()
    d = top()
    local set_default, shrink
    for _, row in ipairs(d.buttons) do for _, b in ipairs(row) do
      if b.text == "Als Standard setzen" or b.text == "Set as default" then set_default = b end
      if b.text:find("verkleinern") or b.text:find("Shrink") then shrink = b end
    end end
    set_default.callback()
    check("set as default saves the plugin setting", p:getSetting("font_size") == 18 and v.own_size == false)
    UIManager:close(top())
    -- tab size button cycles: shrink -> fit -> off
    v:setFontSize(14); v.own_size = false
    local function tabButton()
      v:showMenu()
      local dd = top()
      for _, row in ipairs(dd.buttons) do for _, b in ipairs(row) do
        if b.text:find("Tab%-Größe") or b.text:find("Tab size") then return b end end end
    end
    check("tab size starts at 'smaller if needed'", v.tab_fit == "shrink")
    tabButton().callback()
    check("then 'fit to width', saved", v.tab_fit == "fit" and p:getSetting("tab_fit") == "fit")
    UIManager:close(top())
    tabButton().callback()
    check("then 'same as text': tabs at font size", v.tab_fit == "off" and v.tab_size == 14)
    UIManager:close(top())
    local result
    v.on_close = function(r) result = r end
    v:onClose()
    check("a tab following the default stores no own size", result and result.font_size == nil)
    p:setSetting("font_size", nil); p:setSetting("tab_fit", nil)
  end)
  if not ok then check("ERROR " .. tostring(e), false) end
  f:close()
  UIManager:quit()
end)
