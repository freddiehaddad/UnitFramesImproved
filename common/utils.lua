--[[
	UnitFramesImproved - Common Utilities
	Provides: Frame scaling, textures, auras, colors, status bars, fonts, portraits
]]

---@diagnostic disable: undefined-global

local UFI = UnitFramesImproved

-- Import dependencies from other modules
local Layout = UFI.Layout
local UFI_LAYOUT = Layout.DATA
local LayoutResolveX = Layout.ResolveX
local LayoutResolveY = Layout.ResolveY
local LayoutResolveRect = Layout.ResolveRect
local LayoutToTexCoord = Layout.ToTexCoord

local AURA_ICON_SPACING = Layout.AURA_ICON_SPACING
local AURA_ROW_VERTICAL_SPACING = Layout.AURA_ROW_VERTICAL_SPACING
local AURA_HITRECT_PADDING = Layout.AURA_HITRECT_PADDING

local STATUSBAR_TEXTURE = Layout.STATUSBAR_TEXTURE
local FONT_DEFAULT = Layout.FONT_DEFAULT

local DEFAULT_FRAME_SCALES = Layout.DEFAULT_FRAME_SCALES

-------------------------------------------------------------------------------
-- FRAME SCALE FUNCTIONS
-------------------------------------------------------------------------------

-- Fetch the persisted scale for a frame, falling back to defaults.
local function GetFrameScale(frameName)
	if not frameName then
		return 1
	end

	local db = UnitFramesImprovedDB or {}
	local scales = db.scales or {}
	local scale = scales[frameName]
	if type(scale) == "number" and scale > 0 then
		return scale
	end

	return DEFAULT_FRAME_SCALES[frameName] or 1
end

-- Persist and apply a frame's scale, updating its overlay to match.
local function SetFrameScale(frameName, scale)
	if not frameName or type(scale) ~= "number" or scale <= 0 then
		return
	end

	UnitFramesImprovedDB = UnitFramesImprovedDB or {}
	UnitFramesImprovedDB.scales = UnitFramesImprovedDB.scales or {}
	UnitFramesImprovedDB.scales[frameName] = scale

	local frame = _G[frameName]
	if frame then
		frame:SetScale(scale)
		if type(UpdateOverlayForFrame) == "function" then
			UpdateOverlayForFrame(frameName)
		end
	end
end

-- Apply the stored scale to a freshly created frame.
local function ApplySavedScaleToFrame(frame)
	if not frame then
		return
	end

	local name = frame:GetName()
	if not name then
		return
	end

	frame:SetScale(GetFrameScale(name))
end

-------------------------------------------------------------------------------
-- FRAME SETUP FUNCTIONS
-------------------------------------------------------------------------------

-- Compute a tight clickable region aligned with the visible art cutout.
local function ApplyFrameHitRect(frame, isMirrored)
	if not frame then
		return
	end

	local art = UFI_LAYOUT.Art
	local click = UFI_LAYOUT.Click

	local clickLeft = LayoutResolveX(click, isMirrored)
	local clickTop = LayoutResolveY(click)
	local leftInset = clickLeft
	local rightInset = art.width - (clickLeft + click.width)
	local topInset = clickTop
	local bottomInset = art.height - (clickTop + click.height)

	local left = math.floor(leftInset + 0.5)
	local right = math.floor(rightInset + 0.5)
	local top = math.floor(topInset + 0.5)
	local bottom = math.floor(bottomInset + 0.5)

	frame:SetHitRectInsets(left, right, top, bottom)
	frame.ufHitRect = {
		left = left,
		right = right,
		top = top,
		bottom = bottom,
	}
end

-- Build the base art texture (or portrait mask) with proper flipping.
local function CreateUnitArtTexture(parent, texturePath, mirrored, layer, subLevel)
	local texture = parent:CreateTexture(nil, layer or "ARTWORK", nil, subLevel or 0)
	texture:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
	texture:SetSize(UFI_LAYOUT.Art.width, UFI_LAYOUT.Art.height)
	texture:SetTexture(texturePath)
	local left, right, top, bottom = LayoutToTexCoord(UFI_LAYOUT.Art)
	if mirrored then
		texture:SetTexCoord(right, left, top, bottom)
	else
		texture:SetTexCoord(left, right, top, bottom)
	end
	return texture
end

-- Shared scaffolding used by every unit frame before specialization.
local function SetupUnitFrameBase(frame, texturePath, mirrored)
	frame:SetSize(UFI_LAYOUT.Art.width, UFI_LAYOUT.Art.height)
	frame:SetFrameStrata("LOW")
	ApplySavedScaleToFrame(frame)
	frame.mirrored = mirrored

	ApplyFrameHitRect(frame, mirrored)

	local visual = CreateFrame("Frame", nil, frame)
	visual:SetAllPoints(frame)
	visual:SetFrameStrata("LOW")
	visual:SetFrameLevel(frame:GetFrameLevel())
	frame.visualLayer = visual

	frame.texture = CreateUnitArtTexture(visual, texturePath, mirrored, "ARTWORK", 0)
	frame.portraitMask = CreateUnitArtTexture(visual, texturePath, mirrored, "ARTWORK", 5)
	frame.portraitMask:SetBlendMode("BLEND")
	frame.texture:SetVertexColor(1, 1, 1)
	frame.portraitMask:SetVertexColor(1, 1, 1)

	return visual
