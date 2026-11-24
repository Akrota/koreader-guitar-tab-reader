-- Screenshots of the new screens (run at device size): library menu with the UG
-- entries, search results, viewer menu. UG.get answers from the sample pages.
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local OUT = os.getenv("GTR_TEST_OUT") or "."
local SAMPLES = os.getenv("GTR_SAMPLES")
local f = io.open(OUT .. "/ui-shots.txt", "w")
local function top() return UIManager:getTopmostVisibleWidget() end
local function shot(name) UIManager:forceRePaint(); Screen:shot(OUT .. "/" .. name .. ".png"); f:write("shot ", name, "\n") end
local function read(name) local h = io.open(SAMPLES .. "/" .. name, "rb"); local s = h:read("*a"); h:close(); return s end
UIManager:scheduleIn(4, function()
  local ok, e = pcall(function()
    local p = require("apps/filemanager/filemanager").instance.guitartabreader
    -- tab folder of this test run (run-tests.sh)
    if p and os.getenv("GTR_TABS") then p:setSetting("folder", os.getenv("GTR_TABS")) end
    local UG = require("tabreader/ug")
    UG.get = function(url) return read(url:find("search.php", 1, true) and "search.html" or "tab.html") end
    p:setSetting("ug_enabled", false)
    local lib = p:openLibrary()
    require("tabreader/ugmenu").confirmEnable(p)
    shot("20-confirm-enable")
    UIManager:close(top())
    p:setSetting("ug_enabled", true)
    p:showLibraryMenu()
    shot("21-library-menu")
    UIManager:close(top())
    require("tabreader/ugmenu").runSearch(p, "testlied", 1, function(rel) lib.refresh(); lib.openRel(rel) end)
    shot("22-search-results")
    local results = top()
    results:onMenuChoice(results.item_table[1])
    local v = top()
    f:write("opened: ", tostring(v and v.model and v.model.meta.title), "\n")
    shot("23-ug-tab")
    v:showMenu()
    shot("24-viewer-menu")
    UIManager:close(top())
    v:onClose()
    p:setSetting("ug_enabled", nil)
  end)
  if not ok then f:write("ERROR ", tostring(e), "\n") end
  f:close(); UIManager:quit()
end)
