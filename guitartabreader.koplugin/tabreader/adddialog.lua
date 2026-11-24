--[[--
"Add tab": shows the receiver's address as a QR code and as text, so the
phone can open the page. The receiver keeps running while the library is
open; closing this dialog does not stop it.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local QRWidget = require("ui/widget/qrwidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local _ = require("tabreader/i18n")

local AddDialog = InputContainer:extend{
    url = nil,
}

function AddDialog:init()
    local width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.85)
    local inner = width - 2 * Size.padding.large
    local qr_size = math.floor(math.min(inner * 0.7, Screen:getHeight() * 0.38))
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = Size.border.window,
            radius = Size.radius.window,
            padding = Size.padding.large,
            VerticalGroup:new{
                align = "center",
                TextBoxWidget:new{
                    text = _("Add tabs from your phone"),
                    face = Font:getFace("tfont"),
                    width = inner,
                    alignment = "center",
                },
                VerticalSpan:new{ width = Size.span.vertical_large },
                QRWidget:new{ text = self.url, width = qr_size, height = qr_size },
                VerticalSpan:new{ width = Size.span.vertical_large },
                TextBoxWidget:new{
                    text = _("Scan the code with your phone (same Wi-Fi) or type the address. Send PDFs, text tabs, pasted text or links. Tip: save the page as a bookmark on your home screen.") .. "\n\n" .. self.url,
                    face = Font:getFace("cfont", 16),
                    width = inner,
                    alignment = "center",
                },
                VerticalSpan:new{ width = Size.span.vertical_large },
                Button:new{
                    text = _("Close"),
                    width = math.floor(inner / 2),
                    callback = function() self:onClose() end,
                },
            },
        },
    }
end

function AddDialog:onShow()
    UIManager:setDirty(self, "full")
end

function AddDialog:onCloseWidget()
    -- full refresh: no ghosting of the QR code on e-ink
    UIManager:setDirty(nil, "full")
end

function AddDialog:onClose()
    UIManager:close(self)
    return true
end

return AddDialog
