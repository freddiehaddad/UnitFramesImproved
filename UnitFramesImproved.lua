--[[
	UnitFramesImproved - Custom Unit Frames for WotLK
	
	This addon creates completely custom unit frames independent of Blizzard's
	default frames to avoid taint issues while providing enhanced visuals.
]]

---@diagnostic disable: undefined-global

-- Provide a predictable table wipe helper that survives sandboxed Lua environments.
local table_wipe = rawget(table, "wipe") or function(tbl)
	for key in pairs(tbl) do
		tbl[key] = nil
	end
end

-- Enforce immutability on configuration tables so other add-ons (or saved variable reloads)
-- cannot mutate them and accidentally taint secure frames through unexpected writes.
local function FreezeTable(tbl, label, seen)
	if type(tbl) ~= "table" then
		return tbl
	end

	seen = seen or {}
	if seen[tbl] then
		return tbl
	end
	seen[tbl] = true

	for key, value in pairs(tbl) do
		if type(value) == "table" then
			local childLabel
			if type(key) == "string" then
				childLabel = label and (label .. "." .. key) or key
			else
				childLabel = label
			end
			FreezeTable(value, childLabel, seen)
		end
	end

	local message
	if label then
		message = "Attempt to modify read-only table '" .. label .. "'"
	else
		message = "Attempt to modify read-only table"
	end

	return setmetatable(tbl, {
		__metatable = false,
		__newindex = function()
			error(message, 2)
		end,
	})
end

-------------------------------------------------------------------------------
-- ADDON INITIALIZATION
-------------------------------------------------------------------------------

-- Frame references are kept global so the in-game `/dump` command can inspect them.
UFI_PlayerFrame = nil

local Layout = (function()
	local layout = {}

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

	layout.AURA_ICON_SPACING = 4
	layout.AURA_ROW_VERTICAL_SPACING = 6
	layout.AURA_HITRECT_PADDING = 5

	layout.STATUSBAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
	layout.FONT_DEFAULT = "Fonts\\FRIZQT__.TTF"

	layout.DEFAULT_BOSS_FRAME_SCALE = 0.45
	layout.MAX_BOSS_FRAMES = 4
	layout.DEFAULT_FRAME_SCALES = {
		UFI_PlayerFrame = 0.55,
		UFI_TargetFrame = 0.55,
		UFI_TargetOfTargetFrame = 0.25,
		UFI_FocusFrame = 0.55,
		UFI_BossFrameAnchor = 1,
	}

	for index = 1, layout.MAX_BOSS_FRAMES do
		local name = "UFI_BossFrame" .. index
		layout.DEFAULT_FRAME_SCALES[name] = layout.DEFAULT_FRAME_SCALES[name] or layout.DEFAULT_BOSS_FRAME_SCALE
	end

	FreezeTable(layout.DATA, "Layout.DATA")
	FreezeTable(layout.DEFAULT_FRAME_SCALES, "Layout.DEFAULT_FRAME_SCALES")

	function layout.ResolveX(rect, mirrored)
		local art = layout.DATA.Art
		local width = rect.width or rect.size
		if not mirrored then
			return rect.x - art.x
		end
		local localX = rect.x - art.x
		return art.width - (localX + width)
	end

	function layout.ResolveY(rect)
		return rect.y - layout.DATA.Art.y
	end

	function layout.ResolveRect(rect, mirrored)
		local x = layout.ResolveX(rect, mirrored)
		local y = layout.ResolveY(rect)
		local width = rect.width or rect.size
		local height = rect.height or rect.size
		return x, y, width, height
	end

	function layout.ToTexCoord(rect)
		local tex = layout.DATA.TextureSize
		local left = rect.x / tex.width
		local right = (rect.x + rect.width) / tex.width
		local top = rect.y / tex.height
		local bottom = (rect.y + rect.height) / tex.height
		return left, right, top, bottom
	end

	return layout
end)()

local UFI_LAYOUT = Layout.DATA
local LayoutResolveX = Layout.ResolveX
local LayoutResolveY = Layout.ResolveY
local LayoutResolveRect = Layout.ResolveRect
local LayoutToTexCoord = Layout.ToTexCoord

local AURA_ICON_SPACING = Layout.AURA_ICON_SPACING
local AURA_ROW_VERTICAL_SPACING = Layout.AURA_ROW_VERTICAL_SPACING
local AURA_HITRECT_PADDING = Layout.AURA_HITRECT_PADDING

---@diagnostic disable-next-line: deprecated
local unpack = unpack or table.unpack

local STATUSBAR_TEXTURE = Layout.STATUSBAR_TEXTURE
local FONT_DEFAULT = Layout.FONT_DEFAULT

local NAME_TEXT_COLOR_R, NAME_TEXT_COLOR_G, NAME_TEXT_COLOR_B = 1, 0.82, 0

local DEFAULT_BOSS_FRAME_SCALE = Layout.DEFAULT_BOSS_FRAME_SCALE
local MAX_BOSS_FRAMES = Layout.MAX_BOSS_FRAMES
local DEFAULT_FRAME_SCALES = Layout.DEFAULT_FRAME_SCALES

local UpdatePlayerLevel -- forward declaration

--[[
Pixel Alignment Validation
- Temporarily enable a 1:1 UI scale with `/console UIScale 1` and reload to avoid filtering.
- Use the `/ufi unlock` overlay to confirm bars and portraits line up against the art cutouts.
- Toggle `ProjectedTextures` and inspect the cast bars; every edge should sit on whole pixels without shimmering.
- Restore your preferred scale after verification.
]]

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

-- Emit addon-prefixed messages in the default chat frame.
local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[UFI]|r " .. tostring(msg))
end

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

-- Format large numbers with abbreviations (k/M/G).
local function AbbreviateNumber(value)
	if not value then
		return "0"
	end

	local strValue = tostring(math.floor(value))
	local len = string.len(strValue)

	if len >= 10 then
		return string.sub(strValue, 1, -10) .. "." .. string.sub(strValue, -9, -9) .. "G"
	elseif len >= 7 then
		return string.sub(strValue, 1, -7) .. "." .. string.sub(strValue, -6, -6) .. "M"
	elseif len >= 4 then
		return string.sub(strValue, 1, -4) .. "." .. string.sub(strValue, -3, -3) .. "k"
	else
		return strValue
	end
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

-- Central lookup for base frame textures keyed by classification.
local FRAME_TEXTURES = FreezeTable({
	default = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame",
	player = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare",
	elite = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Elite",
	rare = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare",
	rareElite = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare-Elite",
}, "FRAME_TEXTURES")

-- Rogue variant textures (root-level BLPs only) mapped by classification key
ROGUE_FRAME_TEXTURES = ROGUE_FRAME_TEXTURES or FreezeTable({
	default = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-RogueTargetingFrame",
	player = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-RogueTargetingFrame-Rare",
	elite = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-RogueTargetingFrame-Elite",
	rare = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-RogueTargetingFrame-Rare",
	rareElite = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-RogueTargetingFrame-Rare-Elite",
}, "ROGUE_FRAME_TEXTURES")

-- Alternate vertex colors applied to the player frame under specific states.
local PLAYER_TEXTURE_COLORS = FreezeTable({
	normal = { r = 1, g = 1, b = 1 },
	threat = { r = 1, g = 0.3, b = 0.3 },
}, "PLAYER_TEXTURE_COLORS")

local ADDON_VERSION = "1.0.0"
local DB_SCHEMA_VERSION = 1

local BOSS_FRAME_STRIDE = UFI_LAYOUT.Art.height + UFI_LAYOUT.CastBar.OffsetY + 40
local BOSS_CLASSIFICATION_TEXTURES = FreezeTable({
	worldboss = FRAME_TEXTURES.elite,
	elite = FRAME_TEXTURES.elite,
	rare = FRAME_TEXTURES.rare,
	rareelite = FRAME_TEXTURES.rareElite,
}, "BOSS_CLASSIFICATION_TEXTURES")

local ROGUE_BOSS_CLASSIFICATION_TEXTURES = FreezeTable({
	worldboss = ROGUE_FRAME_TEXTURES.elite,
	elite = ROGUE_FRAME_TEXTURES.elite,
	rare = ROGUE_FRAME_TEXTURES.rare,
	rareelite = ROGUE_FRAME_TEXTURES.rareElite,
}, "ROGUE_BOSS_CLASSIFICATION_TEXTURES")
local bossFrames = {}
local bossFramesByUnit = {}
local UpdateBossFrame
local UpdateAllBossFrames
local UpdateBossHealth
local UpdateBossPower
local UpdateBossPortrait
local UpdateBossName
local UpdateBossLevel
local UpdateBossClassification
local ClearBossUnitFrame

local function IsBossUnit(unit)
	return unit ~= nil and bossFramesByUnit[unit] ~= nil
end

local function ApplyBossTexture(frame, classification)
	if not frame or not frame.texture or not frame.portraitMask then
		return
	end

	local texturePath = BOSS_CLASSIFICATION_TEXTURES[classification] or FRAME_TEXTURES.default

	if frame.currentTexture ~= texturePath then
		frame.texture:SetTexture(texturePath)
		frame.portraitMask:SetTexture(texturePath)
		frame.currentTexture = texturePath
	end
end

-- Format health/power text based on interface options for consistency
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

	return AbbreviateNumber(current) .. " / " .. AbbreviateNumber(max)
end

local SELF_BUFF_EXCLUSIONS = FreezeTable({
	[72221] = true, -- Luck of the Draw
	[91769] = true, -- Keeper's Scroll: Steadfast
	[91794] = true,
	[91796] = true,
	[91803] = true, -- Keeper's Scroll: Ghost Runner
	[91810] = true, -- Keeper's Scroll: Gathering Speed
	[91814] = true,
	[170021] = true,
	[498752] = true,
	[993943] = true, -- Titan Scroll: Norgannon
	[993955] = true, -- Titan Scroll: Khaz'goroth
	[993957] = true, -- Titan Scroll: Eonar
	[993959] = true, -- Titan Scroll: Aggramar
	[993961] = true, -- Titan Scroll: Golganneth
	[997615] = true, -- Resting
	[997616] = true, -- Well Rested
	[9931032] = true,
}, "SELF_BUFF_EXCLUSIONS")

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

-- Precomputed raid target dropdown entries with colorized labels.
local RAID_TARGET_ICON_OPTIONS = {
	{ name = RAID_TARGET_1, index = 1, r = 1.0, g = 1.0, b = 0.0 },
	{ name = RAID_TARGET_2, index = 2, r = 1.0, g = 0.5, b = 0.0 },
	{ name = RAID_TARGET_3, index = 3, r = 0.6, g = 0.4, b = 1.0 },
	{ name = RAID_TARGET_4, index = 4, r = 0.0, g = 1.0, b = 0.0 },
	{ name = RAID_TARGET_5, index = 5, r = 0.7, g = 0.7, b = 0.7 },
	{ name = RAID_TARGET_6, index = 6, r = 0.0, g = 0.5, b = 1.0 },
	{ name = RAID_TARGET_7, index = 7, r = 1.0, g = 0.0, b = 0.0 },
	{ name = RAID_TARGET_8, index = 8, r = 1.0, g = 1.0, b = 1.0 },
}

-- Generate a secure dropdown mirroring Blizzard's unit interaction menus.
local function CreateUnitInteractionDropdown(unit, dropdownName, options)
	local fallbackTitle = (options and options.fallbackTitle) or unit
	local extraLevel1Buttons = options and options.extraLevel1Buttons
	local level1Builder = options and options.level1Builder

	local level2Handlers
	if options then
		local provided = options.level2Handlers
		local legacy = options.extraLevel2Handlers
		if provided and legacy and provided ~= legacy then
			-- Support both new and legacy menu providers without dropping entries.
			level2Handlers = {}
			for key, handler in pairs(legacy) do
				level2Handlers[key] = handler
			end
			for key, handler in pairs(provided) do
				level2Handlers[key] = handler
			end
		else
			level2Handlers = provided or legacy
		end
	end

	local dropdown = CreateFrame("Frame", dropdownName, UIParent, "UIDropDownMenuTemplate")
	dropdown.displayMode = "MENU"

	local function AddButton(level, builder)
		local info = UIDropDownMenu_CreateInfo()
		builder(info)
		UIDropDownMenu_AddButton(info, level)
	end

	local function AddRaidTargetMenu(level)
		local currentTarget = GetRaidTargetIndex(unit)

		for _, icon in ipairs(RAID_TARGET_ICON_OPTIONS) do
			local iconIndex = icon.index
			local iconName = icon.name
			local r, g, b = icon.r, icon.g, icon.b
			AddButton(level, function(info)
				info.text = iconName
				info.func = function()
					SetRaidTarget(unit, iconIndex)
				end
				info.icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. iconIndex
				info.tCoordLeft = 0
				info.tCoordRight = 1
				info.tCoordTop = 0
				info.tCoordBottom = 1
				info.colorCode = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
				info.checked = (currentTarget == iconIndex)
			end)
		end

		AddButton(level, function(info)
			info.text = RAID_TARGET_NONE
			info.func = function()
				SetRaidTarget(unit, 0)
			end
			info.checked = (currentTarget == nil or currentTarget == 0)
		end)
	end

	local function AddLevelOneButtons(level)
		local unitName = UnitName(unit)
		local isPlayer = UnitIsPlayer(unit)

		AddButton(level, function(info)
			info.text = unitName or fallbackTitle
			info.isTitle = true
			info.notCheckable = true
		end)

		AddButton(level, function(info)
			local targetName = unitName
			info.text = WHISPER
			info.notCheckable = true
			info.func = function()
				if targetName then
					ChatFrame_SendTell(targetName)
				end
			end
			info.disabled = not (isPlayer and targetName)
		end)

		AddButton(level, function(info)
			info.text = INSPECT
			info.notCheckable = true
			info.func = function()
				InspectUnit(unit)
			end
			info.disabled = not CanInspect(unit)
		end)

		AddButton(level, function(info)
			local targetName = unitName
			info.text = INVITE
			info.notCheckable = true
			info.func = function()
				if targetName then
					InviteUnit(targetName)
				end
			end
			info.disabled = not (isPlayer and targetName and not UnitInParty(unit) and not UnitInRaid(unit))
		end)

		AddButton(level, function(info)
			local targetName = unitName
			info.text = COMPARE_ACHIEVEMENTS
			info.notCheckable = true
			info.func = function()
				if not AchievementFrame then
					AchievementFrame_LoadUI()
				end
				if AchievementFrame and targetName then
					AchievementFrame_DisplayComparison(targetName)
				end
			end
			info.disabled = not (isPlayer and targetName)
		end)

		AddButton(level, function(info)
			info.text = TRADE
			info.notCheckable = true
			info.func = function()
				InitiateTrade(unit)
			end
			info.disabled = not (isPlayer and CheckInteractDistance(unit, 2))
		end)

		AddButton(level, function(info)
			info.text = FOLLOW
			info.notCheckable = true
			info.func = function()
				FollowUnit(unit)
			end
			info.disabled = not isPlayer
		end)

		AddButton(level, function(info)
			info.text = DUEL
			info.notCheckable = true
			info.func = function()
				StartDuel(unit)
			end
			info.disabled = not (isPlayer and CheckInteractDistance(unit, 3))
		end)

		AddButton(level, function(info)
			info.text = RAID_TARGET_ICON
			info.notCheckable = true
			info.hasArrow = true
			info.value = "RAID_TARGET"
		end)

		if extraLevel1Buttons then
			extraLevel1Buttons(level, unit, AddButton)
		end

		AddButton(level, function(info)
			info.text = CANCEL
			info.notCheckable = true
			info.func = function() CloseDropDownMenus() end
		end)
	end

	dropdown.initialize = function(self, level)
		if not level then
			return
		end

		if level == 1 then
			if level1Builder then
				level1Builder(level, unit, AddButton, fallbackTitle)
			else
				AddLevelOneButtons(level)
			end
		elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "RAID_TARGET" then
			AddRaidTargetMenu(level)
		elseif level2Handlers then
			local handler = level2Handlers[UIDROPDOWNMENU_MENU_VALUE]
			if handler then
				handler(level, unit, AddButton)
			end
		end
	end

	return dropdown
