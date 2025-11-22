--[[
	UnitFramesImproved - Layout System
	Provides: Frame coordinates, sizing data, layout utilities
]]

---@diagnostic disable-next-line: undefined-global
local UFI = UnitFramesImproved

local layout = {}

-------------------------------------------------------------------------------
-- LAYOUT DATA - Coordinates and sizing for frame elements
-------------------------------------------------------------------------------

layout.DATA = {
	TextureSize = { width = 512, height = 256 },
	Art = { x = 52, y = 0, width = 460, height = 200 },
	Click = { x = 56, y = 42, width = 372, height = 87 },
	Health = { x = 60, y = 46, width = 238, height = 58 },
	Power = { x = 60, y = 106, width = 236, height = 20 },
	Portrait = { x = 305, y = 31, width = 116, height = 116 },
	LevelRest = { x = 386, y = 112, width = 39, height = 39 },
	ComboPointsText = { x = 388, y = 38, width = 38, height = 38 },
	CastBar = {
		TextureSize = { width = 128, height = 16 },
		Fill = { x = 3, y = 3, width = 122, height = 10 },
		OffsetY = 50,
		DefaultWidth = 122,
		DefaultHeight = 10,
	},
}

-------------------------------------------------------------------------------
-- AURA CONFIGURATION
-------------------------------------------------------------------------------

layout.AURA_ICON_SPACING = 4
layout.AURA_ROW_VERTICAL_SPACING = 6
layout.AURA_HITRECT_PADDING = 5

-------------------------------------------------------------------------------
-- ASSETS
-------------------------------------------------------------------------------

layout.STATUSBAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
layout.FONT_DEFAULT = "Fonts\\FRIZQT__.TTF"

-------------------------------------------------------------------------------
-- FRAME SCALES
-------------------------------------------------------------------------------

---@diagnostic disable-next-line: undefined-global
local MAX_BOSS_FRAMES = MAX_BOSS_FRAMES or 4

layout.DEFAULT_BOSS_FRAME_SCALE = 0.45
layout.DEFAULT_FRAME_SCALES = {
	UFI_PlayerFrame = 0.55,
	UFI_TargetFrame = 0.55,
	UFI_TargetOfTargetFrame = 0.25,
	UFI_FocusFrame = 0.55,
	UFI_BossFrameAnchor = 1,
}

-- Populate boss frame scales
for index = 1, MAX_BOSS_FRAMES do
	local name = "UFI_BossFrame" .. index
	layout.DEFAULT_FRAME_SCALES[name] = layout.DEFAULT_FRAME_SCALES[name] or layout.DEFAULT_BOSS_FRAME_SCALE
end

-------------------------------------------------------------------------------
-- LAYOUT UTILITY FUNCTIONS
-------------------------------------------------------------------------------

-- Resolve X coordinate relative to art frame, handling mirroring
function layout.ResolveX(rect, mirrored)
	local art = layout.DATA.Art
	local width = rect.width or rect.size
	if not mirrored then
		return rect.x - art.x
	end
	local localX = rect.x - art.x
	return art.width - (localX + width)
end

-- Resolve Y coordinate relative to art frame
function layout.ResolveY(rect)
	return rect.y - layout.DATA.Art.y
end

-- Resolve full rect (x, y, width, height) relative to art frame
function layout.ResolveRect(rect, mirrored)
	local x = layout.ResolveX(rect, mirrored)
	local y = layout.ResolveY(rect)
	local width = rect.width or rect.size
	local height = rect.height or rect.size
	return x, y, width, height
end

-- Convert layout coordinates to texture coordinates (0-1 range)
function layout.ToTexCoord(rect)
	local tex = layout.DATA.TextureSize
	local left = rect.x / tex.width
	local right = (rect.x + rect.width) / tex.width
	local top = rect.y / tex.height
	local bottom = (rect.y + rect.height) / tex.height
	return left, right, top, bottom
end

-------------------------------------------------------------------------------
-- EXPORT
-------------------------------------------------------------------------------

UFI.Layout = layout
