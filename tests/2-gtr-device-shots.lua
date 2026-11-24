-- Screenshots at the real device size (run with EMULATE_READER_W/H/DPI):
-- the Hallelujah PDF at font size 16 and 14, to compare with photos from the device.
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local OUT = os.getenv("GTR_TEST_OUT") or "."
local f = io.open(OUT .. "/shots.txt", "w")
local function top() return UIManager:getTopmostVisibleWidget() end
local function shot(name) UIManager:forceRePaint(); Screen:shot(OUT .. "/" .. name .. ".png") end
UIManager:scheduleIn(4, function()
  local ok, e = pcall(function()
    f:write("screen ", Screen:getWidth(), "x", Screen:getHeight(), " dpi ", Screen:getDPI(), "\n")
    local p = require("apps/filemanager/filemanager").instance.guitartabreader
    -- tab folder of this test run (run-tests.sh)
    if p and os.getenv("GTR_TABS") then p:setSetting("folder", os.getenv("GTR_TABS")) end
    local lib = p:openLibrary()
    for _, it in ipairs(lib.item_table) do
      if it.file and it.file.ext == "pdf" then
        lib:onMenuChoice(it)
        local v = top()
        for _, size in ipairs({ 16, 14 }) do
          v:setFontSize(size)
          v:goTo(1)
          f:write("size ", size, ": ", #v.pages, " pages, tab size ", v.tab_size, "\n")
          shot("pdf-" .. size .. "-p1")
          v:goTo(2)
          shot("pdf-" .. size .. "-p2")
        end
        v:onClose()
      end
    end
  end)
  if not ok then f:write("ERROR ", tostring(e), "\n") end
  f:close(); UIManager:quit()
end)
