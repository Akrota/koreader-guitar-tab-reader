-- Loaded before the plugin's own modules are on the package path,
-- so the description is translated inline.
local lang = G_reader_settings and G_reader_settings:readSetting("language") or "en"

local description = "Guitar tabs and chord sheets on your e-reader, laid out for e-ink."
if lang:match("^de") then
    description = "Gitarren-Tabs und Chords auf dem E-Reader, aufbereitet für E-Ink."
end

return {
    fullname = "Guitar Tab Reader",
    description = description,
    version = "0.7.0",
}
