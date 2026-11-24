-- Test: Guitar Tab Reader stage 2 (receiver). Opens the library, writes the
-- receiver address to a file; the shell script sends tabs with curl; then
-- this patch checks what arrived.
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local OUT = os.getenv("GTR_TEST_OUT") or "."
local f = io.open(OUT .. "/gtr-receiver-results.txt", "w")
local function log(...) local p = {} for i = 1, select("#", ...) do p[#p+1] = tostring(select(i, ...)) end f:write(table.concat(p, " ") .. "\n"); f:flush() end
local function check(n, ok) log(ok and "PASS" or "FAIL", n) end
local function top() return UIManager:getTopmostVisibleWidget() end
local function shot(name) UIManager:forceRePaint(); Screen:shot(OUT .. "/" .. name .. ".png") end
UIManager:scheduleIn(4, function()
  local ok, e = pcall(function()
    local p = require("apps/filemanager/filemanager").instance.guitartabreader
    -- tab folder of this test run (run-tests.sh)
    if p and os.getenv("GTR_TABS") then p:setSetting("folder", os.getenv("GTR_TABS")) end
    local lib = p:openLibrary()
    local before = #lib.item_table
    check("receiver runs while library is open", p.receiver ~= nil)
    local r = p.receiver
    local a = io.open(OUT .. "/receiver-address.txt", "w"); a:write(r.base, "\n", r.token, "\n"); a:close()
    p:showAddDialog()
    check("add dialog shows the address", top() and top().url == r.page_url)
    shot("10-add-dialog")
    UIManager:close(top())
    -- wait for the shell to finish sending (it writes "done")
    local waited = 0
    local function waitDone()
      waited = waited + 1
      local d = io.open(OUT .. "/curl-done", "r")
      if not d and waited < 120 then return UIManager:scheduleIn(0.5, waitDone) end
      if d then d:close() end
      UIManager:scheduleIn(1, function()
        local ok2, e2 = pcall(function()
          local names = {}
          for _, it in ipairs(lib.item_table) do names[#names + 1] = it.text end
          log("library now:", table.concat(names, " | "))
          check("new tabs appear in the library (1 PDF + 1 text; links are only remembered)", #lib.item_table == before + 2)
          local lfs = require("libs/libkoreader-lfs")
          local folder = p:getFolder()
          check("PDF saved in pdf/ with its name", lfs.attributes(folder .. "/pdf/Song Upload.pdf", "mode") == "file")
          check("text tab saved as Artist - Title.txt", lfs.attributes(folder .. "/Handy Band - Gesendeter Song.txt", "mode") == "file")
          local LuaSettings = require("luasettings")
          local links = LuaSettings:open(folder .. "/.tabreader/links.lua"):readSetting("links") or {}
          check("link from the form remembered (the shortcut address is gone)", #links == 1)
          shot("11-library-after-receive")
          -- receiver stops with the library
          lib:onClose()
          check("receiver stopped after closing the library", p.receiver == nil)
        end)
        if not ok2 then log("ERROR", e2) end
        f:close(); UIManager:quit()
      end)
    end
    waitDone()
  end)
  if not ok then log("ERROR", e); f:close(); UIManager:quit() end
end)
