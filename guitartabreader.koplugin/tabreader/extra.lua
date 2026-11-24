--[[--
Extra data for a tab that the text file cannot hold (chord shapes from UG,
the page it came from). Stored in the hidden data folder, one file per tab,
so the tab file itself stays plain text.
--]]

local LuaSettings = require("luasettings")
local util = require("util")

local Extra = {}

local function dir(folder) return folder .. "/.tabreader/extra" end

local function path(folder, rel)
    return dir(folder) .. "/" .. rel:gsub("[/\\]", "__") .. ".lua"
end

function Extra.save(folder, rel, data)
    util.makePath(dir(folder))
    local s = LuaSettings:open(path(folder, rel))
    s:saveSetting("data", data)
    s:flush()
end

--- Forget the data of a deleted tab.
function Extra.remove(folder, rel)
    os.remove(path(folder, rel))
end

--- @return data table or nil
function Extra.load(folder, rel)
    local lfs = require("libs/libkoreader-lfs")
    local p = path(folder, rel)
    if lfs.attributes(p, "mode") ~= "file" then return nil end
    return LuaSettings:open(p):readSetting("data")
end

return Extra