end

-------------------------------------------------------------------------------
-- MOVABLE FRAMES SYSTEM
-------------------------------------------------------------------------------

-- State variables
local frameOverlays = {}
local isUnlocked = false
local pendingPositions = {}
local pendingFocusScale = false
local unsavedPositions = {}
local UpdateOverlayForFrame -- forward declaration

-- Default frame positions
local defaultPositions = {
	UFI_PlayerFrame = {
		point = "TOPLEFT",
		relativePoint = "TOPLEFT",
		x = 5,
		y = -30,
	},
	UFI_TargetFrame = {
		point = "TOPLEFT",
		relativePoint = "TOPLEFT",
		x = 500,
		y = -30,
	},
	UFI_TargetOfTargetFrame = {
		point = "TOPLEFT",
		relativeTo = "UFI_TargetFrame",
		relativePoint = "BOTTOMLEFT",
		x = 385,
		y = 125,
	},
	UFI_FocusFrame = {
		point = "TOPLEFT",
		relativePoint = "TOPLEFT",
		x = 500,
		y = -400,
	},
	UFI_BossFrameAnchor = {
		point = "TOPRIGHT",
		relativePoint = "TOPRIGHT",
		x = 0,
		y = -200,
	},
}

-- Initialize saved variables
local function InitializeDatabase()
	UnitFramesImprovedDB = UnitFramesImprovedDB or {}
	local db = UnitFramesImprovedDB

	db.version = ADDON_VERSION
	db.schemaVersion = tonumber(db.schemaVersion) or 0
	if db.schemaVersion < DB_SCHEMA_VERSION then
		-- Placeholder for future migrations; bump schema once work completes.
		db.schemaVersion = DB_SCHEMA_VERSION
	end

	if type(db.isUnlocked) ~= "boolean" then
		db.isUnlocked = false
	end

	db.positions = db.positions or {}
	db.scales = db.scales or {}

	for frameName, defaultScale in pairs(DEFAULT_FRAME_SCALES) do
		local current = db.scales[frameName]
		if type(current) ~= "number" or current <= 0 then
			db.scales[frameName] = defaultScale
		end
	end
end

-- Sanity-check saved position tables so bad data does not taint frame anchors.
local function ValidatePosition(pos)
	if not pos then
		return false
	end
	if type(pos.x) ~= "number" or type(pos.y) ~= "number" then
		return false
	end
	if not pos.point or not pos.relativePoint then
		return false
	end

	return true
end

-- Fetch a saved position or fall back to the hard-coded defaults.
local function GetSavedPosition(frameName)
	UnitFramesImprovedDB = UnitFramesImprovedDB or {}
	UnitFramesImprovedDB.positions = UnitFramesImprovedDB.positions or {}

	local stored = UnitFramesImprovedDB.positions[frameName]
	if stored and ValidatePosition(stored) then
		return stored
	end

	return defaultPositions[frameName]
end

-- Ensure a frame lands on either its saved position or our layout default.
local function InitializeFramePosition(frameName, frame, pos)
	frame = frame or _G[frameName]
	if not frame then
		return nil
	end

	pos = pos or GetSavedPosition(frameName)
	if not pos then
		return nil
	end

	local relativeFrame = UIParent
	if pos.relativeTo then
		relativeFrame = _G[pos.relativeTo] or UIParent
	end

	ApplySavedScaleToFrame(frame)

	frame:ClearAllPoints()
	frame:SetPoint(pos.point, relativeFrame, pos.relativePoint, pos.x, pos.y)

	return pos
end

-- Repositioning is forbidden while secure frames are in combat lockdown.
local function CanRepositionFrames()
	return not InCombatLockdown()
end

-- Persist the latest coordinates for a given frame.
local function SavePosition(frameName, point, relativePoint, x, y, relativeTo)
	if not UnitFramesImprovedDB.positions then
		UnitFramesImprovedDB.positions = {}
	end

	UnitFramesImprovedDB.positions[frameName] = {
		point = point,
		relativePoint = relativePoint,
		x = x,
		y = y,
		relativeTo = relativeTo,
	}
end

-- Attempt to move a frame immediately, or defer until after combat.
local function ApplyPosition(frameName)
	local frame = _G[frameName]
	if not frame then
		return
	end

	if CanRepositionFrames() then
		local pos = InitializeFramePosition(frameName, frame)
		if pos then
			pendingPositions[frameName] = nil
			local overlay = frameOverlays[frameName]
			if overlay then
				UpdateOverlayForFrame(frameName)
			end
		end
	else
		-- Save for later
		pendingPositions[frameName] = true
	end
end

-- Apply a supplied position blob, respecting combat lockdown rules.
local function ApplyFramePositionData(frameName, pos)
	local frame = _G[frameName]
	if not frame then
		return
	end

	if not CanRepositionFrames() then
		pendingPositions[frameName] = true
		return
	end

	local usedPos = InitializeFramePosition(frameName, frame, pos)
	if usedPos then
		pendingPositions[frameName] = nil
		UpdateOverlayForFrame(frameName)
	end
end

-- Flush any delayed position changes once combat restrictions clear.
local function ApplyPendingPositions()
	if not CanRepositionFrames() then
		return
	end

	for frameName, _ in pairs(pendingPositions) do
		local unsaved = unsavedPositions[frameName]
		if unsaved then
			ApplyFramePositionData(frameName, unsaved)
		else
			ApplyPosition(frameName)
		end
	end

	if next(pendingPositions) then
		Print("Frame positions applied!")
	end
end

-- Restore a frame (and associated scales) back to shipped defaults.
local function ResetFramePosition(frameName)
	local pos = defaultPositions[frameName]
	if not pos then
		Print("Unknown frame: " .. frameName)
		return
	end

	if UnitFramesImprovedDB and UnitFramesImprovedDB.positions then
		UnitFramesImprovedDB.positions[frameName] = nil
	end
	ApplyPosition(frameName)

	local defaultScale = DEFAULT_FRAME_SCALES[frameName]
	if defaultScale then
		SetFrameScale(frameName, defaultScale)
	end

	if frameName == "UFI_BossFrameAnchor" then
		for index = 1, MAX_BOSS_FRAMES do
			local childName = "UFI_BossFrame" .. index
			local childScale = DEFAULT_FRAME_SCALES[childName]
			if childScale then
				SetFrameScale(childName, childScale)
			end
		end
	end

	Print("Reset " .. frameName .. " to default position")
end

-- Paint the move overlay border and segments with the provided color.
local function ApplyOverlayColorTextures(overlay, r, g, b, a)
	if overlay.border then
		overlay.border:SetColorTexture(r, g, b, a)
	end

	if overlay.borderSegments then
		for _, segment in ipairs(overlay.borderSegments) do
			segment:SetColorTexture(r, g, b, a)
		end
	end

	if overlay.bossSegments then
		local segmentAlpha = math.min(1, (a or 0.5) * 0.6)
		for _, segment in ipairs(overlay.bossSegments) do
			segment:SetColorTexture(r, g, b, segmentAlpha)
		end
	end
end

-- Cache overlay color values so drags can temporarily tint them.
local function SetOverlayColor(overlay, r, g, b, a)
	if not overlay then
		return
	end

	overlay.overlayColor = overlay.overlayColor or {}
	overlay.overlayColor.r = r
	overlay.overlayColor.g = g
	overlay.overlayColor.b = b
	overlay.overlayColor.a = a

	ApplyOverlayColorTextures(overlay, r, g, b, a)
end

-- Translate between frame anchors and overlay rectangles to keep drag handles aligned.
local function ComputeAnchorOffsets(point, frameWidth, frameHeight, overlayWidth, overlayHeight, leftInset, topInset)
	point = point or "TOPLEFT"

	local horizontal = "CENTER"
	if string.find(point, "LEFT") then
		horizontal = "LEFT"
	elseif string.find(point, "RIGHT") then
		horizontal = "RIGHT"
	end

	local vertical = "CENTER"
	if string.find(point, "TOP") then
		vertical = "TOP"
	elseif string.find(point, "BOTTOM") then
		vertical = "BOTTOM"
	end

	local frameTopLeftXOffset
	if horizontal == "LEFT" then
		frameTopLeftXOffset = 0
	elseif horizontal == "RIGHT" then
		frameTopLeftXOffset = -frameWidth
	else
		frameTopLeftXOffset = -frameWidth * 0.5
	end

	local frameTopLeftYOffset
	if vertical == "TOP" then
		frameTopLeftYOffset = 0
	elseif vertical == "BOTTOM" then
		frameTopLeftYOffset = frameHeight
	else
		frameTopLeftYOffset = frameHeight * 0.5
	end

	local overlayAnchorToTopLeftX
	if horizontal == "LEFT" then
		overlayAnchorToTopLeftX = 0
	elseif horizontal == "RIGHT" then
		overlayAnchorToTopLeftX = -overlayWidth
	else
		overlayAnchorToTopLeftX = -overlayWidth * 0.5
	end

	local overlayAnchorToTopLeftY
	if vertical == "TOP" then
		overlayAnchorToTopLeftY = 0
	elseif vertical == "BOTTOM" then
		overlayAnchorToTopLeftY = overlayHeight
	else
		overlayAnchorToTopLeftY = overlayHeight * 0.5
	end

	local anchorXOffset = frameTopLeftXOffset + leftInset - overlayAnchorToTopLeftX
	local anchorYOffset = frameTopLeftYOffset - topInset - overlayAnchorToTopLeftY

	return anchorXOffset, anchorYOffset
end

-- Keep overlay frames sized to the underlying secure frame's hit rect.
local function UpdateStandardOverlayGeometry(frame, overlay)
	if not frame or not overlay then
		return
	end

	local rect = frame.ufHitRect
	local left = rect and rect.left or 0
	local right = rect and rect.right or 0
	local top = rect and rect.top or 0
	local bottom = rect and rect.bottom or 0
	local frameWidth = frame:GetWidth()
	local frameHeight = frame:GetHeight()

	local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
	if not point then
		return
	end

	relativeTo = relativeTo or UIParent
	relativePoint = relativePoint or point

	local overlayWidth = math.max(1, frameWidth - left - right)
	local overlayHeight = math.max(1, frameHeight - top - bottom)
	local anchorXOffset, anchorYOffset =
		ComputeAnchorOffsets(point, frameWidth, frameHeight, overlayWidth, overlayHeight, left, top)

	overlay:ClearAllPoints()
	overlay:SetPoint(point, relativeTo, relativePoint, (x or 0) + anchorXOffset, (y or 0) + anchorYOffset)
	overlay:SetSize(overlayWidth, overlayHeight)
	overlay:SetScale(frame:GetScale())
	overlay.anchorAdjustX = anchorXOffset
	overlay.anchorAdjustY = anchorYOffset
	overlay.clickInsets = rect

	if overlay.overlayColor then
		ApplyOverlayColorTextures(
			overlay,
			overlay.overlayColor.r,
			overlay.overlayColor.g,
			overlay.overlayColor.b,
			overlay.overlayColor.a
		)
	else
		ApplyOverlayColorTextures(overlay, 0, 1, 0, 0.5)
	end
end

local function CalculateBossFallbackOverlayData(anchor)
	if not anchor or not anchor.frames then
		return nil
	end

	local baseFrame = anchor.frames[1]
	if not baseFrame then
		return nil
	end

	local activeSlots = 0
	for index, frame in ipairs(anchor.frames) do
		if frame:IsShown() or UnitExists(frame.unit or "") then
			activeSlots = math.max(activeSlots, index)
		end
	end

	if activeSlots == 0 then
		activeSlots = 1
	end

	local anchorWidth = anchor:GetWidth()
	local anchorHeight = anchor:GetHeight()
	local anchorScale = anchor:GetEffectiveScale()
	if not anchorScale or anchorScale == 0 then
		anchorScale = 1
	end

	local rect = baseFrame.ufHitRect
	local leftInset = rect and rect.left or 0
	local rightInset = rect and rect.right or 0
	local topInset = rect and rect.top or 0
	local bottomInset = rect and rect.bottom or 0

	local frameWidth = baseFrame:GetWidth() or 0
	local frameHeight = baseFrame:GetHeight() or 0
	local frameScale = baseFrame:GetEffectiveScale() or anchorScale
	local scaleRatio = frameScale / anchorScale

	local slotWidth = math.max(0, (frameWidth - leftInset - rightInset) * scaleRatio)
	local slotHeight = math.max(0, (frameHeight - topInset - bottomInset) * scaleRatio)
	local slotLeft = leftInset * scaleRatio
	local slotTop = topInset * scaleRatio
	local slotStride = BOSS_FRAME_STRIDE * scaleRatio

	local minLeft = slotLeft
	local minTop = slotTop
	local maxRight = slotLeft + slotWidth
	local maxBottom = slotTop + slotHeight + (activeSlots - 1) * slotStride

	local segments = {}
	for index = 1, activeSlots do
		segments[#segments + 1] = {
			slotIndex = index,
			left = slotLeft,
			top = slotTop + (index - 1) * slotStride,
			width = slotWidth,
			height = slotHeight,
		}
	end

	return {
		minLeft = minLeft,
		minTop = minTop,
		maxRight = maxRight,
		maxBottom = maxBottom,
		segments = segments,
	}
end

local function CalculateBossOverlayData(anchor)
	if not anchor or not anchor.frames then
		return nil
	end

	local anchorLeft = anchor:GetLeft()
	local anchorRight = anchor:GetRight()
	local anchorTop = anchor:GetTop()
	local anchorBottom = anchor:GetBottom()
	local anchorScale = anchor:GetEffectiveScale()
	if
		not anchorLeft
		or not anchorRight
		or not anchorTop
		or not anchorBottom
		or not anchorScale
		or anchorScale == 0
	then
		return CalculateBossFallbackOverlayData(anchor)
	end

	local anchorWidth = anchor:GetWidth()
	local anchorHeight = anchor:GetHeight()
	local minLeft = math.huge
	local minTop = math.huge
	local maxRight = 0
	local maxBottom = 0
	local segments = {}
	local hasLiveData = false

	for index, frame in ipairs(anchor.frames) do
		if frame:IsShown() then
			local left = frame:GetLeft()
			local right = frame:GetRight()
			local top = frame:GetTop()
			local bottom = frame:GetBottom()
			if left and right and top and bottom then
				hasLiveData = true
				local frameEffectiveScale = frame:GetEffectiveScale() or anchorScale
				if frameEffectiveScale == 0 then
					frameEffectiveScale = anchorScale
				end
				local rect = frame.ufHitRect
				if rect then
					local leftInset = rect.left or 0
					local rightInset = rect.right or 0
					local topInset = rect.top or 0
					local bottomInset = rect.bottom or 0
					left = left + leftInset * frameEffectiveScale
					right = right - rightInset * frameEffectiveScale
					top = top - topInset * frameEffectiveScale
					bottom = bottom + bottomInset * frameEffectiveScale
				end

				local localLeft = (left - anchorLeft) / anchorScale
				local localTop = (anchorTop - top) / anchorScale
				local localWidth = math.max(0, (right - left) / anchorScale)
				local localHeight = math.max(0, (top - bottom) / anchorScale)

				minLeft = math.min(minLeft, localLeft)
				minTop = math.min(minTop, localTop)
				maxRight = math.max(maxRight, localLeft + localWidth)
				maxBottom = math.max(maxBottom, localTop + localHeight)

				segments[#segments + 1] = {
					slotIndex = index,
					left = localLeft,
					top = localTop,
					width = localWidth,
					height = localHeight,
				}
			end
		end
	end

	if not hasLiveData or maxRight <= minLeft or maxBottom <= minTop then
		return CalculateBossFallbackOverlayData(anchor)
	end

	return {
		minLeft = minLeft,
		minTop = minTop,
		maxRight = maxRight,
		maxBottom = maxBottom,
		segments = segments,
	}