end

-------------------------------------------------------------------------------
-- AURA FUNCTIONS
-------------------------------------------------------------------------------

-- Create a single aura slot with matching icon, count, and cooldown widgets.
local function CreateAuraIcon(parent, size)
	local iconFrame = CreateFrame("Frame", nil, parent)
	iconFrame:SetSize(size, size)
	iconFrame:SetFrameLevel(parent:GetFrameLevel())

	iconFrame.icon = iconFrame:CreateTexture(nil, "ARTWORK")
	local iconSize = math.max(size - 4, 0)
	iconFrame.icon:SetSize(iconSize, iconSize)
	iconFrame.icon:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
	iconFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	iconFrame.border = iconFrame:CreateTexture(nil, "OVERLAY")
	iconFrame.border:SetSize(size, size)
	iconFrame.border:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
	iconFrame.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
	iconFrame.border:SetTexCoord(39 / 128, (39 + 34) / 128, 0 / 64, 34 / 64)

	iconFrame.cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
	iconFrame.cooldown:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
	iconFrame.cooldown:SetSize(iconSize, iconSize)

	local countFontSize = math.max(10, math.floor(size * 0.36))
	iconFrame.count = iconFrame:CreateFontString(nil, "OVERLAY")
	iconFrame.count:SetFont(FONT_DEFAULT, countFontSize, "OUTLINE")
	iconFrame.count:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)

	iconFrame:Hide()
	return iconFrame
end

-- Anchor an aura row either above or below the health bar region.
local function PositionAuraRow(row, frame, mirrored, position, order)
	if not row or not row.container then
		return
	end

	local container = row.container
	local healthX, _, healthWidth = LayoutResolveRect(UFI_LAYOUT.Health, mirrored)
	local rowHeight = row.iconSize
	local clickTop = LayoutResolveY(UFI_LAYOUT.Click)
	local clickBottom = clickTop + UFI_LAYOUT.Click.height
	local topOffset

	order = order or 1
	position = position or row.position or "below"

	if position == "above" then
		topOffset = clickTop - AURA_HITRECT_PADDING - rowHeight - (order - 1) * (rowHeight + AURA_ROW_VERTICAL_SPACING)
	else
		topOffset = clickBottom + AURA_HITRECT_PADDING + (order - 1) * (rowHeight + AURA_ROW_VERTICAL_SPACING)
	end

	container:ClearAllPoints()
	container:SetPoint("TOPLEFT", frame, "TOPLEFT", healthX, -topOffset)
	container:SetWidth(healthWidth)
	row.position = position
	row.currentOrder = order
end

-- Build an aura row definition and populate it with a fixed number of icons.
local function CreateAuraRow(frame, options)
	local count = options.count or 5
	local mirrored = not not options.mirrored
	local parent = options.parent or frame
	local position = options.position or "below"
	local order = options.order or 1
	local spacing = options.spacing or AURA_ICON_SPACING
	local desiredStrata = options.frameStrata or parent:GetFrameStrata()
	local desiredLevel = options.frameLevel or ((parent:GetFrameLevel() or 0) + 15)

	local _, _, healthWidth = LayoutResolveRect(UFI_LAYOUT.Health, mirrored)
	local iconSize = (healthWidth - (count - 1) * spacing) / count

	local container = CreateFrame("Frame", nil, parent)
	container:SetSize(healthWidth, iconSize)
	container:SetFrameStrata(desiredStrata)
	container:SetFrameLevel(desiredLevel)

	local icons = {}
	for i = 1, count do
		local icon = CreateAuraIcon(container, iconSize)
		icon:SetPoint("TOPLEFT", container, "TOPLEFT", (i - 1) * (iconSize + spacing), 0)
		icons[i] = icon
	end

	icons.container = container
	icons.iconSize = iconSize
	icons.position = position

	PositionAuraRow(icons, frame, mirrored, position, order)

	return icons
end

-------------------------------------------------------------------------------
-- COLOR & FORMATTING FUNCTIONS
-------------------------------------------------------------------------------

