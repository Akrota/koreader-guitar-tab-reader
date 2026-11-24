--[[--
Minimal translation helper (KOReader's gettext only knows its own strings).
English is the source language; tables map English strings to translations.
--]]

local translations = {
    de = require("tabreader/l10n/de"),
}

local function currentLanguage()
    local lang = G_reader_settings and G_reader_settings:readSetting("language") or "en"
    return lang:match("^(%a%a)") or "en"
end

local function translate(msg)
    local tbl = translations[currentLanguage()]
    return tbl and tbl[msg] or msg
end

return translate