end

local function UpdateBossOverlayGeometry(anchor, overlay)
	if not anchor or not overlay then
		return
	end

	local data = CalculateBossOverlayData(anchor)
	local point, relativeTo, relativePoint, x, y = anchor:GetPoint(1)
	if not point then
		point = "TOPLEFT"
		relativeTo = UIParent
		relativePoint = "TOPLEFT"
		x, y = 0, 0
	else
		relativeTo = relativeTo or UIParent
		relativePoint = relativePoint or point
	end

	overlay:ClearAllPoints()

	if not data then
		overlay:SetPoint(point, relativeTo, relativePoint, x or 0, y or 0)
		overlay:SetSize(anchor:GetWidth(), anchor:GetHeight())
		overlay:SetScale(anchor:GetScale())
		overlay.anchorAdjustX = 0
		overlay.anchorAdjustY = 0
		overlay.clickInsets = nil

		if overlay.bossSegments then
			for _, segment in ipairs(overlay.bossSegments) do
				segment:Hide()
			end
		end

		return
	end

	local anchorWidth = anchor:GetWidth()
	local anchorHeight = anchor:GetHeight()
	local overlayWidth = math.max(1, data.maxRight - data.minLeft)
	local overlayHeight = math.max(1, data.maxBottom - data.minTop)
	local anchorXOffset, anchorYOffset =
		ComputeAnchorOffsets(point, anchorWidth, anchorHeight, overlayWidth, overlayHeight, data.minLeft, data.minTop)

	overlay:SetPoint(point, relativeTo, relativePoint, (x or 0) + anchorXOffset, (y or 0) + anchorYOffset)
	overlay:SetSize(overlayWidth, overlayHeight)
	overlay:SetScale(anchor:GetScale())
	overlay.anchorAdjustX = anchorXOffset
	overlay.anchorAdjustY = anchorYOffset
	overlay.clickInsets = {
		left = data.minLeft,
		top = data.minTop,
		right = math.max(anchorWidth - data.maxRight, 0),
		bottom = math.max(anchorHeight - data.maxBottom, 0),
	}

	overlay.bossSegments = overlay.bossSegments or {}
	for index, segInfo in ipairs(data.segments) do
		local segment = overlay.bossSegments[index]
		if not segment then
			segment = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
			overlay.bossSegments[index] = segment
		end

		segment:Show()
		segment:ClearAllPoints()
		segment:SetPoint("TOPLEFT", overlay, "TOPLEFT", segInfo.left - data.minLeft, -(segInfo.top - data.minTop))
		segment:SetSize(segInfo.width, segInfo.height)
	end

	if #overlay.bossSegments > #data.segments then
		for index = #data.segments + 1, #overlay.bossSegments do
			overlay.bossSegments[index]:Hide()
		end
	end

	local color = overlay.overlayColor
	if color then
		ApplyOverlayColorTextures(overlay, color.r, color.g, color.b, color.a)
	else
		ApplyOverlayColorTextures(overlay, 0, 1, 0, 0.5)
	end
end

-- Recalculate overlay placement unless a drag operation is in progress.
UpdateOverlayForFrame = function(frameName)
	local overlay = frameOverlays[frameName]
	if not overlay or overlay.isDragging then
		return
	end

	local frame = _G[frameName]
	if not frame then
		return
	end

	if frameName == "UFI_BossFrameAnchor" then
		UpdateBossOverlayGeometry(frame, overlay)
	else
		UpdateStandardOverlayGeometry(frame, overlay)
	end
end

-- Translate overlay drag coordinates back into frame offsets.
local function OverlayOffsetsToFrameOffsets(overlay, point, x, y)
	if not overlay then
		return x or 0, y or 0
	end

	local frame = overlay.secureFrame
	if not frame then
		return x or 0, y or 0
	end

	point = point or "TOPLEFT"

	local frameWidth = frame:GetWidth()
	local frameHeight = frame:GetHeight()
	if not frameWidth or not frameHeight or frameWidth == 0 or frameHeight == 0 then
		return x or 0, y or 0
	end

	local rect = overlay.clickInsets
	local leftInset = rect and rect.left or 0
	local topInset = rect and rect.top or 0

	local overlayWidth = overlay:GetWidth()
	local overlayHeight = overlay:GetHeight()
	local anchorXOffset, anchorYOffset =
		ComputeAnchorOffsets(point, frameWidth, frameHeight, overlayWidth, overlayHeight, leftInset, topInset)

	return (x or 0) - anchorXOffset, (y or 0) - anchorYOffset
end

-- Create overlay for a frame
local function CreateOverlay(frame, frameName)
	local overlay = CreateFrame("Frame", frameName .. "_Overlay", UIParent)
	overlay:SetFrameStrata("HIGH")
	overlay:SetFrameLevel(100)
	overlay:EnableMouse(false)
	overlay:SetMovable(true)
	overlay:RegisterForDrag("LeftButton")
	overlay:SetClampedToScreen(true)
	overlay:Hide()

	overlay.border = overlay:CreateTexture(nil, "OVERLAY")
	overlay.border:SetAllPoints()
	SetOverlayColor(overlay, 0, 1, 0, 0.5)

	overlay.label = overlay:CreateFontString(nil, "OVERLAY")
	overlay.label:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
	overlay.label:SetPoint("CENTER")
	local displayName = frameName:gsub("UFI_", "")
	if frameName == "UFI_BossFrameAnchor" then
		displayName = "BossFrames"
	end
	overlay.label:SetText(displayName)

	overlay.secureFrame = frame
	overlay.isDragging = false
	overlay.dragStartLeft = 0
	overlay.dragStartTop = 0

	frameOverlays[frameName] = overlay

	if frame and not frame.UFIOverlayHooks then
		frame.UFIOverlayHooks = true
		local nameRef = frameName
		hooksecurefunc(frame, "SetPoint", function()
			UpdateOverlayForFrame(nameRef)
		end)
		hooksecurefunc(frame, "SetSize", function()
			UpdateOverlayForFrame(nameRef)
		end)
		hooksecurefunc(frame, "SetWidth", function()
			UpdateOverlayForFrame(nameRef)
		end)
		hooksecurefunc(frame, "SetHeight", function()
			UpdateOverlayForFrame(nameRef)
		end)
		hooksecurefunc(frame, "SetScale", function()
			UpdateOverlayForFrame(nameRef)
		end)
	end
	UpdateOverlayForFrame(frameName)

	local function FinishOverlayDrag(self, attemptApply)
		self:SetFrameLevel(100)

		local point, relativeToFrame, relativePoint, x, y = self:GetPoint()
		point = point or "TOPLEFT"
		relativePoint = relativePoint or point

		local frameX, frameY = OverlayOffsetsToFrameOffsets(self, point, x, y)
		local relativeToName
		if relativeToFrame then
			relativeToName = relativeToFrame:GetName()
			if not relativeToName and relativeToFrame == UIParent then
				relativeToName = "UIParent"
			end
		else
			relativeToName = "UIParent"
		end

		unsavedPositions[frameName] = {
			point = point,
			relativePoint = relativePoint,
			x = frameX,
			y = frameY,
			relativeTo = relativeToName,
		}

		if not attemptApply then
			SetOverlayColor(self, 0, 1, 0, 0.5)
			UpdateOverlayForFrame(frameName)
			return
		end

		if CanRepositionFrames() then
			local frame = self.secureFrame
			if frame then
				frame:ClearAllPoints()
				local relativeFrame = relativeToFrame
				if not relativeFrame then
					if relativeToName and relativeToName ~= "UIParent" then
						relativeFrame = _G[relativeToName]
					else
						relativeFrame = UIParent
					end
				end
				relativeFrame = relativeFrame or UIParent
				frame:SetPoint(point, relativeFrame, relativePoint, frameX, frameY)
			end
			pendingPositions[frameName] = nil
			SetOverlayColor(self, 0, 1, 0, 0.5)
			UpdateOverlayForFrame(frameName)
		else
			pendingPositions[frameName] = true
			SetOverlayColor(self, 1, 0.5, 0, 0.5)
		end
	end

	local function CompleteOverlayDrag(self)
		self:StopMovingOrSizing()
		local endLeft = self:GetLeft() or 0
		local endTop = self:GetTop() or 0
		local moved = math.abs(endLeft - (self.dragStartLeft or endLeft)) >= 0.5
			or math.abs(endTop - (self.dragStartTop or endTop)) >= 0.5

		self.isDragging = false

		if not moved then
			self:SetFrameLevel(100)
			SetOverlayColor(self, 0, 1, 0, 0.5)
			UpdateOverlayForFrame(frameName)
			return
		end

		FinishOverlayDrag(self, true)
	end

	overlay:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" and isUnlocked then
			self.isDragging = true
			self.dragStartLeft = self:GetLeft() or 0
			self.dragStartTop = self:GetTop() or 0
			self:SetFrameLevel(110)
			SetOverlayColor(self, 1, 1, 0, 0.7)
			self:StartMoving()
		end
	end)

	overlay:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and self.isDragging then
			CompleteOverlayDrag(self)
		end
	end)

	overlay:SetScript("OnDragStop", function(self)
		if self.isDragging then
			CompleteOverlayDrag(self)
		end
	end)

	overlay:SetScript("OnEnter", function(self)
		if isUnlocked and not self.isDragging then
			SetOverlayColor(self, 0.5, 1, 0.5, 0.7)
		end
	end)

	overlay:SetScript("OnLeave", function(self)
		if isUnlocked and not self.isDragging then
			SetOverlayColor(self, 0, 1, 0, 0.5)
		end
	end)

	return overlay
end

-- Unlock frames for movement
local function UnlockFrames()
	if InCombatLockdown() then
		Print("|cffff0000Cannot unlock frames during combat!|r")
		return
	end

	isUnlocked = true
	UnitFramesImprovedDB.isUnlocked = true

	for frameName, overlay in pairs(frameOverlays) do
		UpdateOverlayForFrame(frameName)
		overlay:Show()
		overlay:EnableMouse(true)
		SetOverlayColor(overlay, 0, 1, 0, 0.5) -- Green for unlocked
	end

	Print("Frames unlocked! Drag to reposition. Type /ufi lock to save.")
end

-- Lock frames and save positions
local function LockFrames()
	for frameName, pos in pairs(unsavedPositions) do
		SavePosition(frameName, pos.point, pos.relativePoint, pos.x, pos.y, pos.relativeTo)
	end
	if next(unsavedPositions) then
		Print("Stored frame positions. Unlock again to make further adjustments.")
	end
	table_wipe(unsavedPositions)

	isUnlocked = false
	UnitFramesImprovedDB.isUnlocked = false

	-- Hide overlays
	for _, overlay in pairs(frameOverlays) do
		overlay:Hide()
		overlay:EnableMouse(false)
	end

	-- Apply any pending positions if possible
	if CanRepositionFrames() then
		ApplyPendingPositions()
		Print("Frames locked and positions saved!")
	else
		Print("Frames locked! Positions will apply after combat.")
	end
end