-- Get unit color (class color for players, reaction color for NPCs)
-- Consolidate color lookups so unit name text stays consistent across frames.
local function GetUnitColor(unit)
	local r, g, b

	if not UnitIsConnected(unit) or UnitIsDeadOrGhost(unit) then
		-- Gray for disconnected or dead
		r, g, b = 0.5, 0.5, 0.5
	elseif UnitIsPlayer(unit) then
		-- Class color for players
		local _, class = UnitClass(unit)
		local classColor = RAID_CLASS_COLORS[class]
		if classColor then
			r, g, b = classColor.r, classColor.g, classColor.b
		else
			r, g, b = 1.0, 1.0, 1.0
		end
	else
		-- Reaction color for NPCs
		r, g, b = UnitSelectionColor(unit)
	end

	return r, g, b
end

--[[------------------------------------------------------------------
	TruncateNameToFit: Truncates text with "..." to fit within maxWidth.
	Uses GetStringWidth() to measure actual rendered pixel width.
--]]
------------------------------------------------------------------
local function TruncateNameToFit(fontString, text, maxWidth)
	if not text or text == "" then
		return ""
	end

	fontString:SetText(text)
	if fontString:GetStringWidth() <= maxWidth then
		return text
	end

	-- Progressively shorten until it fits
	for i = #text - 1, 1, -1 do
		local truncated = string.sub(text, 1, i) .. "..."
		fontString:SetText(truncated)
		if fontString:GetStringWidth() <= maxWidth then
			return truncated
		end
	end

	return "..."
end

-- Format health/power text based on interface options for consistency.
local function FormatStatusText(current, max)
	local statusTextPercentage = GetCVar("statusTextPercentage")

	if statusTextPercentage == "1" then
		local percent = 0
		if max > 0 then
			percent = math.floor((current / max) * 100)
		end
		return percent .. "%"
	end

	return UFI.AbbreviateNumber(current) .. " / " .. UFI.AbbreviateNumber(max)
end

-------------------------------------------------------------------------------
-- WIDGET CREATION FUNCTIONS
-------------------------------------------------------------------------------

-- Construct a themed StatusBar aligned with the art layout coordinates.
local function CreateStatusBar(parent, rect, mirrored)
	local x, y, width, height = LayoutResolveRect(rect, mirrored)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetSize(width, height)
	bar:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	bar:SetStatusBarTexture(STATUSBAR_TEXTURE)
	local texture = bar:GetStatusBarTexture()
	texture:SetHorizTile(false)
	texture:SetVertTile(false)
	texture:SetDrawLayer("ARTWORK", 0)
	texture:SetVertexColor(1, 1, 1, 1)
	bar:SetMinMaxValues(0, 100)
	bar:SetValue(100)
	bar:SetFrameLevel(math.max((parent:GetFrameLevel() or 1) - 1, 0))

	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetColorTexture(0, 0, 0, 0.75)
	bg:SetAllPoints(bar)
	bar.bg = bg

	return bar
end

-- Helper for creating font strings with consistent defaults.
local function CreateFontString(parent, fontOptions)
	local fontString = parent:CreateFontString(nil, "OVERLAY")
	local fontFlags = fontOptions.flags
	fontString:SetFont(fontOptions.path or FONT_DEFAULT, fontOptions.size, fontFlags)
	local relativeTo = fontOptions.relativeTo or parent
	local relativePoint = fontOptions.relativePoint or fontOptions.point
	fontString:SetPoint(fontOptions.point, relativeTo, relativePoint, fontOptions.x or 0, fontOptions.y or 0)
	if fontOptions.color then
		fontString:SetTextColor(fontOptions.color.r, fontOptions.color.g, fontOptions.color.b)
	end
	fontString:SetDrawLayer("OVERLAY", fontOptions.drawLayer or 7)
	return fontString
end

-- Create the circular portrait texture that sits inside the art ring.
local function CreatePortrait(parent, mirrored)
	local rect = UFI_LAYOUT.Portrait
	local x, y, width, height = LayoutResolveRect(rect, mirrored)
	local portrait = parent:CreateTexture(nil, "BACKGROUND", nil, 0)
	portrait:SetSize(width, height)
	portrait:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	return portrait
end

-------------------------------------------------------------------------------
-- EXPORT TO NAMESPACE
-------------------------------------------------------------------------------

UFI.Utils = {
	-- Frame scale
	GetFrameScale = GetFrameScale,
	SetFrameScale = SetFrameScale,
	ApplySavedScaleToFrame = ApplySavedScaleToFrame,
	
	-- Frame setup
	ApplyFrameHitRect = ApplyFrameHitRect,
	CreateUnitArtTexture = CreateUnitArtTexture,
	SetupUnitFrameBase = SetupUnitFrameBase,
	
	-- Auras
	CreateAuraIcon = CreateAuraIcon,
	PositionAuraRow = PositionAuraRow,
	CreateAuraRow = CreateAuraRow,
	
	-- Colors & formatting
	GetUnitColor = GetUnitColor,
	TruncateNameToFit = TruncateNameToFit,
	FormatStatusText = FormatStatusText,
	
	-- Widgets
	CreateStatusBar = CreateStatusBar,
	CreateFontString = CreateFontString,
	CreatePortrait = CreatePortrait,
}
