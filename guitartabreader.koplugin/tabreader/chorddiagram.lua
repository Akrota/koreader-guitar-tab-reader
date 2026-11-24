--[[--
A chord diagram in the style of the UG PDFs: the name on top, x and o above
the strings, a grid of 4 frets (thick nut in the first position, else the
first fret number on the left), dots for the fingers, a bar for a barre.
Strings run from the low E (left) to the high e (right).
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local RenderText = require("ui/rendertext")
local Widget = require("ui/widget/widget")

local ChordDiagram = Widget:extend{
    name = nil,    -- chord name shown on top
    shape = nil,   -- { frets = {6}, base = first fret shown, barres = {…} } or nil (name only)
    width = 100,   -- pixels
}

local FRETS = 4

function ChordDiagram:init()
    self.pad = math.floor(self.width * 0.16)        -- room left for the fret number
    self.sx = (self.width - 2 * self.pad) / 5       -- string spacing
    self.fy = math.floor(self.sx * 1.25)            -- fret spacing
    self.face = Font:getFace("infofont", math.max(10, math.floor(self.width / 5.5)))
    self.small = Font:getFace("infofont", math.max(8, math.floor(self.width / 9)))
    self.name_h = math.floor(self.face.size * 1.5)
    self.mark_h = math.floor(self.sx * 1.2)
    self.dimen = Geom:new{ w = self.width, h = self.name_h + self.mark_h + FRETS * self.fy + math.floor(self.sx * 0.5) }
end

function ChordDiagram:getSize()
    return self.dimen
end

local function textWidth(face, text)
    return RenderText:sizeUtf8Text(0, 2000, face, text).x
end

function ChordDiagram:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local black = Blitbuffer.COLOR_BLACK
    local name = self.name or ""
    local nw = textWidth(self.face, name)
    RenderText:renderUtf8Text(bb, x + math.floor((self.width - nw) / 2), y + math.floor(self.face.size * 1.1), self.face, name, true, true)
    local shape = self.shape
    if not shape then return end
    local gx = x + self.pad
    local gy = y + self.name_h + self.mark_h
    local line = math.max(1, math.floor(self.width / 60))
    -- x and o sit above the nut (which is drawn upwards from the first fret line)
    local mark_cy = gy - line * 4 - math.floor(self.mark_h * 0.4)
    local mark_r = math.max(3, math.floor(self.sx * 0.28))
    local grid_w = math.floor(self.sx * 5)
    -- strings
    for s = 0, 5 do
        bb:paintRect(math.floor(gx + s * self.sx), gy, line, FRETS * self.fy, black)
    end
    -- frets; a thick nut in the first position
    for fr = 0, FRETS do
        local h = (fr == 0 and shape.base <= 1) and line * 4 or line
        bb:paintRect(gx, gy + fr * self.fy - (fr == 0 and h - line or 0), grid_w + line, h, black)
    end
    if shape.base > 1 then
        local label = tostring(shape.base)
        RenderText:renderUtf8Text(bb, x + math.max(0, self.pad - textWidth(self.small, label) - line * 3),
            gy + math.floor(self.fy * 0.6), self.small, label, true, false)
    end
    local r = math.max(3, math.floor(self.sx * 0.36))
    -- barres
    for _, b in ipairs(shape.barres or {}) do
        local row = b.fret - shape.base + 1
        if row >= 1 and row <= FRETS and b.from and b.to then
            local x1 = math.floor(gx + (b.from - 1) * self.sx)
            local x2 = math.floor(gx + (b.to - 1) * self.sx)
            local cy = math.floor(gy + (row - 0.5) * self.fy)
            bb:paintRoundedRect(x1 - r, cy - r, x2 - x1 + 2 * r, 2 * r, black, r)
        end
    end
    -- open / muted strings and finger dots
    for s, f in ipairs(shape.frets) do
        local cx = math.floor(gx + (s - 1) * self.sx + line / 2)
        if f < 0 then
            local m = mark_r
            local cy = mark_cy
            for d = -m, m do
                bb:paintRect(cx + d, cy + d, line + 1, line + 1, black)
                bb:paintRect(cx + d, cy - d, line + 1, line + 1, black)
            end
        elseif f == 0 then
            bb:paintCircle(cx, mark_cy, mark_r, black, line + 1)
        else
            local row = f - shape.base + 1
            if row >= 1 and row <= FRETS then
                bb:paintCircle(cx, math.floor(gy + (row - 0.5) * self.fy), r, black)
            end
        end
    end
end

return ChordDiagram