-- Apply focus frame scale based on interface option setting
local function ApplyFocusFrameScale()
	if not UFI_FocusFrame then
		return
	end

	-- Defer scale changes during combat
	if InCombatLockdown() then
		pendingFocusScale = true
		return
	end

	local fullSize = GetCVarBool("fullSizeFocusFrame")
	local desiredScale = fullSize and 0.55 or 0.45

	-- Only apply if user hasn't manually scaled the frame
	local currentScale = GetFrameScale("UFI_FocusFrame")
	local defaultLarge = 0.55
	local defaultSmall = 0.45

	-- Check if current scale matches either default (meaning user hasn't customized it)
	if currentScale == defaultLarge or currentScale == defaultSmall then
		SetFrameScale("UFI_FocusFrame", desiredScale)
	end

	pendingFocusScale = false
end

-- Handle combat start
local function OnCombatStart()
	if isUnlocked then
		-- Disable dragging during combat
		for _, overlay in pairs(frameOverlays) do
			overlay:EnableMouse(false)
			SetOverlayColor(overlay, 1, 0, 0, 0.5) -- Red for locked
			local labelText = overlay.label:GetText() or ""
			if not labelText:find(" %(COMBAT%)$") then
				overlay.label:SetText(labelText .. " (COMBAT)")
			end
		end
		Print("|cffff8800Frame movement disabled during combat!|r")
	end

	UpdatePlayerLevel()
end

-- Handle combat end
local function OnCombatEnd()
	-- Apply pending positions
	ApplyPendingPositions()

	-- Apply pending focus scale if needed
	if pendingFocusScale then
		ApplyFocusFrameScale()
	end

	-- Re-enable dragging if unlocked
	if isUnlocked then
		for _, overlay in pairs(frameOverlays) do
			overlay:EnableMouse(true)
			SetOverlayColor(overlay, 0, 1, 0, 0.5) -- Back to green
			overlay.label:SetText((overlay.label:GetText() or ""):gsub(" %(COMBAT%)$", ""))
		end
		Print("Frame movement re-enabled!")
	end

	UpdatePlayerLevel()
end

-- Slash command handler
SLASH_UFI1 = "/ufi"
SlashCmdList["UFI"] = function(msg)
	local cmd, arg = msg:match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()

	if cmd == "unlock" then
		UnlockFrames()
	elseif cmd == "lock" then
		LockFrames()
	elseif cmd == "reset" then
		if arg and arg ~= "" then
			local normalized = arg:lower()
			local frameAliases = {
				player = "UFI_PlayerFrame",
				target = "UFI_TargetFrame",
				focus = "UFI_FocusFrame",
				tot = "UFI_TargetOfTargetFrame",
				targetoftarget = "UFI_TargetOfTargetFrame",
				boss = "UFI_BossFrameAnchor",
				bosses = "UFI_BossFrameAnchor",
				bossframe = "UFI_BossFrameAnchor",
				bossframes = "UFI_BossFrameAnchor",
				bossanchor = "UFI_BossFrameAnchor",
			}

			local frameName = frameAliases[normalized]
			if not frameName then
				frameName = "UFI_" .. normalized:sub(1, 1):upper() .. normalized:sub(2) .. "Frame"
			end

			ResetFramePosition(frameName)
		else
			-- Reset all frames
			for frameName, _ in pairs(defaultPositions) do
				ResetFramePosition(frameName)
			end
		end
	elseif cmd == "help" or cmd == "" then
		Print("|cff00ff00UnitFramesImproved v" .. ADDON_VERSION .. "|r")
		Print("Available commands:")
		Print("  |cffffcc00/ufi unlock|r - Unlock frames for repositioning")
		Print("  |cffffcc00/ufi lock|r - Lock frames and save positions")
		Print("  |cffffcc00/ufi reset [frame]|r - Reset frame(s) to default position")
		Print(
			"    Examples: |cff888888/ufi reset player|r, |cff888888/ufi reset boss|r, |cff888888/ufi reset|r (resets all)"
		)
		Print("  |cffffcc00/ufi help|r - Show this help message")
	else
		Print("Unknown command. Type |cffffcc00/ufi help|r for available commands.")
	end
end

-------------------------------------------------------------------------------
-- PLAYER FRAME CREATION
-------------------------------------------------------------------------------

local function CreateUnitFrame(config)
	assert(type(config) == "table", "CreateUnitFrame requires a configuration table")
	assert(config.name, "CreateUnitFrame requires a frame name")
	assert(config.unit, "CreateUnitFrame requires a unit token")

	local frame = CreateFrame("Button", config.name, config.parent or UIParent, "SecureUnitButtonTemplate")
	frame.unitToken = config.unit
	frame.mirrored = not not config.mirrored

	local desiredLevel = config.frameLevel or 20
	frame:SetFrameLevel(desiredLevel)

	local texturePath = config.texturePath or FRAME_TEXTURES.default
	local visual = SetupUnitFrameBase(frame, texturePath, frame.mirrored)
	frame.visualLayer = visual

	local frameStrata = config.frameStrata or "LOW"
	frame:SetFrameStrata(frameStrata)
	visual:SetFrameStrata(frameStrata)
	visual:SetFrameLevel(frame:GetFrameLevel())

	local includeHealthBar = config.includeHealthBar ~= false
	local includePowerBar = config.includePowerBar ~= false
	local includePortrait = config.includePortrait ~= false

	if includeHealthBar then
		frame.healthBar = CreateStatusBar(visual, UFI_LAYOUT.Health, frame.mirrored)
	end

	if includePowerBar then
		frame.powerBar = CreateStatusBar(visual, UFI_LAYOUT.Power, frame.mirrored)
	end

	if includePortrait then
		frame.portrait = CreatePortrait(visual, frame.mirrored)
	end

	local levelX, levelY, levelWidth, levelHeight = LayoutResolveRect(UFI_LAYOUT.LevelRest, frame.mirrored)
	local levelFont = config.levelFont or {}
	frame.levelText = CreateFontString(visual, {
		point = "TOPLEFT",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = levelX,
		y = -levelY,
		size = levelFont.size or 14,
		flags = levelFont.flags or "OUTLINE",
		color = levelFont.color or { r = 1, g = 0.82, b = 0 },
		drawLayer = levelFont.drawLayer or 0,
	})
	frame.levelText:SetSize(levelWidth, levelHeight)
	frame.levelText:SetJustifyH("CENTER")
	frame.levelText:SetJustifyV("MIDDLE")

	local textStyles = config.textStyles or {}
	local defaultTextStyles = {
		name = {
			y = 8,
			size = 16,
			flags = "THICKOUTLINE",
			drawLayer = 7,
			color = { r = NAME_TEXT_COLOR_R, g = NAME_TEXT_COLOR_G, b = NAME_TEXT_COLOR_B },
		},
		health = {
			y = -10,
			size = 14,
			flags = "OUTLINE",
			drawLayer = 7,
			color = { r = 1, g = 1, b = 1 },
		},
		power = {
			y = 0,
			size = 13,
			flags = "OUTLINE",
			drawLayer = 7,
			color = { r = 1, g = 1, b = 1 },
		},
	}

	local function createText(parent, defaults, style)
		if not parent or style == false then
			return nil
		end

		style = style or {}

		local fontOptions = {
			point = "CENTER",
			relativeTo = parent,
			relativePoint = "CENTER",
			x = style.x or defaults.x or 0,
			y = style.y or defaults.y or 0,
			size = style.size or defaults.size,
			flags = style.flags or defaults.flags,
			drawLayer = style.drawLayer or defaults.drawLayer,
		}

		local color = style.color or defaults.color
		if color then
			fontOptions.color = color
		end

		return CreateFontString(parent, fontOptions)
	end

	if includeHealthBar and textStyles.name ~= false then
		frame.nameText = createText(frame.healthBar, defaultTextStyles.name, textStyles.name)
	end

	if includeHealthBar and textStyles.health ~= false then
		frame.healthText = createText(frame.healthBar, defaultTextStyles.health, textStyles.health)
	end

	if includePowerBar and textStyles.power ~= false then
		frame.powerText = createText(frame.powerBar, defaultTextStyles.power, textStyles.power)
	end

	if config.enableMouse ~= false then
		frame:EnableMouse(true)
	else
		frame:EnableMouse(false)
	end

	if config.clicks ~= false then
		if type(config.clicks) == "table" then
			frame:RegisterForClicks(unpack(config.clicks))
		else
			frame:RegisterForClicks(config.clicks or "AnyUp")
		end
	end

	if config.initializePosition ~= false then
		if type(config.initializePosition) == "function" then
			config.initializePosition(frame)
		else
			InitializeFramePosition(config.name, frame)
		end
	end

	local profile = {}
	if type(config.profile) == "table" then
		for key, value in pairs(config.profile) do
			profile[key] = value
		end
	end
	profile.unit = config.unit
	frame.ufProfile = profile

	if config.postCreate then
		config.postCreate(frame)
	end

	return frame
end

-------------------------------------------------------------------------------
-- UNIT FRAME FACTORY HELPERS
-------------------------------------------------------------------------------

local function ApplyUnitFrameProfileDefaults(frame, defaults)
	if not frame then
		return nil
	end

	local profile = frame.ufProfile or {}
	defaults = defaults or {}

	if defaults.customLevelUpdate ~= nil then
		profile.customLevelUpdate = defaults.customLevelUpdate
	end

	local powerDefaults = defaults.power
	if powerDefaults then
		local powerProfile = profile.power or {}
		for key, value in pairs(powerDefaults) do
			powerProfile[key] = value
		end
		profile.power = powerProfile
	end

	local levelDefaults = defaults.level
	if levelDefaults then
		local levelProfile = profile.level or {}
		for key, value in pairs(levelDefaults) do
			levelProfile[key] = value
		end
		profile.level = levelProfile
	end

	frame.ufProfile = profile
	return profile
end

local function AttachStatusIndicator(frame, options)
	if not frame or not frame.healthBar then
		return nil
	end

	options = options or {}

	local fontOptions = {
		point = options.point or "CENTER",
		relativeTo = options.relativeTo or frame.healthBar,
		relativePoint = options.relativePoint or options.point or "CENTER",
		x = options.x or 0,
		y = options.y or -12,
		size = options.size or 20,
		flags = options.flags or "OUTLINE",
		color = options.color or { r = 0.5, g = 0.5, b = 0.5 },
		drawLayer = options.drawLayer or 7,
	}

	local label = CreateFontString(options.parent or frame.healthBar, fontOptions)
	label:Hide()

	local statusConfig = {
		trackDead = options.trackDead,
		trackGhost = options.trackGhost,
		trackDisconnected = options.trackDisconnected,
		zeroHealthWhenStatus = options.zeroHealthWhenStatus,
		labelFontString = label,
		labels = options.labels or {},
		hideHealthTextOnStatus = options.hideHealthTextOnStatus,
	}

	frame.ufProfile.status = statusConfig
	return label, statusConfig
end

local function AttachClassificationOverlay(frame, options)
	if not frame or not frame.visualLayer then
		return nil
	end

	options = options or {}

	local texturePath = options.texture or FRAME_TEXTURES.default
	local layer = options.layer or "OVERLAY"
	local subLevel = options.subLevel or 1

	local texture = CreateUnitArtTexture(frame.visualLayer, texturePath, frame.mirrored, layer, subLevel)
	texture:Hide()
	frame.ufProfile.classificationTexture = texture
	frame.ufProfile.classificationTextures = options.textures or BOSS_CLASSIFICATION_TEXTURES
	return texture
end

local function AttachAuraContainers(frame, config)
	if not frame then
		return nil, nil
	end

	config = config or {}

	local buffsConfig = config.buffs
	if buffsConfig ~= false then
		buffsConfig = buffsConfig or {}
		if buffsConfig.parent == nil then
			buffsConfig.parent = frame.visualLayer
		end
		if buffsConfig.mirrored == nil then
			buffsConfig.mirrored = frame.mirrored
		end
		frame.buffs = CreateAuraRow(frame, buffsConfig)
	else
		frame.buffs = nil
	end

	local debuffsConfig = config.debuffs
	if debuffsConfig ~= false then
		debuffsConfig = debuffsConfig or {}
		if debuffsConfig.parent == nil then
			debuffsConfig.parent = frame.visualLayer
		end
		if debuffsConfig.mirrored == nil then
			debuffsConfig.mirrored = frame.mirrored
		end
		frame.debuffs = CreateAuraRow(frame, debuffsConfig)
	else
		frame.debuffs = nil
	end

	return frame.buffs, frame.debuffs
end

local function MakeUnitFrameUpdater(frameAccessor, updater)
	return function(...)
		local frame = frameAccessor(...)
		if frame then
			updater(frame, ...)
		end
	end
end

local function GetPlayerFrame()
	return UFI_PlayerFrame
end

local function GetTargetFrame()
	return UFI_TargetFrame
end

local function GetFocusFrame()
	return UFI_FocusFrame
end

local function GetTargetOfTargetFrame()
	return UFI_TargetOfTargetFrame
end

local function GetBossFrame(unit)
	if not unit then
		return nil
	end

	return bossFramesByUnit[unit]
end

local function CreatePlayerFrame()
	local frame = CreateUnitFrame({
		name = "UFI_PlayerFrame",
		unit = "player",
		mirrored = true,
		texturePath = FRAME_TEXTURES.player,
		frameLevel = 25,
	})

	ApplyUnitFrameProfileDefaults(frame, {
		power = { hideTextWhenNoPower = true },
		level = { colorByPlayerDiff = true },
		customLevelUpdate = UpdatePlayerLevel,
	})

	frame.texture:SetVertexColor(
		PLAYER_TEXTURE_COLORS.normal.r,
		PLAYER_TEXTURE_COLORS.normal.g,
		PLAYER_TEXTURE_COLORS.normal.b
	)
	frame.portraitMask:SetVertexColor(
		PLAYER_TEXTURE_COLORS.normal.r,
		PLAYER_TEXTURE_COLORS.normal.g,
		PLAYER_TEXTURE_COLORS.normal.b
	)
	frame.currentVertexColor = PLAYER_TEXTURE_COLORS.normal

	SetPortraitTexture(frame.portrait, "player")
	frame.nameText:SetText(UnitName("player"))
	frame.healthText:SetText("")
	frame.powerText:SetText("")

	local selfBuffLevel = math.max((frame.visualLayer:GetFrameLevel() or 1) - 1, 0)
	frame.selfBuffs = CreateAuraRow(frame, {
		parent = frame.visualLayer,
		mirrored = frame.mirrored,
		count = 5,
		position = "above",
		order = 1,
		frameStrata = "LOW",
		frameLevel = selfBuffLevel,
	})
	for i = 1, #frame.selfBuffs do
		frame.selfBuffs[i].border:SetVertexColor(1, 1, 1)
	end

	local dropdown = CreateUnitInteractionDropdown("player", "UFI_PlayerFrameDropDown", {
		fallbackTitle = PLAYER or "Player",
		level1Builder = function(level, unitId, addButton, defaultTitle)
			if level ~= 1 then
				return
			end

			local unitName = UnitName(unitId) or defaultTitle or "Player"

			addButton(level, function(info)
				info.text = unitName
				info.isTitle = true
				info.notCheckable = true
			end)

			addButton(level, function(info)
				info.text = DUNGEON_DIFFICULTY
				info.notCheckable = true
				info.hasArrow = true
				info.value = "DUNGEON_DIFFICULTY"
			end)

			addButton(level, function(info)
				info.text = RAID_DIFFICULTY
				info.notCheckable = true
				info.hasArrow = true
				info.value = "RAID_DIFFICULTY"
			end)

			addButton(level, function(info)
				info.text = RESET_INSTANCES
				info.notCheckable = true
				info.hasArrow = true
				info.value = "RESET_INSTANCES"
			end)

			addButton(level, function(info)
				info.text = RAID_TARGET_ICON
				info.notCheckable = true
				info.hasArrow = true
				info.value = "RAID_TARGET"
			end)

			local partyMemberCount = GetNumPartyMembers()
			local raidMemberCount = GetNumRaidMembers()
			if partyMemberCount > 0 or raidMemberCount > 0 then
				local isRaid = raidMemberCount > 0
				local leaveText
				if isRaid then
					leaveText = LEAVE_RAID or LEAVE_GROUP or LEAVE_PARTY or "Leave Raid"
				else
					leaveText = LEAVE_PARTY or LEAVE_GROUP or "Leave Party"
				end

				addButton(level, function(leaveInfo)
					leaveInfo.text = leaveText
					leaveInfo.notCheckable = true
					leaveInfo.func = function()
						LeaveParty()
					end
				end)
			end

			addButton(level, function(info)
				info.text = CANCEL
				info.notCheckable = true
				info.func = function()
					CloseDropDownMenus()
				end
			end)
		end,
		level2Handlers = {
			DUNGEON_DIFFICULTY = function(level, unitId, addButton)
				local currentDifficulty = GetDungeonDifficulty()
				local options = {
					{ text = "5 Player",          value = 1 },
					{ text = "5 Player (Heroic)", value = 2 },
					{ text = "5 Player (Mythic)", value = 3 },
				}

				for _, option in ipairs(options) do
					addButton(level, function(info)
						info.text = option.text
						info.func = function()
							SetDungeonDifficulty(option.value)
						end
						info.checked = (currentDifficulty == option.value)
					end)
				end
			end,
			RAID_DIFFICULTY = function(level, unitId, addButton)
				local currentDifficulty = GetRaidDifficulty()
				local options = {
					{ text = "Normal (10-25 Players)",   value = 1 },
					{ text = "Heroic (10-25 Players)",   value = 2 },
					{ text = "Mythic (10-25 Players)",   value = 3 },
					{ text = "Ascended (10-25 Players)", value = 4 },
				}

				for _, option in ipairs(options) do
					addButton(level, function(info)
						info.text = option.text
						info.func = function()
							SetRaidDifficulty(option.value)
						end
						info.checked = (currentDifficulty == option.value)
					end)
				end
			end,
			RESET_INSTANCES = function(level, unitId, addButton)
				addButton(level, function(info)
					info.text = RESET_ALL_DUNGEONS
					info.notCheckable = true
					info.func = function()
						StaticPopup_Show("CONFIRM_RESET_INSTANCES")
					end
				end)
			end,
		},
	})

	-- Initialize secure unit button with menu function
	SecureUnitButton_OnLoad(frame, "player", function(self, unit, button)
		ToggleDropDownMenu(1, nil, dropdown, self, 110, 45)
	end)

	frame:Show()
	return frame
end

-------------------------------------------------------------------------------
-- CAST BAR STATE AND FUNCTIONS
-------------------------------------------------------------------------------

-- Cast bar state machine
local CASTBAR_STATE = FreezeTable({
	HIDDEN = "hidden",
	CASTING = "casting",
	CHANNELING = "channeling",
	FINISHED = "finished", -- Holding the end state (for interrupts/fails)
	FADING = "fading",
}, "CASTBAR_STATE")

local castBarsByUnit = {}

local function CreateCastBar(parent, unit, mirrored)
	mirrored = not not mirrored
	local healthX, _, healthWidth = LayoutResolveRect(UFI_LAYOUT.Health, mirrored)
	local width = healthWidth
	local widthScale = width / UFI_LAYOUT.CastBar.DefaultWidth
	local height =
		math.max(UFI_LAYOUT.CastBar.DefaultHeight, math.floor(UFI_LAYOUT.CastBar.DefaultHeight * widthScale + 0.5))
	local offsetY = UFI_LAYOUT.CastBar.OffsetY
	local anchorPoint
	local anchorX

	if mirrored then
		anchorPoint = "TOPRIGHT"
		anchorX = healthX + width
	else
		anchorPoint = "TOPLEFT"
		anchorX = healthX
	end

	local castBar = CreateFrame("StatusBar", nil, parent)
	castBar:SetSize(width, height)
	castBar:SetPoint(anchorPoint, parent, "BOTTOMLEFT", anchorX, -offsetY)
	castBar:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
	castBar:SetStatusBarTexture(STATUSBAR_TEXTURE)
	local fill = castBar:GetStatusBarTexture()
	fill:SetHorizTile(false)
	fill:SetVertTile(false)
	local fillCoords = UFI_LAYOUT.CastBar.Fill
	local texSize = UFI_LAYOUT.CastBar.TextureSize
	local left = fillCoords.x / texSize.width
	local right = (fillCoords.x + fillCoords.width) / texSize.width
	local top = fillCoords.y / texSize.height
	local bottom = (fillCoords.y + fillCoords.height) / texSize.height
	fill:SetTexCoord(left, right, top, bottom)
	castBar:SetMinMaxValues(0, 1)
	castBar:SetValue(0)
	castBar:Hide()

	local bg = castBar:CreateTexture(nil, "BACKGROUND")
	bg:SetColorTexture(0, 0, 0, 0.65)
	bg:SetAllPoints(castBar)

	-- Restore decorative border with proportional scaling so it still hugs the bar
	local borderWidth = math.floor(width * (195 / 148) + 0.5)
	local borderHeight = math.floor(height * (50 / 12) + 0.5)
	local borderOffsetY = math.floor(height * (20 / 12) + 0.5)
	local border = castBar:CreateTexture(nil, "OVERLAY", nil, 1)
	border:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border-Small")
	border:SetSize(borderWidth, borderHeight)
	border:SetPoint("TOP", castBar, "TOP", 0, borderOffsetY)
	castBar.border = border

	local text = castBar:CreateFontString(nil, "OVERLAY")
	text:SetFont(FONT_DEFAULT, math.max(10, math.floor(height * 0.65)), "OUTLINE")
	text:SetTextColor(1, 1, 1)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("MIDDLE")
	text:SetWordWrap(false)
	text:ClearAllPoints()
	text:SetPoint("LEFT", castBar, "LEFT", 4, 2)
	text:SetPoint("TOP", castBar, "TOP", 0, 2)
	text:SetPoint("BOTTOM", castBar, "BOTTOM", 0, 2)
	castBar.text = text

	local time = castBar:CreateFontString(nil, "OVERLAY")
	time:SetFont(FONT_DEFAULT, math.max(10, math.floor(height * 0.65)), "OUTLINE")
	time:SetTextColor(1, 1, 1)
	time:SetJustifyH("RIGHT")
	time:SetJustifyV("MIDDLE")
	time:SetWordWrap(false)
	time:ClearAllPoints()
	time:SetPoint("RIGHT", castBar, "RIGHT", -4, 2)
	time:SetPoint("TOP", castBar, "TOP", 0, 2)
	time:SetPoint("BOTTOM", castBar, "BOTTOM", 0, 2)
	castBar.time = time

	text:SetPoint("RIGHT", time, "LEFT", -6, 0)

	local icon = castBar:CreateTexture(nil, "OVERLAY")
	local iconSize = 30
	icon:SetSize(iconSize, iconSize)
	if mirrored then
		icon:SetPoint("LEFT", castBar, "RIGHT", 4, 0)
	else
		icon:SetPoint("RIGHT", castBar, "LEFT", -4, 0)
	end
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	castBar.icon = icon

	local iconBorder = castBar:CreateTexture(nil, "OVERLAY", nil, 1)
	iconBorder:SetPoint("CENTER", icon, "CENTER", 0, 0)
	iconBorder:SetSize(34, 34)
	iconBorder:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
	iconBorder:SetTexCoord(39 / 128, (39 + 34) / 128, 0 / 64, 34 / 64)
	castBar.iconBorder = iconBorder
	iconBorder:Hide()

	castBar.unit = unit
	castBar.mirrored = mirrored
	castBar.state = CASTBAR_STATE.HIDDEN
	castBar.startTime = 0
	castBar.endTime = 0
	castBar.notInterruptible = false
	castBar.holdUntil = 0
	castBar.fadeStartTime = 0
	castBar.spellName = ""
	castBar.spellTexture = ""

	castBarsByUnit[unit] = castBar
	return castBar
end

local function UpdateCastBar(castBar)
	if not castBar or castBar.state == CASTBAR_STATE.HIDDEN then
		return
	end

	local unit = castBar.unit
	if not unit or not UnitExists(unit) then
		castBar:Hide()
		castBar.state = CASTBAR_STATE.HIDDEN
		return
	end

	local currentTime = GetTime()
	local state = castBar.state

	if state == CASTBAR_STATE.FINISHED then
		if currentTime >= castBar.holdUntil then
			castBar.state = CASTBAR_STATE.FADING
			castBar.fadeStartTime = currentTime
		end
		return
	end

	if state == CASTBAR_STATE.FADING then
		local fadeDuration = 1
		local fadeElapsed = currentTime - castBar.fadeStartTime

		if fadeElapsed >= fadeDuration then
			castBar:Hide()
			castBar:SetAlpha(1)
			castBar.state = CASTBAR_STATE.HIDDEN
		else
			local alpha = 1 - (fadeElapsed / fadeDuration)
			castBar:SetAlpha(alpha)
		end
		return
	end

	if state == CASTBAR_STATE.CASTING or state == CASTBAR_STATE.CHANNELING then
		local remaining = castBar.endTime - currentTime
		if remaining < 0 then
			castBar:SetValue(1)
			return
		end

		local duration = castBar.endTime - castBar.startTime
		local progress
		if state == CASTBAR_STATE.CHANNELING then
			progress = duration > 0 and (remaining / duration) or 0
		else
			progress = duration > 0 and (1 - (remaining / duration)) or 0
		end

		castBar:SetValue(progress)
		castBar.time:SetText(string.format("%.1f", remaining))

		if castBar.notInterruptible then
			castBar:SetStatusBarColor(0.5, 0.5, 0.5)
			castBar.border:SetVertexColor(0.7, 0, 0) -- Red border for uninterruptible
			if castBar.iconBorder then
				castBar.iconBorder:SetVertexColor(0.5, 0, 0.3) -- Purple icon border
			end
		else
			castBar:SetStatusBarColor(1, 0.7, 0)
			castBar.border:SetVertexColor(0, 1, 0) -- Green border for interruptible
			if castBar.iconBorder then
				castBar.iconBorder:SetVertexColor(1, 0.9, 0) -- Gold icon border
			end
		end
	end
end

local function BeginCast(unit, isChannel)
	local castBar = castBarsByUnit[unit]
	if not castBar then
		return
	end

	local info = isChannel and { UnitChannelInfo(unit) } or { UnitCastingInfo(unit) }
	local name = info[1]
	if not name then
		return
	end

	local texture = info[4]
	local startTime = info[5]
	local endTime = info[6]
	local notInterruptible = isChannel and (info[8] or false) or (info[9] or false)

	castBar.state = isChannel and CASTBAR_STATE.CHANNELING or CASTBAR_STATE.CASTING
	castBar.startTime = (startTime or 0) / 1000
	castBar.endTime = (endTime or 0) / 1000
	castBar.notInterruptible = notInterruptible
	castBar.holdUntil = 0
	castBar.fadeStartTime = 0
	castBar.spellName = name
	castBar.spellTexture = texture or ""
	castBar:SetAlpha(1)
	castBar:SetValue(isChannel and 1 or 0)
	castBar.text:SetText(name)
	castBar.time:SetText("")
	castBar.icon:SetTexture(texture)
	if castBar.iconBorder then
		castBar.iconBorder:Show()
	end
	-- Color is set by UpdateCastBar based on interruptibility
	castBar:Show()
	UpdateCastBar(castBar)
end

local function StopCast(unit)
	local castBar = castBarsByUnit[unit]
	if not castBar then
		return
	end

	if castBar.state == CASTBAR_STATE.CASTING or castBar.state == CASTBAR_STATE.CHANNELING then
		castBar.state = CASTBAR_STATE.FADING
		castBar.fadeStartTime = GetTime()
	end
end

local function FailCast(unit, wasInterrupted)
	local castBar = castBarsByUnit[unit]
	if not castBar then
		return
	end

	if castBar.state ~= CASTBAR_STATE.FINISHED then
		if wasInterrupted then
			castBar:SetStatusBarColor(1, 0, 0)
			castBar.text:SetText("Interrupted")
			castBar.border:SetVertexColor(1, 0, 0) -- Red border for interrupted
			if castBar.iconBorder then
				castBar.iconBorder:SetVertexColor(1, 0, 0) -- Red icon border
			end
		else
			castBar:SetStatusBarColor(0.5, 0.5, 0.5)
			castBar.text:SetText("Failed")
			castBar.border:SetVertexColor(0.5, 0.5, 0.5) -- Gray border for failed
			if castBar.iconBorder then
				castBar.iconBorder:SetVertexColor(0.5, 0.5, 0.5) -- Gray icon border
			end
		end
		castBar:SetValue(1)
		castBar:SetAlpha(1)
		castBar:Show()
		castBar.state = CASTBAR_STATE.FINISHED
		castBar.holdUntil = GetTime() + 0.5
	end
end

local function AdjustCastTiming(unit, isChannel)
	local castBar = castBarsByUnit[unit]
	if not castBar then
		return
	end

	local info = isChannel and { UnitChannelInfo(unit) } or { UnitCastingInfo(unit) }
	if not info[1] then
		return
	end

	castBar.startTime = (info[5] or 0) / 1000
	castBar.endTime = (info[6] or 0) / 1000

	if not isChannel then
		castBar.notInterruptible = info[9] or false
	else
		castBar.notInterruptible = info[8] or false
	end
end

local function HideCastBar(unit)
	local castBar = castBarsByUnit[unit]
	if not castBar then
		return
	end

	castBar.state = CASTBAR_STATE.HIDDEN
	castBar:SetAlpha(1)
	castBar:SetValue(0)
	castBar:Hide()
	castBar.text:SetText("")
	castBar.time:SetText("")
	castBar.icon:SetTexture(nil)
	castBar.border:SetVertexColor(1, 1, 1) -- Reset border to white
	if castBar.iconBorder then
		castBar.iconBorder:Hide()
		castBar.iconBorder:SetVertexColor(1, 1, 1) -- Reset icon border to white
	end
	castBar.notInterruptible = false
end

local function RefreshCastBar(unit)
	if UnitCastingInfo(unit) then
		BeginCast(unit, false)
	elseif UnitChannelInfo(unit) then
		BeginCast(unit, true)
	else
		HideCastBar(unit)
	end
end

-------------------------------------------------------------------------------
-- TARGET FRAME CREATION
-------------------------------------------------------------------------------

local function CreateTargetFrame()
	local frame = CreateUnitFrame({
		name = "UFI_TargetFrame",
		unit = "target",
		mirrored = false,
	})

	ApplyUnitFrameProfileDefaults(frame, {
		power = { hideTextWhenNoPower = true },
		level = { colorByPlayerDiff = true },
	})

	frame.deadText = AttachStatusIndicator(frame, {
		trackDead = true,
		trackGhost = true,
		labels = { dead = "Dead", ghost = "Ghost" },
		hideHealthTextOnStatus = true,
	})

	frame.eliteTexture = AttachClassificationOverlay(frame, {
		texture = FRAME_TEXTURES.default,
		textures = BOSS_CLASSIFICATION_TEXTURES,
	})
	frame.castBar = CreateCastBar(frame, "target", frame.mirrored)
	if frame.ufProfile then frame.ufProfile.classificationTextures = BOSS_CLASSIFICATION_TEXTURES end

	-- New dedicated combo points text (independent of level text)
	local cpX, cpY, cpW, cpH = LayoutResolveRect(UFI_LAYOUT.ComboPointsText, frame.mirrored)
	frame.comboPointsText = CreateFontString(frame.visualLayer, {
		point = "TOPLEFT",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = cpX,
		y = -cpY,
		size = 20,
		flags = "OUTLINE",
		color = { r = 1, g = 1, b = 0 },
		drawLayer = 7,
	})
	frame.comboPointsText:SetSize(cpW, cpH)
	frame.comboPointsText:SetJustifyH("CENTER")
	frame.comboPointsText:SetJustifyV("MIDDLE")
	frame.comboPointsText:Hide()

	frame.comboPoints = nil
	frame.comboPointHighlight = nil

	AttachAuraContainers(frame, {
		buffs = { count = 5, position = "below", order = 1 },
		debuffs = { count = 5, position = "below", order = 2 },
	})

	local targetDropdown = CreateUnitInteractionDropdown("target", "UFI_TargetFrameDropDown", {
		fallbackTitle = TARGET or "Target",
	})

	local playerDropdown = UFI_PlayerFrameDropDown

	SecureUnitButton_OnLoad(frame, "target", function(self, unit, button)
		if UnitIsUnit("target", "player") then
			ToggleDropDownMenu(1, nil, playerDropdown, self, 110, 45)
		else
			ToggleDropDownMenu(1, nil, targetDropdown, self, 110, 45)
		end
	end)

	RegisterStateDriver(frame, "visibility", "[exists] show; hide")

	return frame
end

-------------------------------------------------------------------------------
-- FOCUS FRAME CREATION
-------------------------------------------------------------------------------

local function CreateFocusFrame()
	local frame = CreateUnitFrame({
		name = "UFI_FocusFrame",
		unit = "focus",
		mirrored = false,
	})

	ApplyUnitFrameProfileDefaults(frame, {
		power = { hideTextWhenNoPower = true },
		level = { colorByPlayerDiff = true },
	})

	frame.deadText = AttachStatusIndicator(frame, {
		trackDead = true,
		trackGhost = true,
		trackDisconnected = true,
		zeroHealthWhenStatus = true,
		labels = { dead = "Dead", ghost = "Ghost", disconnected = "Offline" },
		hideHealthTextOnStatus = true,
	})

	frame.eliteTexture = AttachClassificationOverlay(frame, {
		texture = FRAME_TEXTURES.default,
		textures = BOSS_CLASSIFICATION_TEXTURES,
	})
	frame.castBar = CreateCastBar(frame, "focus", frame.mirrored)

	AttachAuraContainers(frame, {
		buffs = { count = 5, position = "below", order = 1 },
		debuffs = { count = 5, position = "below", order = 2 },
	})

	local focusDropdown = CreateUnitInteractionDropdown("focus", "UFI_FocusFrameDropDown", {
		fallbackTitle = FOCUS or "Focus",
	})

	SecureUnitButton_OnLoad(frame, "focus", function(self, unit, button)
		ToggleDropDownMenu(1, nil, focusDropdown, self, 110, 45)
	end)

	RegisterStateDriver(frame, "visibility", "[target=focus,exists,nodead] show; hide")

	return frame
end

-------------------------------------------------------------------------------
-- TARGET OF TARGET FRAME CREATION
-------------------------------------------------------------------------------

local function CreateTargetOfTargetFrame()
	local anchorFrame = UFI_TargetFrame or UIParent
	local baseLevel = math.max((anchorFrame and anchorFrame:GetFrameLevel() or 0) + 15, 15)

	local frame = CreateUnitFrame({
		name = "UFI_TargetOfTargetFrame",
		unit = "targettarget",
		mirrored = true,
		frameLevel = baseLevel,
		frameStrata = "LOW",
		textStyles = {
			name = { y = 6, size = 20, flags = "OUTLINE", drawLayer = 7 },
			health = false,
			power = false,
		},
	})

	frame:SetFrameLevel(baseLevel)
	frame.visualLayer:SetFrameLevel(baseLevel)

	frame:SetAttribute("unit", "targettarget")
	frame:SetAttribute("type1", "target")

	ApplyUnitFrameProfileDefaults(frame, {
		power = { hideTextWhenNoPower = true },
		level = { colorByPlayerDiff = true },
	})

	frame:Hide()

	return frame
end

-- BOSS FRAME CREATION

local UpdateUnitFrameHealth
local UpdateUnitFramePower
local UpdateUnitFramePortrait
local UpdateUnitFrameName
local UpdateUnitFrameLevel

local function ClearBossFrame(frame)
	if not frame then
		return
	end

	frame.nameText:SetText("")
	frame.levelText:SetText("")
	frame.healthText:SetText("")
	frame.powerText:SetText("")
	frame.healthBar:SetMinMaxValues(0, 1)
	frame.healthBar:SetValue(0)
	frame.powerBar:SetMinMaxValues(0, 1)
	frame.powerBar:SetValue(0)
	frame.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame.portrait:SetTexture(nil)

	if frame.castBar then
		frame.castBar:Hide()
		frame.castBar:SetAlpha(1)
		frame.castBar:SetValue(0)
		frame.castBar.text:SetText("")
		frame.castBar.time:SetText("")
		frame.castBar.icon:SetTexture(nil)
		frame.castBar.state = CASTBAR_STATE.HIDDEN
		frame.castBar.holdUntil = 0
	end

	frame.currentTexture = nil
end

local function UpdateBossFrame(unit)
	if not unit then
		return
	end

	if not UnitExists(unit) then
		ClearBossUnitFrame(unit)
		return
	end

	UpdateBossHealth(unit)
	UpdateBossPower(unit)
	UpdateBossPortrait(unit)
	UpdateBossName(unit)
	UpdateBossLevel(unit)
	UpdateBossClassification(unit)
end

local function UpdateAllBossFrames()
	for index = 1, MAX_BOSS_FRAMES do
		local unit = "boss" .. index
		UpdateBossFrame(unit)
	end
end

local function CreateBossFrames()
	local anchor = CreateFrame("Frame", "UFI_BossFrameAnchor", UIParent)
	anchor:SetSize(UFI_LAYOUT.Art.width, (BOSS_FRAME_STRIDE * MAX_BOSS_FRAMES))
	anchor:SetFrameStrata("LOW")
	anchor.frames = {}
	UFI_BossFrameAnchor = anchor
	InitializeFramePosition("UFI_BossFrameAnchor", anchor)

	for index = 1, MAX_BOSS_FRAMES do
		local unit = "boss" .. index
		local frame = CreateUnitFrame({
			name = "UFI_BossFrame" .. index,
			unit = unit,
			parent = anchor,
			mirrored = false,
			frameLevel = (anchor:GetFrameLevel() or 0) + index,
			frameStrata = "LOW",
			initializePosition = false,
		})
		frame.unit = unit
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -((index - 1) * BOSS_FRAME_STRIDE))

		frame:SetAttribute("unit", unit)
		frame:SetAttribute("type1", "target")
		RegisterUnitWatch(frame)
		frame:Hide()

		frame.castBar = CreateCastBar(frame, unit, frame.mirrored)
		frame.currentTexture = FRAME_TEXTURES.default
		ApplyUnitFrameProfileDefaults(frame, {
			power = { hideTextWhenNoPower = true },
			level = { colorByPlayerDiff = true },
		})

		frame:SetScript("OnShow", function(self)
			if self.unit and UnitExists(self.unit) then
				UpdateBossFrame(self.unit)
			else
				ClearBossFrame(self)
			end
		end)

		frame:SetScript("OnHide", function(self)
			ClearBossFrame(self)
		end)

		ClearBossFrame(frame)

		bossFrames[index] = frame
		bossFramesByUnit[unit] = frame
		anchor.frames[index] = frame
	end

	return anchor
end

-------------------------------------------------------------------------------
-- PLAYER FRAME UPDATE FUNCTIONS
-------------------------------------------------------------------------------

local function GetFrameProfile(frame)
	return frame and frame.ufProfile
end

local function ResolveProfileUnit(frame, profile)
	profile = profile or GetFrameProfile(frame)
	if not profile then
		return nil
	end

	local unit = profile.unit
	if type(unit) == "function" then
		return unit(frame)
	end

	return unit
end

local function ApplyLevelColorByDiff(fontString, levelDiff)
	if not fontString then
		return
	end

	if levelDiff >= 5 then
		fontString:SetTextColor(1, 0, 0)
	elseif levelDiff >= 3 then
		fontString:SetTextColor(1, 0.5, 0)
	elseif levelDiff >= -2 then
		fontString:SetTextColor(1, 1, 0)
	elseif levelDiff >= -4 then
		fontString:SetTextColor(0, 1, 0)
	else
		fontString:SetTextColor(0.5, 0.5, 0.5)
	end
end

UpdateUnitFrameHealth = function(frame)
	if not frame or not frame.healthBar then
		return
	end

	local profile = GetFrameProfile(frame)
	if not profile then
		return
	end

	local unit = ResolveProfileUnit(frame, profile)
	if not unit then
		return
	end

	if not UnitExists(unit) then
		local statusConfig = profile.status
		if statusConfig and statusConfig.labelFontString then
			statusConfig.labelFontString:Hide()
		end
		if frame.healthText then
			frame.healthText:SetText("")
		end
		return
	end

	local health = UnitHealth(unit)
	local maxHealth = UnitHealthMax(unit)
	if maxHealth == 0 then
		maxHealth = 1
	end

	local statusConfig = profile.status
	local statusKey
	if statusConfig then
		if statusConfig.trackDisconnected and not UnitIsConnected(unit) then
			statusKey = "disconnected"
		elseif statusConfig.trackDead and UnitIsDead(unit) then
			statusKey = "dead"
		elseif statusConfig.trackGhost and UnitIsGhost(unit) then
			statusKey = "ghost"
		end

		if statusKey and statusConfig.zeroHealthWhenStatus then
			health = 0
		end
	end

	frame.healthBar:SetMinMaxValues(0, maxHealth)
	frame.healthBar:SetValue(health)

	local r, g, b = GetUnitColor(unit)
	frame.healthBar:SetStatusBarColor(r, g, b)
	if frame.nameText then
		frame.nameText:SetTextColor(NAME_TEXT_COLOR_R, NAME_TEXT_COLOR_G, NAME_TEXT_COLOR_B)
	end

	if statusConfig and statusConfig.labelFontString then
		if statusKey then
			local labels = statusConfig.labels or {}
			statusConfig.labelFontString:SetText(labels[statusKey] or "")
			statusConfig.labelFontString:Show()
			if frame.healthText and statusConfig.hideHealthTextOnStatus then
				frame.healthText:Hide()
			end
		else
			statusConfig.labelFontString:Hide()
			if frame.healthText then
				frame.healthText:Show()
				frame.healthText:SetText(FormatStatusText(health, maxHealth))
			end
		end
	elseif frame.healthText then
		frame.healthText:SetText(FormatStatusText(health, maxHealth))
	end

	if profile.customHealthUpdate then
		profile.customHealthUpdate(frame, unit, health, maxHealth, statusKey)
	end
end

UpdateUnitFramePower = function(frame)
	if not frame or not frame.powerBar then
		return
	end

	local profile = GetFrameProfile(frame)
	if not profile then
		return
	end

	local unit = ResolveProfileUnit(frame, profile)
	if not unit then
		return
	end

	if not UnitExists(unit) then
		if frame.powerText then
			frame.powerText:SetText("")
		end
		return
	end

	local power = UnitPower(unit)
	local maxPower = UnitPowerMax(unit)
	local powerConfig = profile.power or {}

	if maxPower == 0 then
		frame.powerBar:SetMinMaxValues(0, 1)
		frame.powerBar:SetValue(0)
		frame.powerBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 0)
		if frame.powerText then
			frame.powerText:SetText("")
			if powerConfig.hideTextWhenNoPower then
				frame.powerText:Hide()
			else
				frame.powerText:Show()
			end
		end
		if powerConfig.hideBarWhenNoPower then
			frame.powerBar:Hide()
		else
			frame.powerBar:Show()
		end
		if profile.customPowerUpdate then
			profile.customPowerUpdate(frame, unit, power, maxPower, true)
		end
		return
	end

	frame.powerBar:Show()
	frame.powerBar:SetMinMaxValues(0, maxPower)
	frame.powerBar:SetValue(power)
	frame.powerBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 0)

	local powerType = UnitPowerType(unit)
	local info = PowerBarColor[powerType]
	if info then
		frame.powerBar:SetStatusBarColor(info.r, info.g, info.b)
	end

	if frame.powerText then
		frame.powerText:Show()
		frame.powerText:SetText(FormatStatusText(power, maxPower))
	end

	if profile.customPowerUpdate then
		profile.customPowerUpdate(frame, unit, power, maxPower, false)
	end
end

UpdateUnitFrameName = function(frame)
	if not frame or not frame.nameText then
		return
	end

	local unit = ResolveProfileUnit(frame)
	if not unit or not UnitExists(unit) then
		frame.nameText:SetText("")
		return
	end

	-- Truncate name to fit health bar width (with 20px padding)
	local maxWidth = frame.healthBar:GetWidth() - 20
	local truncatedName = TruncateNameToFit(frame.nameText, UnitName(unit) or "", maxWidth)
	frame.nameText:SetText(truncatedName)

	local profile = GetFrameProfile(frame)
	if profile and profile.customNameUpdate then
		profile.customNameUpdate(frame, unit)
	end
end

UpdateUnitFramePortrait = function(frame)
	if not frame or not frame.portrait then
		return
	end

	local unit = ResolveProfileUnit(frame)
	if not unit or not UnitExists(unit) then
		return
	end

	SetPortraitTexture(frame.portrait, unit)
end

UpdateUnitFrameLevel = function(frame)
	if not frame or not frame.levelText then
		return
	end

	local profile = GetFrameProfile(frame)
	if not profile then
		return
	end

	if profile.customLevelUpdate then
		profile.customLevelUpdate(frame)
		return
	end

	local unit = ResolveProfileUnit(frame, profile)
	if not unit or not UnitExists(unit) then
		frame.levelText:SetText("")
		return
	end

	local level = UnitLevel(unit)
	if level == -1 then
		frame.levelText:SetText("??")
		frame.levelText:SetTextColor(1, 0, 0)
		return
	end

	frame.levelText:SetText(level)

	local levelConfig = profile.level
	if levelConfig and levelConfig.colorByPlayerDiff then
		local referenceUnit = levelConfig.referenceUnit or "player"
		local referenceLevel = UnitLevel(referenceUnit) or 0
		ApplyLevelColorByDiff(frame.levelText, level - referenceLevel)
	else
		frame.levelText:SetTextColor(1, 0.82, 0)
	end
end

local function ApplyBossClassification(frame, unit)
	ApplyBossTexture(frame, UnitClassification(unit))
end

ClearBossUnitFrame = MakeUnitFrameUpdater(GetBossFrame, ClearBossFrame)
UpdateBossHealth = MakeUnitFrameUpdater(GetBossFrame, UpdateUnitFrameHealth)
UpdateBossPower = MakeUnitFrameUpdater(GetBossFrame, UpdateUnitFramePower)
UpdateBossPortrait = MakeUnitFrameUpdater(GetBossFrame, UpdateUnitFramePortrait)
UpdateBossName = MakeUnitFrameUpdater(GetBossFrame, UpdateUnitFrameName)
UpdateBossLevel = MakeUnitFrameUpdater(GetBossFrame, UpdateUnitFrameLevel)
UpdateBossClassification = MakeUnitFrameUpdater(GetBossFrame, ApplyBossClassification)

local function UpdateClassificationOverlay(frame)
	local profile = GetFrameProfile(frame)
	if not frame or not profile or not profile.classificationTexture then
		return
	end

	local unit = ResolveProfileUnit(frame, profile)
	if not unit or not UnitExists(unit) then
		profile.classificationTexture:Hide()
		return
	end

	local mapping = profile.classificationTextures or BOSS_CLASSIFICATION_TEXTURES
	local texturePath = mapping[UnitClassification(unit)]

	if texturePath then
		profile.classificationTexture:SetTexture(texturePath)
		profile.classificationTexture:Show()
	else
		profile.classificationTexture:Hide()
	end
end

local function ApplyPlayerTextureColor(color)
	if not UFI_PlayerFrame or not color then
		return
	end

	if UFI_PlayerFrame.currentVertexColor == color then
		return
	end

	if UFI_PlayerFrame.texture then
		UFI_PlayerFrame.texture:SetVertexColor(color.r, color.g, color.b)
	end

	if UFI_PlayerFrame.portraitMask then
		UFI_PlayerFrame.portraitMask:SetVertexColor(color.r, color.g, color.b)
	end

	UFI_PlayerFrame.currentVertexColor = color
end

local function UpdatePlayerThreat()
	local threatStatus = UnitThreatSituation("player")

	if threatStatus and threatStatus >= 2 then
		ApplyPlayerTextureColor(PLAYER_TEXTURE_COLORS.threat)
	else
		ApplyPlayerTextureColor(PLAYER_TEXTURE_COLORS.normal)
	end
end

local UpdatePlayerHealth = MakeUnitFrameUpdater(GetPlayerFrame, UpdateUnitFrameHealth)
local UpdatePlayerPower = MakeUnitFrameUpdater(GetPlayerFrame, UpdateUnitFramePower)
local UpdatePlayerPortrait = MakeUnitFrameUpdater(GetPlayerFrame, UpdateUnitFramePortrait)
local UpdatePlayerName = MakeUnitFrameUpdater(GetPlayerFrame, UpdateUnitFrameName)

UpdatePlayerLevel = function(frame)
	frame = frame or UFI_PlayerFrame
	if not frame then
		return
	end

	local level = UnitLevel("player")
	local inCombat = UnitAffectingCombat("player")

	if inCombat then
		frame.levelText:SetText(level)
		frame.levelText:SetTextColor(1, 0.25, 0.25)
	elseif IsResting() then
		frame.levelText:SetText("zzz")
		frame.levelText:SetTextColor(1, 0.82, 0)
	else
		frame.levelText:SetText(level)
		frame.levelText:SetTextColor(1, 0.82, 0)
	end
end

-------------------------------------------------------------------------------
-- TARGET FRAME UPDATE FUNCTIONS
-------------------------------------------------------------------------------

local UpdateTargetHealth = MakeUnitFrameUpdater(GetTargetFrame, UpdateUnitFrameHealth)
local UpdateTargetPower = MakeUnitFrameUpdater(GetTargetFrame, UpdateUnitFramePower)
local UpdateTargetPortrait = MakeUnitFrameUpdater(GetTargetFrame, UpdateUnitFramePortrait)
local UpdateTargetName = MakeUnitFrameUpdater(GetTargetFrame, UpdateUnitFrameName)
local UpdateTargetLevel = MakeUnitFrameUpdater(GetTargetFrame, UpdateUnitFrameLevel)
function UpdateTargetClassification(frame)
	frame = frame or UFI_TargetFrame
	if not frame then return end
	local profile = GetFrameProfile(frame)
	if not profile then return end
	local unit = profile.unit or "target"
	if not UnitExists(unit) then return end
	local classification = UnitClassification(unit) or "normal"
	local _, playerClass = UnitClass("player")
	local form = GetShapeshiftForm() or 0
	local useRogue = (playerClass == "ROGUE") or (playerClass == "DRUID" and form == 3)
	local function ResolveBasePath(isRogueVariant, classKey)
		classKey = string.lower(classKey or "normal")
		if classKey == "worldboss" then classKey = "elite" end
		local baseMap = isRogueVariant and ROGUE_FRAME_TEXTURES or FRAME_TEXTURES
		if classKey == "rareelite" then
			return baseMap.rareElite
		end
		return baseMap[classKey] or baseMap.default
	end
	local path = ResolveBasePath(useRogue, classification)
	if path and path ~= "" then
		if frame.texture and frame.texture:GetTexture() ~= path then
			frame.texture:SetTexture(path)
		end
		if frame.portraitMask and frame.portraitMask:GetTexture() ~= path then
			frame.portraitMask:SetTexture(path)
		end
	end
	-- Ensure classification overlay uses matching rogue/non-rogue mapping
	local _, playerClass2 = UnitClass("player")
	local form2 = GetShapeshiftForm() or 0
	local rogueVariant = (playerClass2 == "ROGUE") or (playerClass2 == "DRUID" and form2 == 3)
	if profile then
		profile.classificationTextures = rogueVariant and ROGUE_BOSS_CLASSIFICATION_TEXTURES or
		BOSS_CLASSIFICATION_TEXTURES
	end
	UpdateClassificationOverlay(frame)
	UpdateTargetPortrait()
end

-- Update combo points display on target frame
function UpdateTargetComboPoints()
	local frame = UFI_TargetFrame
	if not frame or not UnitExists("target") then
		return
	end
	local cpText = frame.comboPointsText
	if not cpText then
		return
	end
	local _, playerClass = UnitClass("player")
	local form = GetShapeshiftForm() or 0
	local isDruidCat = (playerClass == "DRUID" and form == 3)
	local isRogue = (playerClass == "ROGUE")
	local eligible = isRogue or isDruidCat
	local points = GetComboPoints("player", "target") or GetComboPoints() or 0
	if eligible then
		local r, g, b
		if UFI_PlayerFrame and UFI_PlayerFrame.powerBar then
			r, g, b = UFI_PlayerFrame.powerBar:GetStatusBarColor()
		end
		if not r then r, g, b = 1, 1, 0 end
		if points and points > 0 then
			cpText:SetText(points)
		else
			cpText:SetText(0)
		end
		cpText:SetTextColor(r, g, b)
		cpText:Show()
	else
		cpText:Hide()
	end
end

-------------------------------------------------------------------------------
-- TARGET OF TARGET FRAME UPDATE FUNCTIONS
-------------------------------------------------------------------------------

local targetOfTargetVisibilityDriver = nil
local targetOfTargetDriverActive = false
local pendingTargetOfTargetDriver = nil
local pendingTargetOfTargetDriverActivation = false

-- When combat lockdown is active we cannot touch the frame's state driver, so we
-- mimic the visibility change with alpha/mouse toggles and remember the desired state.
local function ApplyTargetOfTargetCombatFallback(frame, wantsDriver)
	if not frame then
		return
	end

	local fallback = frame.ufCombatFallback

	if InCombatLockdown() then
		if not fallback then
			fallback = {
				alpha = frame:GetAlpha() or 1,
				mouseEnabled = frame:IsMouseEnabled(),
			}
			frame.ufCombatFallback = fallback
		end
		fallback.wantsDriver = wantsDriver
		if not wantsDriver then
			frame:SetAlpha(0)
		else
			frame:SetAlpha(fallback.alpha or 1)
		end
		return
	end

	if wantsDriver then
		if fallback then
			frame:SetAlpha(fallback.alpha or 1)
			local mouseEnabled = fallback.mouseEnabled
			if mouseEnabled == nil then
				mouseEnabled = true
			end
			frame:EnableMouse(mouseEnabled)
			frame.ufCombatFallback = nil
		else
			frame:SetAlpha(1)
			frame:EnableMouse(true)
		end
	else
		if not fallback then
			frame.ufCombatFallback = {
				alpha = frame:GetAlpha() or 1,
				mouseEnabled = frame:IsMouseEnabled(),
			}
		end
		frame:SetAlpha(0)
		frame:EnableMouse(false)
	end
end

local function DriverWantsTargetOfTargetShown(driver)
	return type(driver) == "string" and driver ~= "hide"
end

-- Construct the visibility macro string that mimics Blizzard's settings dialog so
-- RegisterStateDriver stays in lock-step with the user's preferred target-of-target mode.
local function BuildTargetOfTargetVisibilityDriver()
	if not GetCVarBool("showTargetOfTarget") then
		return "hide"
	end

	local mode = tonumber(GetCVar("targetOfTargetMode") or "0") or 0
	local baseCondition = "[target=targettarget,exists"

	if mode == 1 then  -- raid only
		return baseCondition .. ",group:raid] show; hide"
	elseif mode == 2 then -- party only
		return baseCondition .. ",group:party] show; hide"
	elseif mode == 3 then -- solo only
		return "[target=targettarget,exists,group:raid] hide; [target=targettarget,exists,group:party] hide; "
			.. baseCondition
			.. "] show; hide"
	elseif mode == 4 then -- raid & party
		return baseCondition .. ",group:raid] show; [target=targettarget,exists,group:party] show; hide"
	end

	return baseCondition .. "] show; hide"
end

local function ApplyTargetOfTargetVisibilityDriver()
	local driver = BuildTargetOfTargetVisibilityDriver()
	local wantsDriver = DriverWantsTargetOfTargetShown(driver)
	local frame = UFI_TargetOfTargetFrame

	local driverChanged = driver ~= targetOfTargetVisibilityDriver
	local activationChanged = wantsDriver ~= targetOfTargetDriverActive

	if not frame then
		if driverChanged or activationChanged then
			pendingTargetOfTargetDriver = driver
			pendingTargetOfTargetDriverActivation = wantsDriver
		end
		return
	end

	if not driverChanged and not activationChanged then
		if frame.ufCombatFallback then
			ApplyTargetOfTargetCombatFallback(frame, wantsDriver)
		end
		pendingTargetOfTargetDriver = nil
		pendingTargetOfTargetDriverActivation = false
		return
	end

	if InCombatLockdown() then
		pendingTargetOfTargetDriver = driver
		pendingTargetOfTargetDriverActivation = wantsDriver
		ApplyTargetOfTargetCombatFallback(frame, wantsDriver)
		return
	end

	if frame.ufCombatFallback then
		local previousAlpha = frame.ufCombatFallback.alpha
		frame:SetAlpha(previousAlpha or 1)
		frame.ufCombatFallback = nil
	end

	if targetOfTargetDriverActive then
		UnregisterStateDriver(frame, "visibility")
		targetOfTargetDriverActive = false
	end

	if wantsDriver then
		frame:EnableMouse(true)
		frame:SetAlpha(1)
		RegisterStateDriver(frame, "visibility", driver)
		targetOfTargetDriverActive = true
	else
		frame:EnableMouse(false)
		frame:SetAlpha(1)
		frame:Hide()
		targetOfTargetDriverActive = false
	end

	targetOfTargetVisibilityDriver = driver
	pendingTargetOfTargetDriver = nil
	pendingTargetOfTargetDriverActivation = false
end

-- Ensure our manual refreshes respect both the secure driver state and Blizzard heuristics.
local function ShouldShowTargetOfTarget()
	local frame = UFI_TargetOfTargetFrame

	if frame and frame.ufCombatFallback and not pendingTargetOfTargetDriverActivation then
		return false
	end

	if pendingTargetOfTargetDriverActivation then
		return true
	end

	if not DriverWantsTargetOfTargetShown(targetOfTargetVisibilityDriver) then
		return false
	end

	if not targetOfTargetDriverActive then
		return false
	end

	if TargetFrame_ShouldShowTargetOfTarget and TargetFrame then
		local ok, result = pcall(TargetFrame_ShouldShowTargetOfTarget, TargetFrame)
		if ok then
			return result
		end
	end

	return true
end

local UpdateTargetOfTargetHealth = MakeUnitFrameUpdater(GetTargetOfTargetFrame, UpdateUnitFrameHealth)
local UpdateTargetOfTargetPower = MakeUnitFrameUpdater(GetTargetOfTargetFrame, UpdateUnitFramePower)
local UpdateTargetOfTargetPortrait = MakeUnitFrameUpdater(GetTargetOfTargetFrame, UpdateUnitFramePortrait)
local UpdateTargetOfTargetName = MakeUnitFrameUpdater(GetTargetOfTargetFrame, UpdateUnitFrameName)
local UpdateTargetOfTargetLevel = MakeUnitFrameUpdater(GetTargetOfTargetFrame, UpdateUnitFrameLevel)

local function UpdateTargetOfTarget()
	if not GetTargetOfTargetFrame() then
		return
	end

	if not ShouldShowTargetOfTarget() then
		return
	end

	UpdateTargetOfTargetHealth()
	UpdateTargetOfTargetPower()
	UpdateTargetOfTargetPortrait()
	UpdateTargetOfTargetName()
	UpdateTargetOfTargetLevel()
end

-------------------------------------------------------------------------------
-- FOCUS FRAME UPDATE FUNCTIONS
-------------------------------------------------------------------------------
local UpdateFocusHealth = MakeUnitFrameUpdater(GetFocusFrame, UpdateUnitFrameHealth)
local UpdateFocusPower = MakeUnitFrameUpdater(GetFocusFrame, UpdateUnitFramePower)
local UpdateFocusPortrait = MakeUnitFrameUpdater(GetFocusFrame, UpdateUnitFramePortrait)
local UpdateFocusName = MakeUnitFrameUpdater(GetFocusFrame, UpdateUnitFrameName)
local UpdateFocusLevel = MakeUnitFrameUpdater(GetFocusFrame, UpdateUnitFrameLevel)
local UpdateFocusClassification = MakeUnitFrameUpdater(GetFocusFrame, UpdateClassificationOverlay)

local function HideAuraRows(frame)
	if not frame then
		return
	end

	if frame.buffs then
		for i = 1, #frame.buffs do
			local iconFrame = frame.buffs[i]
			if iconFrame.cooldown then
				iconFrame.cooldown:Hide()
			end
			if iconFrame.count then
				iconFrame.count:Hide()
			end
			iconFrame:Hide()
		end
	end

	if frame.debuffs then
		for i = 1, #frame.debuffs do
			local iconFrame = frame.debuffs[i]
			if iconFrame.cooldown then
				iconFrame.cooldown:Hide()
			end
			if iconFrame.count then
				iconFrame.count:Hide()
			end
			iconFrame:Hide()
		end
	end
end

local function UpdateUnitAuras(unit, frame, filterDebuffs)
	if not frame then
		return
	end

	if not UnitExists(unit) then
		HideAuraRows(frame)
		PositionAuraRow(frame.debuffs, frame, frame.mirrored, "below", 1)
		return
	end

	local buffsShown = 0
	local buffFrames = frame.buffs
	if buffFrames and #buffFrames > 0 then
		local maxBuffs = #buffFrames
		for index = 1, maxBuffs do
			local iconFrame = buffFrames[index]
			if iconFrame.cooldown then
				iconFrame.cooldown:Hide()
			end
			if iconFrame.count then
				iconFrame.count:Hide()
			end
			iconFrame:Hide()
		end

		for auraIndex = 1, 40 do
			local name, _, icon, count, _, duration, expirationTime = UnitBuff(unit, auraIndex)
			if not name then
				break
			end

			buffsShown = buffsShown + 1
			if buffsShown > maxBuffs then
				buffsShown = maxBuffs
				break
			end

			local iconFrame = buffFrames[buffsShown]
			iconFrame.icon:SetTexture(icon)
			if duration and duration > 0 and expirationTime then
				iconFrame.cooldown:SetCooldown(expirationTime - duration, duration)
				iconFrame.cooldown:Show()
			else
				iconFrame.cooldown:Hide()
			end
			if count and count > 1 then
				iconFrame.count:SetText(count)
				iconFrame.count:Show()
			else
				iconFrame.count:Hide()
			end
			iconFrame:Show()
		end
	end

	local debuffFrames = frame.debuffs
	local debuffsShown = 0
	if debuffFrames and #debuffFrames > 0 then
		local maxDebuffs = #debuffFrames
		for index = 1, maxDebuffs do
			local iconFrame = debuffFrames[index]
			if iconFrame.cooldown then
				iconFrame.cooldown:Hide()
			end
			if iconFrame.count then
				iconFrame.count:Hide()
			end
			iconFrame:Hide()
		end

		for auraIndex = 1, 40 do
			local name, _, icon, count, debuffType, duration, expirationTime, caster = UnitDebuff(unit, auraIndex)
			if not name then
				break
			end

			if not filterDebuffs or (caster == "player" or caster == "pet" or caster == "vehicle") then
				debuffsShown = debuffsShown + 1
				if debuffsShown > maxDebuffs then
					debuffsShown = maxDebuffs
					break
				end

				local iconFrame = debuffFrames[debuffsShown]
				iconFrame.icon:SetTexture(icon)
				local color = DebuffTypeColor[debuffType or "none"] or DebuffTypeColor["none"]
				iconFrame.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
				iconFrame.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
				iconFrame.border:SetVertexColor(color[1], color[2], color[3])

				if duration and duration > 0 and expirationTime then
					iconFrame.cooldown:SetCooldown(expirationTime - duration, duration)
					iconFrame.cooldown:Show()
				else
					iconFrame.cooldown:Hide()
				end
				if count and count > 1 then
					iconFrame.count:SetText(count)
					iconFrame.count:Show()
				else
					iconFrame.count:Hide()
				end
				iconFrame:Show()
			end
		end

		for index = debuffsShown + 1, maxDebuffs do
			local iconFrame = debuffFrames[index]
			iconFrame.cooldown:Hide()
			iconFrame.count:Hide()
			iconFrame:Hide()
		end
	end

	local desiredOrder = buffsShown > 0 and 2 or 1
	if frame.debuffs and frame.debuffs.currentOrder ~= desiredOrder then
		PositionAuraRow(frame.debuffs, frame, frame.mirrored, "below", desiredOrder)
	end
end

local UpdateFocusAuras = MakeUnitFrameUpdater(GetFocusFrame, function(frame)
	UpdateUnitAuras("focus", frame)
end)

local function UpdatePlayerAuras()
	if not UFI_PlayerFrame or not UFI_PlayerFrame.selfBuffs then
		return
	end

	local icons = UFI_PlayerFrame.selfBuffs
	local iconCount = #icons
	local shown = 0

	for index = 1, iconCount do
		local iconFrame = icons[index]
		iconFrame.cooldown:Hide()
		iconFrame.count:Hide()
		iconFrame:Hide()
	end

	for auraIndex = 1, 40 do
		local name, _, icon, count, _, duration, expirationTime, caster, _, _, spellId = UnitBuff("player", auraIndex)
		if not name then
			break
		end

		if
			(caster == "player" or caster == "pet" or caster == "vehicle")
			and not (spellId and SELF_BUFF_EXCLUSIONS[spellId])
		then
			shown = shown + 1
			if shown > iconCount then
				shown = iconCount
				break
			end

			local iconFrame = icons[shown]
			iconFrame.icon:SetTexture(icon)
			if duration and duration > 0 and expirationTime then
				iconFrame.cooldown:SetCooldown(expirationTime - duration, duration)
				iconFrame.cooldown:Show()
			else
				iconFrame.cooldown:Hide()
			end
			if count and count > 1 then
				iconFrame.count:SetText(count)
				iconFrame.count:Show()
			else
				iconFrame.count:Hide()
			end

			iconFrame.border:SetVertexColor(1, 1, 1)
			iconFrame:Show()
		end
	end

	for index = shown + 1, iconCount do
		local iconFrame = icons[index]
		iconFrame.cooldown:Hide()
		iconFrame.count:Hide()
		iconFrame:Hide()
	end
end

local function UpdateFocusFrame()
	if not GetFocusFrame() then
		return
	end

	if not UnitExists("focus") then
		return
	end

	UpdateFocusHealth()
	UpdateFocusPower()
	UpdateFocusPortrait()
	UpdateFocusName()
	UpdateFocusLevel()
	UpdateFocusClassification()
	UpdateFocusAuras()
end

-------------------------------------------------------------------------------
-- TARGET FRAME AURAS
-------------------------------------------------------------------------------

-- Debuff type colors
local DebuffTypeColor = {
	["Magic"] = { 0.2, 0.6, 1.0 },
	["Curse"] = { 0.6, 0.0, 1.0 },
	["Disease"] = { 0.6, 0.4, 0 },
	["Poison"] = { 0.0, 0.6, 0 },
	["none"] = { 0.8, 0, 0 },
}

local function UpdateTargetAuras()
	UpdateUnitAuras("target", UFI_TargetFrame, true)
end

-------------------------------------------------------------------------------
-- EVENT HANDLING
-------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("UNIT_MAXHEALTH")
eventFrame:RegisterEvent("UNIT_POWER_FREQUENT")
eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
eventFrame:RegisterEvent("UNIT_MANA")
eventFrame:RegisterEvent("UNIT_RAGE")
eventFrame:RegisterEvent("UNIT_ENERGY")
eventFrame:RegisterEvent("UNIT_FOCUS")
eventFrame:RegisterEvent("UNIT_RUNIC_POWER")
eventFrame:RegisterEvent("UNIT_MAXMANA")
eventFrame:RegisterEvent("UNIT_MAXRAGE")
eventFrame:RegisterEvent("UNIT_MAXENERGY")
eventFrame:RegisterEvent("UNIT_MAXFOCUS")
eventFrame:RegisterEvent("UNIT_MAXRUNIC_POWER")
eventFrame:RegisterEvent("UNIT_MAXPOWER")
eventFrame:RegisterEvent("UNIT_PORTRAIT_UPDATE")
eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
eventFrame:RegisterEvent("UNIT_LEVEL")
eventFrame:RegisterEvent("UNIT_CLASSIFICATION_CHANGED")
eventFrame:RegisterEvent("UNIT_COMBO_POINTS")
eventFrame:RegisterEvent("PLAYER_COMBO_POINTS")
eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterEvent("UNIT_TARGET")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("UNIT_SPELLCAST_START")
eventFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
eventFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_DELAYED")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
eventFrame:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
eventFrame:RegisterEvent("UNIT_TARGETABLE_CHANGED")
eventFrame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
eventFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")

local function HandlePlayerLogin()
	InitializeDatabase()

	UFI_PlayerFrame = CreatePlayerFrame()
	UFI_TargetFrame = CreateTargetFrame()
	UFI_FocusFrame = CreateFocusFrame()
	ApplyFocusFrameScale()
	UFI_TargetOfTargetFrame = CreateTargetOfTargetFrame()
	UFI_BossFrameAnchor = CreateBossFrames()

	ApplyTargetOfTargetVisibilityDriver()

	PlayerFrame:UnregisterAllEvents()
	-- Hide Blizzard's secure frames entirely so they do not fire events or taint our replacements.
	PlayerFrame:Hide()
	PlayerFrame:SetAlpha(0)

	TargetFrame:UnregisterAllEvents()
	TargetFrame:Hide()
	TargetFrame:SetAlpha(0)

	FocusFrame:UnregisterAllEvents()
	FocusFrame:Hide()
	FocusFrame:SetAlpha(0)

	for index = 1, MAX_BOSS_FRAMES do
		local defaultBossFrame = _G["Boss" .. index .. "TargetFrame"]
		if defaultBossFrame then
			defaultBossFrame:UnregisterAllEvents()
			defaultBossFrame:Hide()
			defaultBossFrame:SetAlpha(0)
		end
	end

	if BossTargetFrameContainer then
		BossTargetFrameContainer:UnregisterAllEvents()
		BossTargetFrameContainer:Hide()
		BossTargetFrameContainer:SetAlpha(0)
	end

	if TargetFrameToT then
		TargetFrameToT:UnregisterAllEvents()
		TargetFrameToT:Hide()
		TargetFrameToT:SetAlpha(0)
	end

	-- Hide Blizzard's combo point frame
	if ComboFrame then
		ComboFrame:UnregisterAllEvents()
		ComboFrame:Hide()
		ComboFrame:SetAlpha(0)
	end

	ApplyPosition("UFI_PlayerFrame")
	ApplyPosition("UFI_TargetFrame")
	ApplyPosition("UFI_TargetOfTargetFrame")
	ApplyPosition("UFI_FocusFrame")
	ApplyPosition("UFI_BossFrameAnchor")

	CreateOverlay(UFI_PlayerFrame, "UFI_PlayerFrame")
	CreateOverlay(UFI_TargetFrame, "UFI_TargetFrame")
	if UFI_TargetOfTargetFrame then
		CreateOverlay(UFI_TargetOfTargetFrame, "UFI_TargetOfTargetFrame")
	end
	CreateOverlay(UFI_FocusFrame, "UFI_FocusFrame")
	if UFI_BossFrameAnchor then
		CreateOverlay(UFI_BossFrameAnchor, "UFI_BossFrameAnchor")
	end

	-- Interface options still call the legacy SetCVar API, so hook it to react without polling.
	hooksecurefunc("SetCVar", function(name, value)
		if name == "statusTextPercentage" then
			UpdatePlayerHealth()
			UpdatePlayerPower()
			if UnitExists("target") then
				UpdateTargetHealth()
				UpdateTargetPower()
			end
			if UnitExists("focus") then
				UpdateFocusHealth()
				UpdateFocusPower()
			end
			UpdateAllBossFrames()
		elseif name == "showTargetOfTarget" or name == "targetOfTargetMode" then
			ApplyTargetOfTargetVisibilityDriver()
			UpdateTargetOfTarget()
		elseif name == "fullSizeFocusFrame" then
			ApplyFocusFrameScale()
		end
	end)

	if UnitFramesImprovedDB.isUnlocked and not InCombatLockdown() then
		UnlockFrames()
	end

	Print("|cff00ff00UnitFramesImproved v" .. ADDON_VERSION .. " loaded!|r Type |cffffcc00/ufi help|r for commands.")

	UpdatePlayerHealth()
	UpdatePlayerPower()
	UpdatePlayerPortrait()
	UpdatePlayerName()
	UpdatePlayerLevel()
	UpdatePlayerAuras()
	UpdatePlayerThreat()

	UpdateTargetOfTarget()

	if UnitExists("focus") then
		UpdateFocusFrame()
	end

	UpdateAllBossFrames()
end

local function HandlePlayerTargetChanged()
	UpdateTargetHealth()
	UpdateTargetPower()
	UpdateTargetPortrait()
	UpdateTargetName()
	UpdateTargetLevel()
	UpdateTargetClassification()
	UpdateTargetAuras()
	UpdateTargetOfTarget()
	RefreshCastBar("target")
	UpdatePlayerThreat()
	UpdateTargetComboPoints()
end

local function HandlePlayerEnteringWorld()
	ApplyTargetOfTargetVisibilityDriver()
	UpdateTargetOfTarget()
	UpdateAllBossFrames()
	UpdatePlayerThreat()
end

local function HandlePlayerFocusChanged()
	UpdateFocusFrame()
	RefreshCastBar("focus")
end

local function HandleThreatEvent(_, unit)
	if not unit or unit == "player" then
		UpdatePlayerThreat()
	end
end

local function HandleUnitHealthEvent(_, unit)
	if unit == "player" then
		UpdatePlayerHealth()
	elseif unit == "target" then
		UpdateTargetHealth()
	elseif unit == "focus" then
		UpdateFocusHealth()
	elseif IsBossUnit(unit) then
		UpdateBossHealth(unit)
	end
end

local function HandleUnitPowerEvent(_, unit)
	if unit == "player" then
		UpdatePlayerPower()
	elseif unit == "target" then
		UpdateTargetPower()
	elseif unit == "focus" then
		UpdateFocusPower()
	elseif IsBossUnit(unit) then
		UpdateBossPower(unit)
	end

	if UnitIsUnit(unit, "targettarget") then
		UpdateTargetOfTargetPower()
	end
end

local function HandleUnitPortraitEvent(_, unit)
	if unit == "player" then
		UpdatePlayerPortrait()
	elseif unit == "target" then
		UpdateTargetPortrait()
	elseif unit == "focus" then
		UpdateFocusPortrait()
	elseif IsBossUnit(unit) then
		UpdateBossPortrait(unit)
	end
end

local function HandleUnitNameOrLevelEvent(_, unit)
	if unit == "player" then
		UpdatePlayerName()
		UpdatePlayerLevel()
	elseif unit == "target" then
		UpdateTargetName()
		UpdateTargetLevel()
		UpdateTargetClassification()
	elseif unit == "focus" then
		UpdateFocusName()
		UpdateFocusLevel()
		UpdateFocusClassification()
	elseif unit == "targettarget" then
		UpdateTargetOfTargetName()
		UpdateTargetOfTargetLevel()
	elseif IsBossUnit(unit) then
		UpdateBossName(unit)
		UpdateBossLevel(unit)
		UpdateBossClassification(unit)
	end
end

local function HandleUnitClassificationChanged(_, unit)
	if unit == "target" then
		UpdateTargetClassification()
	elseif unit == "focus" then
		UpdateFocusClassification()
	end
	if IsBossUnit(unit) then
		UpdateBossClassification(unit)
	end
end

local function HandleUnitAuraEvent(_, unit)
	if unit == "player" then
		UpdatePlayerAuras()
	elseif unit == "target" then
		UpdateTargetAuras()
	elseif unit == "focus" then
		UpdateFocusAuras()
	end
end

local function HandleUnitTargetEvent(_, unit)
	if unit == "target" then
		UpdateTargetOfTarget()
	end
end

local function HandleUnitTargetableChanged(_, unit)
	if IsBossUnit(unit) then
		UpdateBossFrame(unit)
	end
end

local function HandleEncounterEvent()
	UpdateAllBossFrames()
end

local function HandleRosterEvent()
	ApplyTargetOfTargetVisibilityDriver()
	UpdateTargetOfTarget()
end

local function HandlePlayerUpdateResting()
	UpdatePlayerLevel()
end

local function HandleSpellcastStart(_, unit)
	BeginCast(unit, false)
end

local function HandleSpellcastChannelStart(_, unit)
	BeginCast(unit, true)
end

local function HandleSpellcastStop(_, unit)
	StopCast(unit)
end

local function HandleSpellcastFailed(_, unit)
	FailCast(unit, false)
end

local function HandleSpellcastInterrupted(_, unit)
	FailCast(unit, true)
end

local function HandleSpellcastDelayed(_, unit)
	AdjustCastTiming(unit, false)
end

local function HandleSpellcastChannelUpdate(_, unit)
	AdjustCastTiming(unit, true)
end

local function HandleSpellcastInterruptible(_, unit)
	local castBar = castBarsByUnit[unit]
	if castBar then
		castBar.notInterruptible = false
	end
end

local function HandleSpellcastNotInterruptible(_, unit)
	local castBar = castBarsByUnit[unit]
	if castBar then
		castBar.notInterruptible = true
	end
end

local function HandlePlayerLogout()
	if next(unsavedPositions) then
		for frameName, pos in pairs(unsavedPositions) do
			SavePosition(frameName, pos.point, pos.relativePoint, pos.x, pos.y, pos.relativeTo)
		end
	end

	for frameName in pairs(defaultPositions) do
		local frame = _G[frameName]
		if frame then
			local point, relativeToFrame, relativePoint, x, y = frame:GetPoint()
			if point then
				local relativeToName
				if relativeToFrame then
					relativeToName = relativeToFrame:GetName()
					if not relativeToName and relativeToFrame == UIParent then
						relativeToName = "UIParent"
					end
				end
				SavePosition(frameName, point, relativePoint, x, y, relativeToName)
			end
		end
	end
end

local function HandlePlayerRegenDisabled()
	UpdatePlayerThreat()
	UpdatePlayerLevel()
	OnCombatStart()
end

local function HandlePlayerRegenEnabled()
	UpdatePlayerThreat()
	UpdatePlayerLevel()
	OnCombatEnd()
	ApplyTargetOfTargetVisibilityDriver()
	UpdateTargetOfTarget()
	UpdateAllBossFrames()
end

local EVENT_HANDLERS = {
	PLAYER_LOGIN = function()
		HandlePlayerLogin()
	end,
	PLAYER_LOGOUT = function()
		HandlePlayerLogout()
	end,
	PLAYER_TARGET_CHANGED = function()
		HandlePlayerTargetChanged()
	end,
	PLAYER_ENTERING_WORLD = function()
		HandlePlayerEnteringWorld()
	end,
	PLAYER_FOCUS_CHANGED = function()
		HandlePlayerFocusChanged()
	end,
	PLAYER_UPDATE_RESTING = function()
		HandlePlayerUpdateResting()
	end,
	PLAYER_REGEN_DISABLED = function()
		HandlePlayerRegenDisabled()
	end,
	PLAYER_REGEN_ENABLED = function()
		HandlePlayerRegenEnabled()
	end,
	UNIT_THREAT_SITUATION_UPDATE = HandleThreatEvent,
	UNIT_HEALTH = HandleUnitHealthEvent,
	UNIT_MAXHEALTH = HandleUnitHealthEvent,
	UNIT_POWER_FREQUENT = HandleUnitPowerEvent,
	UNIT_POWER_UPDATE = HandleUnitPowerEvent,
	UNIT_MANA = HandleUnitPowerEvent,
	UNIT_RAGE = HandleUnitPowerEvent,
	UNIT_ENERGY = HandleUnitPowerEvent,
	UNIT_FOCUS = HandleUnitPowerEvent,
	UNIT_RUNIC_POWER = HandleUnitPowerEvent,
	UNIT_MAXPOWER = HandleUnitPowerEvent,
	UNIT_MAXMANA = HandleUnitPowerEvent,
	UNIT_MAXRAGE = HandleUnitPowerEvent,
	UNIT_MAXENERGY = HandleUnitPowerEvent,
	UNIT_MAXFOCUS = HandleUnitPowerEvent,
	UNIT_MAXRUNIC_POWER = HandleUnitPowerEvent,
	UNIT_DISPLAYPOWER = HandleUnitPowerEvent,
	UNIT_PORTRAIT_UPDATE = HandleUnitPortraitEvent,
	UNIT_NAME_UPDATE = HandleUnitNameOrLevelEvent,
	UNIT_LEVEL = HandleUnitNameOrLevelEvent,
	UNIT_CLASSIFICATION_CHANGED = HandleUnitClassificationChanged,
	UNIT_COMBO_POINTS = function()
		UpdateTargetComboPoints()
	end,
	PLAYER_COMBO_POINTS = function()
		UpdateTargetComboPoints()
	end,
	UPDATE_SHAPESHIFT_FORM = function()
		UpdateTargetClassification()
		UpdateTargetComboPoints()
	end,
	UNIT_AURA = HandleUnitAuraEvent,
	UNIT_TARGET = HandleUnitTargetEvent,
	UNIT_TARGETABLE_CHANGED = HandleUnitTargetableChanged,
	INSTANCE_ENCOUNTER_ENGAGE_UNIT = function()
		HandleEncounterEvent()
	end,
	ENCOUNTER_END = function()
		HandleEncounterEvent()
	end,
	PARTY_MEMBERS_CHANGED = function()
		HandleRosterEvent()
	end,
	RAID_ROSTER_UPDATE = function()
		HandleRosterEvent()
	end,
	UNIT_SPELLCAST_START = HandleSpellcastStart,
	UNIT_SPELLCAST_CHANNEL_START = HandleSpellcastChannelStart,
	UNIT_SPELLCAST_STOP = HandleSpellcastStop,
	UNIT_SPELLCAST_CHANNEL_STOP = HandleSpellcastStop,
	UNIT_SPELLCAST_FAILED = HandleSpellcastFailed,
	UNIT_SPELLCAST_INTERRUPTED = HandleSpellcastInterrupted,
	UNIT_SPELLCAST_DELAYED = HandleSpellcastDelayed,
	UNIT_SPELLCAST_CHANNEL_UPDATE = HandleSpellcastChannelUpdate,
	UNIT_SPELLCAST_INTERRUPTIBLE = HandleSpellcastInterruptible,
	UNIT_SPELLCAST_NOT_INTERRUPTIBLE = HandleSpellcastNotInterruptible,
}

-- Table-driven dispatcher keeps the event handler list declarative and easy to audit.
eventFrame:SetScript("OnEvent", function(_, event, ...)
	local handler = EVENT_HANDLERS[event]
	if handler then
		handler(event, ...)
	end
end)

-- OnUpdate for cast bar
-- Poll cast bars outside the event system so channel/channel updates continue during fades.
eventFrame:SetScript("OnUpdate", function()
	for _, castBar in pairs(castBarsByUnit) do
		if castBar.state ~= CASTBAR_STATE.HIDDEN then
			UpdateCastBar(castBar)
		end
	end
end)
