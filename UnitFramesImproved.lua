--[[
	UnitFramesImproved - Custom Unit Frames for WotLK
	
	This addon creates completely custom unit frames independent of Blizzard's
	default frames to avoid taint issues while providing enhanced visuals.
]]

-------------------------------------------------------------------------------
-- ADDON INITIALIZATION
-------------------------------------------------------------------------------

-- Frame references (global for debugging)
UFI_PlayerFrame = nil

-- Pixel-perfect layout definitions (shared by all unit frames)
local UFI_LAYOUT = {
	TextureSize = { width = 512, height = 256 },
	Art = { x = 52, y = 0, width = 460, height = 200 },
	Click = { x = 56, y = 42, width = 372, height = 87 },
	Health = { x = 60, y = 46, width = 238, height = 58 },
	Power = { x = 60, y = 106, width = 236, height = 20 },
	Portrait = { x = 305, y = 31, width = 116, height = 116 },
	LevelRest = { x = 386, y = 112, width = 39, height = 39 },
	CastBar = {
		TextureSize = { width = 128, height = 16 },
		Fill = { x = 3, y = 3, width = 122, height = 10 },
		OffsetY = 50,
		DefaultWidth = 122,
		DefaultHeight = 10,
	},
}

--[[
Pixel Alignment Validation
- Temporarily enable a 1:1 UI scale with `/console UIScale 1` and reload to avoid filtering.
- Use the `/ufi unlock` overlay to confirm bars and portraits line up against the art cutouts.
- Toggle `ProjectedTextures` and inspect the cast bars; every edge should sit on whole pixels without shimmering.
- Restore your preferred scale after verification.
]]

local function LayoutResolveX(rect, mirrored)
	local width = rect.width or rect.size
	if not mirrored then
		return rect.x - UFI_LAYOUT.Art.x
	end
	local localX = rect.x - UFI_LAYOUT.Art.x
	return UFI_LAYOUT.Art.width - (localX + width)
end

local function LayoutResolveY(rect)
	return rect.y - UFI_LAYOUT.Art.y
end

local function LayoutResolveRect(rect, mirrored)
	local x = LayoutResolveX(rect, mirrored)
	local y = LayoutResolveY(rect)
	local width = rect.width or rect.size
	local height = rect.height or rect.size
	return x, y, width, height
end

local function LayoutToTexCoord(rect)
	local tex = UFI_LAYOUT.TextureSize
	local left = rect.x / tex.width
	local right = (rect.x + rect.width) / tex.width
	local top = rect.y / tex.height
	local bottom = (rect.y + rect.height) / tex.height
	return left, right, top, bottom
end

local AURA_ICON_SPACING = 4
local AURA_ROW_VERTICAL_SPACING = 6
local AURA_HITRECT_PADDING = 5

local STATUSBAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local FONT_DEFAULT = "Fonts\\FRIZQT__.TTF"

local DEFAULT_BOSS_FRAME_SCALE = 0.45

local DEFAULT_FRAME_SCALES = {
	UFI_PlayerFrame = 0.55,
	UFI_TargetFrame = 0.55,
	UFI_TargetOfTargetFrame = 0.25,
	UFI_FocusFrame = 0.55,
	UFI_BossFrameAnchor = 1,
}

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
-- UTILITY FUNCTIONS
-------------------------------------------------------------------------------

-- Debug output to chat
local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[UFI]|r " .. tostring(msg))
end

-- Get unit color (class color for players, reaction color for NPCs)
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

-- Format large numbers with abbreviations (k/M/G)
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

local FRAME_TEXTURES = {
	default = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame",
	player = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare",
	elite = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Elite",
	rare = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare",
	rareElite = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare-Elite",
}

local PLAYER_TEXTURE_COLORS = {
	normal = { r = 1, g = 1, b = 1 },
	threat = { r = 1, g = 0.3, b = 0.3 },
}

local MAX_BOSS_FRAMES = 4
for index = 1, MAX_BOSS_FRAMES do
	DEFAULT_FRAME_SCALES["UFI_BossFrame" .. index] = DEFAULT_FRAME_SCALES["UFI_BossFrame" .. index]
		or DEFAULT_BOSS_FRAME_SCALE
end
local BOSS_FRAME_STRIDE = UFI_LAYOUT.Art.height + UFI_LAYOUT.CastBar.OffsetY + 40
local BOSS_CLASSIFICATION_TEXTURES = {
	worldboss = FRAME_TEXTURES.elite,
	elite = FRAME_TEXTURES.elite,
	rare = FRAME_TEXTURES.rare,
	rareelite = FRAME_TEXTURES.rareElite,
}
local bossFrames = {}
local bossFramesByUnit = {}
local UpdateBossFrame
local UpdateAllBossFrames

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

local SELF_BUFF_EXCLUSIONS = {
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
	[9931032] = true,
}

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

local function CreatePortrait(parent, mirrored)
	local rect = UFI_LAYOUT.Portrait
	local x, y, width, height = LayoutResolveRect(rect, mirrored)
	local portrait = parent:CreateTexture(nil, "BACKGROUND", nil, 0)
	portrait:SetSize(width, height)
	portrait:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	return portrait
end

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

local function CreateUnitInteractionDropdown(unit, dropdownName, options)
	local fallbackTitle = (options and options.fallbackTitle) or unit
	local extraLevel1Buttons = options and options.extraLevel1Buttons
	local level1Builder = options and options.level1Builder

	local level2Handlers
	if options then
		local provided = options.level2Handlers
		local legacy = options.extraLevel2Handlers
		if provided and legacy and provided ~= legacy then
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
			info.func = CloseDropDownMenus
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
	if not UnitFramesImprovedDB then
		UnitFramesImprovedDB = {
			version = "1.0.0",
			isUnlocked = false,
			positions = {},
			scales = {},
		}
	end

	-- Migrate old versions if needed
	if not UnitFramesImprovedDB.version or UnitFramesImprovedDB.version < "1.0.0" then
		UnitFramesImprovedDB.version = "1.0.0"
	end

	UnitFramesImprovedDB.scales = UnitFramesImprovedDB.scales or {}
	for frameName, defaultScale in pairs(DEFAULT_FRAME_SCALES) do
		local current = UnitFramesImprovedDB.scales[frameName]
		if type(current) ~= "number" or current <= 0 then
			UnitFramesImprovedDB.scales[frameName] = defaultScale
		end
	end
end

-- Validate position data
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

-- Check if frames can be repositioned
local function CanRepositionFrames()
	return not InCombatLockdown()
end

-- Save position for a frame
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

-- Apply position to a frame
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

-- Apply all pending positions (called after combat ends)
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

-- Reset frame to default position
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
	table.wipe(unsavedPositions)

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
		Print("|cff00ff00UnitFramesImproved v1.0.0|r")
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

local function CreatePlayerFrame()
	local mirrored = true
	local frame = CreateFrame("Button", "UFI_PlayerFrame", UIParent, "SecureUnitButtonTemplate")
	frame:SetSize(UFI_LAYOUT.Art.width, UFI_LAYOUT.Art.height)
	frame:SetFrameStrata("LOW")
	frame:SetFrameLevel(20)
	frame.mirrored = mirrored

	ApplyFrameHitRect(frame, mirrored)
	InitializeFramePosition("UFI_PlayerFrame", frame)

	local visual = CreateFrame("Frame", nil, frame)
	visual:SetAllPoints(frame)
	visual:SetFrameStrata("LOW")
	visual:SetFrameLevel(frame:GetFrameLevel())
	frame.visualLayer = visual

	frame.texture = CreateUnitArtTexture(visual, FRAME_TEXTURES.player, mirrored, "ARTWORK", 0)
	frame.portraitMask = CreateUnitArtTexture(visual, FRAME_TEXTURES.player, mirrored, "ARTWORK", 5)
	frame.portraitMask:SetBlendMode("BLEND")
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

	frame.healthBar = CreateStatusBar(visual, UFI_LAYOUT.Health, mirrored)
	frame.powerBar = CreateStatusBar(visual, UFI_LAYOUT.Power, mirrored)

	frame.portrait = CreatePortrait(visual, mirrored)
	SetPortraitTexture(frame.portrait, "player")

	local levelX, levelY, levelWidth, levelHeight = LayoutResolveRect(UFI_LAYOUT.LevelRest, mirrored)
	local levelText = CreateFontString(visual, {
		point = "TOPLEFT",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = levelX,
		y = -levelY,
		size = 14,
		flags = "OUTLINE",
		drawLayer = 0,
		color = { r = 1, g = 0.82, b = 0 },
	})
	levelText:SetSize(levelWidth, levelHeight)
	levelText:SetJustifyH("CENTER")
	levelText:SetJustifyV("MIDDLE")
	frame.levelText = levelText

	frame.nameText = CreateFontString(frame.healthBar, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = 8,
		size = 16,
		flags = "THICKOUTLINE",
		drawLayer = 7,
	})
	frame.nameText:SetText(UnitName("player"))

	frame.healthText = CreateFontString(frame.healthBar, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = -10,
		size = 14,
		flags = "OUTLINE",
		drawLayer = 7,
		color = { r = 1, g = 1, b = 1 },
	})
	frame.healthText:SetText("")

	frame.powerText = CreateFontString(frame.powerBar, {
		point = "CENTER",
		relativeTo = frame.powerBar,
		relativePoint = "CENTER",
		x = 0,
		y = 0,
		size = 13,
		flags = "OUTLINE",
		drawLayer = 7,
		color = { r = 1, g = 1, b = 1 },
	})
	frame.powerText:SetText("")

	local selfBuffLevel = math.max((visual:GetFrameLevel() or 1) - 1, 0)
	frame.selfBuffs = CreateAuraRow(frame, {
		parent = visual,
		mirrored = mirrored,
		count = 5,
		position = "above",
		order = 1,
		frameStrata = "LOW",
		frameLevel = selfBuffLevel,
	})
	for i = 1, #frame.selfBuffs do
		frame.selfBuffs[i].border:SetVertexColor(1, 1, 1)
	end

	frame:EnableMouse(true)
	frame:RegisterForClicks("AnyUp")

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
					{ text = "5 Player", value = 1 },
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
					{ text = "Normal (10-25 Players)", value = 1 },
					{ text = "Heroic (10-25 Players)", value = 2 },
					{ text = "Mythic (10-25 Players)", value = 3 },
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
local CASTBAR_STATE = {
	HIDDEN = "hidden",
	CASTING = "casting",
	CHANNELING = "channeling",
	FINISHED = "finished", -- Holding the end state (for interrupts/fails)
	FADING = "fading",
}

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
		else
			castBar:SetStatusBarColor(1, 0.7, 0)
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
	castBar:SetStatusBarColor(1, 0.7, 0)
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
		else
			castBar:SetStatusBarColor(0.5, 0.5, 0.5)
			castBar.text:SetText("Failed")
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
	if castBar.iconBorder then
		castBar.iconBorder:Hide()
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
	local mirrored = false
	local frame = CreateFrame("Button", "UFI_TargetFrame", UIParent, "SecureUnitButtonTemplate")

	local visual = SetupUnitFrameBase(frame, FRAME_TEXTURES.default, mirrored)
	InitializeFramePosition("UFI_TargetFrame", frame)

	frame.healthBar = CreateStatusBar(visual, UFI_LAYOUT.Health, mirrored)
	frame.powerBar = CreateStatusBar(visual, UFI_LAYOUT.Power, mirrored)

	frame.portrait = CreatePortrait(visual, mirrored)

	local levelX, levelY, levelWidth, levelHeight = LayoutResolveRect(UFI_LAYOUT.LevelRest, mirrored)
	local levelText = CreateFontString(visual, {
		point = "TOPLEFT",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = levelX,
		y = -levelY,
		size = 14,
		flags = "OUTLINE",
		color = { r = 1, g = 0.82, b = 0 },
		drawLayer = 0,
	})
	levelText:SetSize(levelWidth, levelHeight)
	levelText:SetJustifyH("CENTER")
	levelText:SetJustifyV("MIDDLE")
	frame.levelText = levelText

	frame.nameText = CreateFontString(frame.healthBar, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = 8,
		size = 16,
		flags = "THICKOUTLINE",
		drawLayer = 7,
	})

	frame.healthText = CreateFontString(frame.healthBar, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = -10,
		size = 14,
		flags = "OUTLINE",
		color = { r = 1, g = 1, b = 1 },
		drawLayer = 7,
	})

	frame.powerText = CreateFontString(frame.powerBar, {
		point = "CENTER",
		relativeTo = frame.powerBar,
		relativePoint = "CENTER",
		x = 0,
		y = 0,
		size = 13,
		flags = "OUTLINE",
		color = { r = 1, g = 1, b = 1 },
		drawLayer = 7,
	})

	frame.deadText = CreateFontString(frame.healthBar, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = -4,
		size = 12,
		flags = "OUTLINE",
		color = { r = 0.5, g = 0.5, b = 0.5 },
		drawLayer = 7,
	})
	frame.deadText:Hide()

	frame.eliteTexture = CreateUnitArtTexture(visual, FRAME_TEXTURES.default, mirrored, "OVERLAY", 1)
	frame.eliteTexture:Hide()

	frame.castBar = CreateCastBar(frame, "target", mirrored)

	frame.buffs = CreateAuraRow(frame, {
		parent = visual,
		mirrored = mirrored,
		count = 5,
		position = "below",
		order = 1,
	})

	frame.debuffs = CreateAuraRow(frame, {
		parent = visual,
		mirrored = mirrored,
		count = 5,
		position = "below",
		order = 2,
	})

	frame:EnableMouse(true)
	frame:RegisterForClicks("AnyUp")

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
	local mirrored = false
	local frame = CreateFrame("Button", "UFI_FocusFrame", UIParent, "SecureUnitButtonTemplate")

	local visual = SetupUnitFrameBase(frame, FRAME_TEXTURES.default, mirrored)
	InitializeFramePosition("UFI_FocusFrame", frame)

	frame.healthBar = CreateStatusBar(visual, UFI_LAYOUT.Health, mirrored)
	frame.powerBar = CreateStatusBar(visual, UFI_LAYOUT.Power, mirrored)

	frame.portrait = CreatePortrait(visual, mirrored)

	local levelX, levelY, levelWidth, levelHeight = LayoutResolveRect(UFI_LAYOUT.LevelRest, mirrored)
	local levelText = CreateFontString(visual, {
		point = "TOPLEFT",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = levelX,
		y = -levelY,
		size = 14,
		flags = "OUTLINE",
		color = { r = 1, g = 0.82, b = 0 },
		drawLayer = 0,
	})
	levelText:SetSize(levelWidth, levelHeight)
	levelText:SetJustifyH("CENTER")
	levelText:SetJustifyV("MIDDLE")
	frame.levelText = levelText

	frame.nameText = CreateFontString(frame.healthBar, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = 8,
		size = 16,
		flags = "THICKOUTLINE",
		drawLayer = 7,
	})

	frame.healthText = CreateFontString(frame.healthBar, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = -10,
		size = 14,
		flags = "OUTLINE",
		color = { r = 1, g = 1, b = 1 },
		drawLayer = 7,
	})

	frame.powerText = CreateFontString(frame.powerBar, {
		point = "CENTER",
		relativeTo = frame.powerBar,
		relativePoint = "CENTER",
		x = 0,
		y = 0,
		size = 13,
		flags = "OUTLINE",
		color = { r = 1, g = 1, b = 1 },
		drawLayer = 7,
	})

	frame.deadText = CreateFontString(frame.healthBar, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = -4,
		size = 12,
		flags = "OUTLINE",
		color = { r = 0.5, g = 0.5, b = 0.5 },
		drawLayer = 7,
	})
	frame.deadText:Hide()

	frame.eliteTexture = CreateUnitArtTexture(visual, FRAME_TEXTURES.default, mirrored, "OVERLAY", 1)
	frame.eliteTexture:Hide()

	frame.castBar = CreateCastBar(frame, "focus", mirrored)

	frame.buffs = CreateAuraRow(frame, {
		parent = visual,
		mirrored = mirrored,
		count = 5,
		position = "below",
		order = 1,
	})
	frame.debuffs = CreateAuraRow(frame, {
		parent = visual,
		mirrored = mirrored,
		count = 5,
		position = "below",
		order = 2,
	})

	frame:EnableMouse(true)
	frame:RegisterForClicks("AnyUp")

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
	local mirrored = true
	local frame = CreateFrame("Button", "UFI_TargetOfTargetFrame", UIParent, "SecureUnitButtonTemplate")
	local anchorFrame = UFI_TargetFrame or UIParent
	frame:SetFrameStrata("LOW")

	local baseLevel = math.max((anchorFrame and anchorFrame:GetFrameLevel() or 0) + 15, 15)
	frame:SetFrameLevel(baseLevel)

	local visual = SetupUnitFrameBase(frame, FRAME_TEXTURES.default, mirrored)
	visual:SetFrameLevel(baseLevel)
	InitializeFramePosition("UFI_TargetOfTargetFrame", frame)

	frame.healthBar = CreateStatusBar(visual, UFI_LAYOUT.Health, mirrored)
	frame.powerBar = CreateStatusBar(visual, UFI_LAYOUT.Power, mirrored)

	frame.portrait = CreatePortrait(visual, mirrored)

	local levelX, levelY, levelWidth, levelHeight = LayoutResolveRect(UFI_LAYOUT.LevelRest, mirrored)
	local levelText = CreateFontString(visual, {
		point = "TOPLEFT",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = levelX,
		y = -levelY,
		size = 14,
		flags = "OUTLINE",
		color = { r = 1, g = 0.82, b = 0 },
		drawLayer = 0,
	})
	levelText:SetSize(levelWidth, levelHeight)
	levelText:SetJustifyH("CENTER")
	levelText:SetJustifyV("MIDDLE")
	frame.levelText = levelText

	frame.nameText = CreateFontString(frame.healthBar, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = 6,
		size = 20,
		flags = "OUTLINE",
		drawLayer = 7,
	})

	frame:EnableMouse(true)
	frame:RegisterForClicks("AnyUp")

	frame:SetAttribute("unit", "targettarget")
	frame:SetAttribute("type1", "target")
	RegisterUnitWatch(frame)

	frame:Hide()

	return frame
end

-------------------------------------------------------------------------------
-- BOSS FRAME CREATION
-------------------------------------------------------------------------------

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

local function UpdateBossHealth(unit)
	local frame = bossFramesByUnit[unit]
	if not frame then
		return
	end

	if not UnitExists(unit) then
		ClearBossFrame(frame)
		return
	end

	local health = UnitHealth(unit)
	local maxHealth = UnitHealthMax(unit)
	if maxHealth == 0 then
		maxHealth = 1
	end

	frame.healthBar:SetMinMaxValues(0, maxHealth)
	frame.healthBar:SetValue(health)

	local r, g, b = GetUnitColor(unit)
	frame.healthBar:SetStatusBarColor(r, g, b)
	frame.nameText:SetTextColor(r, g, b)
	frame.healthText:SetText(FormatStatusText(health, maxHealth))
end

local function UpdateBossPower(unit)
	local frame = bossFramesByUnit[unit]
	if not frame then
		return
	end

	if not UnitExists(unit) then
		ClearBossFrame(frame)
		return
	end

	local power = UnitPower(unit)
	local maxPower = UnitPowerMax(unit)

	if maxPower == 0 then
		frame.powerBar:Show()
		frame.powerBar:SetMinMaxValues(0, 1)
		frame.powerBar:SetValue(0)
		frame.powerBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 0)
		frame.powerText:SetText("")
		frame.powerText:Hide()
		return
	end

	frame.powerBar:Show()
	frame.powerText:Show()

	frame.powerBar:SetMinMaxValues(0, maxPower)
	frame.powerBar:SetValue(power)
	frame.powerBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 0)

	local powerType = UnitPowerType(unit)
	local info = PowerBarColor[powerType]
	if info then
		frame.powerBar:SetStatusBarColor(info.r, info.g, info.b)
	end
	frame.powerText:SetText(FormatStatusText(power, maxPower))
end

local function UpdateBossPortrait(unit)
	local frame = bossFramesByUnit[unit]
	if not frame then
		return
	end

	if not UnitExists(unit) then
		ClearBossFrame(frame)
		return
	end

	SetPortraitTexture(frame.portrait, unit)
end

local function UpdateBossName(unit)
	local frame = bossFramesByUnit[unit]
	if not frame then
		return
	end

	if not UnitExists(unit) then
		ClearBossFrame(frame)
		return
	end

	frame.nameText:SetText(UnitName(unit) or "")
end

local function UpdateBossLevel(unit)
	local frame = bossFramesByUnit[unit]
	if not frame then
		return
	end

	if not UnitExists(unit) then
		ClearBossFrame(frame)
		return
	end

	local level = UnitLevel(unit)
	if level == -1 then
		frame.levelText:SetText("??")
		frame.levelText:SetTextColor(1, 0, 0)
		return
	end

	if level and level > 0 then
		frame.levelText:SetText(level)
	else
		frame.levelText:SetText("")
	end

	local playerLevel = UnitLevel("player") or 0
	local levelDiff = (level or playerLevel) - playerLevel

	if levelDiff >= 5 then
		frame.levelText:SetTextColor(1, 0, 0)
	elseif levelDiff >= 3 then
		frame.levelText:SetTextColor(1, 0.5, 0)
	elseif levelDiff >= -2 then
		frame.levelText:SetTextColor(1, 1, 0)
	elseif levelDiff >= -4 then
		frame.levelText:SetTextColor(0, 1, 0)
	else
		frame.levelText:SetTextColor(0.5, 0.5, 0.5)
	end
end

local function UpdateBossFrame(unit)
	local frame = bossFramesByUnit[unit]
	if not frame then
		return
	end

	UpdateBossHealth(unit)
	UpdateBossPower(unit)
	UpdateBossPortrait(unit)
	UpdateBossName(unit)
	UpdateBossLevel(unit)

	if UnitExists(unit) then
		ApplyBossTexture(frame, UnitClassification(unit))
	end
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
		local frame = CreateFrame("Button", "UFI_BossFrame" .. index, anchor, "SecureUnitButtonTemplate")
		frame:SetSize(UFI_LAYOUT.Art.width, UFI_LAYOUT.Art.height)
		frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -((index - 1) * BOSS_FRAME_STRIDE))
		frame:SetFrameStrata("LOW")
		ApplyFrameHitRect(frame, false)
		frame.unit = unit
		frame:EnableMouse(true)
		frame:RegisterForClicks("AnyUp")

		frame:SetAttribute("unit", unit)
		frame:SetAttribute("type1", "target")
		RegisterUnitWatch(frame)
		frame:Hide()

		frame:SetFrameLevel((anchor:GetFrameLevel() or 0) + index)
		local visual = SetupUnitFrameBase(frame, FRAME_TEXTURES.default, false)
		visual:SetFrameLevel(frame:GetFrameLevel())

		frame.healthBar = CreateStatusBar(visual, UFI_LAYOUT.Health, false)
		frame.powerBar = CreateStatusBar(visual, UFI_LAYOUT.Power, false)
		frame.portrait = CreatePortrait(visual, false)
		frame.currentTexture = FRAME_TEXTURES.default

		local levelX, levelY, levelWidth, levelHeight = LayoutResolveRect(UFI_LAYOUT.LevelRest, false)
		local levelText = CreateFontString(visual, {
			point = "TOPLEFT",
			relativeTo = frame,
			relativePoint = "TOPLEFT",
			x = levelX,
			y = -levelY,
			size = 14,
			flags = "OUTLINE",
			color = { r = 1, g = 0.82, b = 0 },
			drawLayer = 0,
		})
		levelText:SetSize(levelWidth, levelHeight)
		levelText:SetJustifyH("CENTER")
		levelText:SetJustifyV("MIDDLE")
		frame.levelText = levelText

		frame.nameText = CreateFontString(frame.healthBar, {
			point = "CENTER",
			relativeTo = frame.healthBar,
			relativePoint = "CENTER",
			x = 0,
			y = 8,
			size = 16,
			flags = "THICKOUTLINE",
			drawLayer = 7,
		})

		frame.healthText = CreateFontString(frame.healthBar, {
			point = "CENTER",
			relativeTo = frame.healthBar,
			relativePoint = "CENTER",
			x = 0,
			y = -10,
			size = 14,
			flags = "OUTLINE",
			drawLayer = 7,
			color = { r = 1, g = 1, b = 1 },
		})

		frame.powerText = CreateFontString(frame.powerBar, {
			point = "CENTER",
			relativeTo = frame.powerBar,
			relativePoint = "CENTER",
			x = 0,
			y = 0,
			size = 13,
			flags = "OUTLINE",
			drawLayer = 7,
			color = { r = 1, g = 1, b = 1 },
		})

		frame.castBar = CreateCastBar(frame, unit, false)

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

local function UpdatePlayerHealth()
	if not UFI_PlayerFrame then
		return
	end

	local health = UnitHealth("player")
	local maxHealth = UnitHealthMax("player")

	UFI_PlayerFrame.healthBar:SetMinMaxValues(0, maxHealth)
	UFI_PlayerFrame.healthBar:SetValue(health)

	-- Set color
	local r, g, b = GetUnitColor("player")
	UFI_PlayerFrame.healthBar:SetStatusBarColor(r, g, b)
	UFI_PlayerFrame.nameText:SetTextColor(r, g, b)

	-- Set text
	UFI_PlayerFrame.healthText:SetText(FormatStatusText(health, maxHealth))
end

local function UpdatePlayerPower()
	if not UFI_PlayerFrame then
		return
	end

	local power = UnitPower("player")
	local maxPower = UnitPowerMax("player")
	local powerType = UnitPowerType("player")

	if not UFI_PlayerFrame.powerBar then
		return
	end

	UFI_PlayerFrame.powerBar:SetMinMaxValues(0, maxPower)
	UFI_PlayerFrame.powerBar:SetValue(power)

	-- Ensure texture stays in BACKGROUND layer
	UFI_PlayerFrame.powerBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 0)

	-- Set color based on power type
	local info = PowerBarColor[powerType]
	if info then
		UFI_PlayerFrame.powerBar:SetStatusBarColor(info.r, info.g, info.b)
	end

	-- Set text
	UFI_PlayerFrame.powerText:SetText(FormatStatusText(power, maxPower))
end

local function UpdatePlayerPortrait()
	if not UFI_PlayerFrame then
		return
	end
	SetPortraitTexture(UFI_PlayerFrame.portrait, "player")
end

local function UpdatePlayerName()
	if not UFI_PlayerFrame then
		return
	end
	UFI_PlayerFrame.nameText:SetText(UnitName("player"))
end

local function UpdatePlayerLevel()
	if not UFI_PlayerFrame then
		return
	end

	local frame = UFI_PlayerFrame
	local level = UnitLevel("player")
	local inCombat = UnitAffectingCombat("player")

	if inCombat then
		frame.levelText:SetText(level)
		frame.levelText:SetTextColor(1, 0.25, 0.25) -- Red tint while in combat
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

local function UpdateTargetHealth()
	if not UFI_TargetFrame then
		return
	end

	if not UnitExists("target") then
		return
	end

	local health = UnitHealth("target")
	local maxHealth = UnitHealthMax("target")

	UFI_TargetFrame.healthBar:SetMinMaxValues(0, maxHealth)
	UFI_TargetFrame.healthBar:SetValue(health)

	-- Set color based on unit type and state
	local r, g, b = GetUnitColor("target")
	UFI_TargetFrame.healthBar:SetStatusBarColor(r, g, b)
	UFI_TargetFrame.nameText:SetTextColor(r, g, b)

	-- Check if dead
	if UnitIsDead("target") then
		UFI_TargetFrame.deadText:SetText("Dead")
		UFI_TargetFrame.deadText:Show()
		UFI_TargetFrame.healthText:Hide()
	elseif UnitIsGhost("target") then
		UFI_TargetFrame.deadText:SetText("Ghost")
		UFI_TargetFrame.deadText:Show()
		UFI_TargetFrame.healthText:Hide()
	else
		UFI_TargetFrame.deadText:Hide()
		UFI_TargetFrame.healthText:Show()
		-- Set text
		UFI_TargetFrame.healthText:SetText(FormatStatusText(health, maxHealth))
	end
end

local function UpdateTargetPower()
	if not UFI_TargetFrame or not UnitExists("target") then
		return
	end

	local power = UnitPower("target")
	local maxPower = UnitPowerMax("target")
	local powerType = UnitPowerType("target")

	-- Hide power bar if target has no power
	if maxPower == 0 then
		UFI_TargetFrame.powerBar:Show()
		UFI_TargetFrame.powerBar:SetMinMaxValues(0, 1)
		UFI_TargetFrame.powerBar:SetValue(0)
		UFI_TargetFrame.powerBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 0)
		UFI_TargetFrame.powerText:SetText("")
		UFI_TargetFrame.powerText:Hide()
		return
	end

	UFI_TargetFrame.powerBar:Show()
	UFI_TargetFrame.powerText:Show()

	UFI_TargetFrame.powerBar:SetMinMaxValues(0, maxPower)
	UFI_TargetFrame.powerBar:SetValue(power)

	-- Ensure texture stays in BACKGROUND layer
	UFI_TargetFrame.powerBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 0)

	-- Set color based on power type
	local info = PowerBarColor[powerType]
	if info then
		UFI_TargetFrame.powerBar:SetStatusBarColor(info.r, info.g, info.b)
	end

	-- Set text
	UFI_TargetFrame.powerText:SetText(FormatStatusText(power, maxPower))
end

local function UpdateTargetPortrait()
	if not UFI_TargetFrame or not UnitExists("target") then
		return
	end
	SetPortraitTexture(UFI_TargetFrame.portrait, "target")
end

local function UpdateTargetName()
	if not UFI_TargetFrame or not UnitExists("target") then
		return
	end
	UFI_TargetFrame.nameText:SetText(UnitName("target"))
end

local function UpdateTargetLevel()
	if not UFI_TargetFrame or not UnitExists("target") then
		return
	end

	local level = UnitLevel("target")
	if level == -1 then
		-- Boss level (skull)
		UFI_TargetFrame.levelText:SetText("??")
		UFI_TargetFrame.levelText:SetTextColor(1, 0, 0) -- Red for skull
	else
		UFI_TargetFrame.levelText:SetText(level)

		-- Color based on level difference
		local playerLevel = UnitLevel("player")
		local levelDiff = level - playerLevel

		if levelDiff >= 5 then
			UFI_TargetFrame.levelText:SetTextColor(1, 0, 0) -- Red
		elseif levelDiff >= 3 then
			UFI_TargetFrame.levelText:SetTextColor(1, 0.5, 0) -- Orange
		elseif levelDiff >= -2 then
			UFI_TargetFrame.levelText:SetTextColor(1, 1, 0) -- Yellow
		elseif levelDiff >= -4 then
			UFI_TargetFrame.levelText:SetTextColor(0, 1, 0) -- Green
		else
			UFI_TargetFrame.levelText:SetTextColor(0.5, 0.5, 0.5) -- Gray
		end
	end
end

local function UpdateTargetClassification()
	if not UFI_TargetFrame or not UnitExists("target") then
		return
	end

	local classification = UnitClassification("target")

	if classification == "worldboss" or classification == "elite" then
		UFI_TargetFrame.eliteTexture:SetTexture(
			"Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Elite"
		)
		UFI_TargetFrame.eliteTexture:Show()
	elseif classification == "rare" then
		UFI_TargetFrame.eliteTexture:SetTexture(
			"Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare"
		)
		UFI_TargetFrame.eliteTexture:Show()
	elseif classification == "rareelite" then
		UFI_TargetFrame.eliteTexture:SetTexture(
			"Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare-Elite"
		)
		UFI_TargetFrame.eliteTexture:Show()
	else
		UFI_TargetFrame.eliteTexture:Hide()
	end
end

-------------------------------------------------------------------------------
-- TARGET OF TARGET FRAME UPDATE FUNCTIONS
-------------------------------------------------------------------------------

local function ShouldShowTargetOfTarget()
	if TargetFrame_ShouldShowTargetOfTarget and TargetFrame then
		local ok, result = pcall(TargetFrame_ShouldShowTargetOfTarget, TargetFrame)
		if ok then
			return result
		end
	end

	if not GetCVarBool("showTargetOfTarget") then
		return false
	end

	local mode = tonumber(GetCVar("targetOfTargetMode") or "0") or 0
	local raidMembers = GetNumRaidMembers() or 0
	local partyMembers = GetNumPartyMembers() or 0
	local inRaid = raidMembers > 0
	local inParty = (not inRaid) and partyMembers > 0
	local isSolo = (not inRaid) and not inParty

	if mode == 1 then -- Raid
		return inRaid
	elseif mode == 2 then -- Party
		return inParty
	elseif mode == 3 then -- Solo
		return isSolo
	elseif mode == 4 then -- Raid & Party
		return not isSolo
	end

	return true -- Treat 0 or any unknown value as Always
end

local function ApplyTargetOfTargetVisibility(shouldShow)
	if not UFI_TargetOfTargetFrame then
		return
	end

	UFI_TargetOfTargetFrame.desiredVisibility = shouldShow
	UFI_TargetOfTargetFrame:SetAlpha(shouldShow and 1 or 0)
end

local function UpdateTargetOfTargetHealth()
	if not UFI_TargetOfTargetFrame or not UnitExists("targettarget") then
		return
	end

	local health = UnitHealth("targettarget")
	local maxHealth = UnitHealthMax("targettarget")

	UFI_TargetOfTargetFrame.healthBar:SetMinMaxValues(0, maxHealth)
	UFI_TargetOfTargetFrame.healthBar:SetValue(health)

	-- Set color
	local r, g, b = GetUnitColor("targettarget")
	UFI_TargetOfTargetFrame.healthBar:SetStatusBarColor(r, g, b)
	UFI_TargetOfTargetFrame.nameText:SetTextColor(r, g, b)
end

local function UpdateTargetOfTargetPower()
	if not UFI_TargetOfTargetFrame or not UnitExists("targettarget") then
		return
	end

	local power = UnitPower("targettarget")
	local maxPower = UnitPowerMax("targettarget")
	local powerType = UnitPowerType("targettarget")

	if UFI_TargetOfTargetFrame.powerBar then
		if maxPower == 0 then
			UFI_TargetOfTargetFrame.powerBar:SetMinMaxValues(0, 1)
			UFI_TargetOfTargetFrame.powerBar:SetValue(0)
			return
		end

		UFI_TargetOfTargetFrame.powerBar:SetMinMaxValues(0, maxPower)
		UFI_TargetOfTargetFrame.powerBar:SetValue(power)

		local info = PowerBarColor[powerType]
		if info then
			UFI_TargetOfTargetFrame.powerBar:SetStatusBarColor(info.r, info.g, info.b)
		end
	end
end

local function UpdateTargetOfTargetPortrait()
	if not UFI_TargetOfTargetFrame or not UnitExists("targettarget") then
		return
	end

	SetPortraitTexture(UFI_TargetOfTargetFrame.portrait, "targettarget")
end

local function UpdateTargetOfTargetName()
	if not UFI_TargetOfTargetFrame or not UnitExists("targettarget") then
		return
	end

	UFI_TargetOfTargetFrame.nameText:SetText(UnitName("targettarget"))
end

local function UpdateTargetOfTargetLevel()
	if not UFI_TargetOfTargetFrame or not UnitExists("targettarget") then
		return
	end

	local level = UnitLevel("targettarget")
	if level == -1 then
		-- Boss level (skull)
		UFI_TargetOfTargetFrame.levelText:SetText("??")
		UFI_TargetOfTargetFrame.levelText:SetTextColor(1, 0, 0) -- Red for skull
	else
		UFI_TargetOfTargetFrame.levelText:SetText(level)

		-- Color based on level difference
		local playerLevel = UnitLevel("player")
		local levelDiff = level - playerLevel

		if levelDiff >= 5 then
			UFI_TargetOfTargetFrame.levelText:SetTextColor(1, 0, 0) -- Red
		elseif levelDiff >= 3 then
			UFI_TargetOfTargetFrame.levelText:SetTextColor(1, 0.5, 0) -- Orange
		elseif levelDiff >= -2 then
			UFI_TargetOfTargetFrame.levelText:SetTextColor(1, 1, 0) -- Yellow
		elseif levelDiff >= -4 then
			UFI_TargetOfTargetFrame.levelText:SetTextColor(0, 1, 0) -- Green
		else
			UFI_TargetOfTargetFrame.levelText:SetTextColor(0.5, 0.5, 0.5) -- Gray
		end
	end
end

local function UpdateTargetOfTarget()
	if not UFI_TargetOfTargetFrame then
		return
	end

	if not UnitExists("target") or not UnitExists("targettarget") then
		ApplyTargetOfTargetVisibility(false)
		return
	end

	if not ShouldShowTargetOfTarget() then
		ApplyTargetOfTargetVisibility(false)
		return
	end

	UpdateTargetOfTargetHealth()
	UpdateTargetOfTargetPower()
	UpdateTargetOfTargetPortrait()
	UpdateTargetOfTargetName()
	UpdateTargetOfTargetLevel()
	ApplyTargetOfTargetVisibility(true)
end

-------------------------------------------------------------------------------
-- FOCUS FRAME UPDATE FUNCTIONS
-------------------------------------------------------------------------------

local function UpdateFocusHealth()
	if not UFI_FocusFrame then
		return
	end

	if not UnitExists("focus") then
		return
	end

	local health = UnitHealth("focus")
	local maxHealth = UnitHealthMax("focus")

	if maxHealth == 0 then
		maxHealth = 1
	end

	local isDead = UnitIsDead("focus")
	local isGhost = UnitIsGhost("focus")
	local isDisconnected = not UnitIsConnected("focus")

	if isDead or isGhost or isDisconnected then
		health = 0
	end

	UFI_FocusFrame.healthBar:SetMinMaxValues(0, maxHealth)
	UFI_FocusFrame.healthBar:SetValue(health)

	-- Set color based on unit type and state
	local r, g, b = GetUnitColor("focus")
	UFI_FocusFrame.healthBar:SetStatusBarColor(r, g, b)
	UFI_FocusFrame.nameText:SetTextColor(r, g, b)

	if isDead then
		UFI_FocusFrame.deadText:SetText("Dead")
		UFI_FocusFrame.deadText:Show()
		UFI_FocusFrame.healthText:Hide()
	elseif isGhost then
		UFI_FocusFrame.deadText:SetText("Ghost")
		UFI_FocusFrame.deadText:Show()
		UFI_FocusFrame.healthText:Hide()
	elseif isDisconnected then
		UFI_FocusFrame.deadText:SetText("Offline")
		UFI_FocusFrame.deadText:Show()
		UFI_FocusFrame.healthText:Hide()
	else
		UFI_FocusFrame.deadText:Hide()
		UFI_FocusFrame.healthText:Show()
		UFI_FocusFrame.healthText:SetText(FormatStatusText(health, maxHealth))
	end
end

local function UpdateFocusPower()
	if not UFI_FocusFrame or not UnitExists("focus") then
		return
	end

	local power = UnitPower("focus")
	local maxPower = UnitPowerMax("focus")
	local powerType = UnitPowerType("focus")

	-- Hide power bar if focus has no power
	if maxPower == 0 then
		UFI_FocusFrame.powerBar:Show()
		UFI_FocusFrame.powerBar:SetMinMaxValues(0, 1)
		UFI_FocusFrame.powerBar:SetValue(0)
		UFI_FocusFrame.powerBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 0)
		UFI_FocusFrame.powerText:SetText("")
		UFI_FocusFrame.powerText:Hide()
		return
	end

	UFI_FocusFrame.powerBar:Show()
	UFI_FocusFrame.powerText:Show()

	UFI_FocusFrame.powerBar:SetMinMaxValues(0, maxPower)
	UFI_FocusFrame.powerBar:SetValue(power)

	-- Ensure texture stays in BACKGROUND layer
	UFI_FocusFrame.powerBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 0)

	-- Set color based on power type
	local info = PowerBarColor[powerType]
	if info then
		UFI_FocusFrame.powerBar:SetStatusBarColor(info.r, info.g, info.b)
	end

	-- Set text
	UFI_FocusFrame.powerText:SetText(FormatStatusText(power, maxPower))
end

local function UpdateFocusPortrait()
	if not UFI_FocusFrame then
		return
	end

	SetPortraitTexture(UFI_FocusFrame.portrait, "focus")
end

local function UpdateFocusName()
	if not UFI_FocusFrame then
		return
	end

	UFI_FocusFrame.nameText:SetText(UnitName("focus"))
end

local function UpdateFocusLevel()
	if not UFI_FocusFrame or not UnitExists("focus") then
		return
	end

	local level = UnitLevel("focus")
	if level == -1 then
		-- Boss level (skull)
		UFI_FocusFrame.levelText:SetText("??")
		UFI_FocusFrame.levelText:SetTextColor(1, 0, 0) -- Red for skull
	else
		UFI_FocusFrame.levelText:SetText(level)

		-- Color based on level difference
		local playerLevel = UnitLevel("player")
		local levelDiff = level - playerLevel

		if levelDiff >= 5 then
			UFI_FocusFrame.levelText:SetTextColor(1, 0, 0) -- Red
		elseif levelDiff >= 3 then
			UFI_FocusFrame.levelText:SetTextColor(1, 0.5, 0) -- Orange
		elseif levelDiff >= -2 then
			UFI_FocusFrame.levelText:SetTextColor(1, 1, 0) -- Yellow
		elseif levelDiff >= -4 then
			UFI_FocusFrame.levelText:SetTextColor(0, 1, 0) -- Green
		else
			UFI_FocusFrame.levelText:SetTextColor(0.5, 0.5, 0.5) -- Gray
		end
	end
end

local function UpdateFocusClassification()
	if not UFI_FocusFrame or not UnitExists("focus") then
		return
	end

	local classification = UnitClassification("focus")

	if classification == "worldboss" or classification == "elite" then
		UFI_FocusFrame.eliteTexture:SetTexture(
			"Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Elite"
		)
		UFI_FocusFrame.eliteTexture:Show()
	elseif classification == "rare" then
		UFI_FocusFrame.eliteTexture:SetTexture(
			"Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare"
		)
		UFI_FocusFrame.eliteTexture:Show()
	elseif classification == "rareelite" then
		UFI_FocusFrame.eliteTexture:SetTexture(
			"Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare-Elite"
		)
		UFI_FocusFrame.eliteTexture:Show()
	else
		UFI_FocusFrame.eliteTexture:Hide()
	end
end

local function HideAuraRows(frame)
	if not frame then
		return
	end

	if frame.buffs then
		for i = 1, #frame.buffs do
			frame.buffs[i]:Hide()
		end
	end

	if frame.debuffs then
		for i = 1, #frame.debuffs do
			frame.debuffs[i]:Hide()
		end
	end
end

local function SortByRemainingTime(a, b)
	return a.remainingTime < b.remainingTime
end

local function UpdateUnitAuras(unit, frame)
	if not frame then
		return
	end

	if not UnitExists(unit) then
		HideAuraRows(frame)
		PositionAuraRow(frame.debuffs, frame, frame.mirrored, "below", 1)
		return
	end

	local now = GetTime()

	local allBuffs = {}
	for i = 1, 40 do
		local name, _, icon, count, _, duration, expirationTime = UnitBuff(unit, i)
		if not name then
			break
		end

		local remainingTime = 999999
		if duration and duration > 0 and expirationTime then
			remainingTime = expirationTime - now
		end

		allBuffs[#allBuffs + 1] = {
			icon = icon,
			count = count,
			duration = duration,
			expirationTime = expirationTime,
			remainingTime = remainingTime,
		}
	end

	table.sort(allBuffs, SortByRemainingTime)

	local buffsShown = 0
	if frame.buffs then
		for i = 1, #frame.buffs do
			local buffFrame = frame.buffs[i]
			local data = allBuffs[i]
			if data then
				buffFrame.icon:SetTexture(data.icon)
				if data.duration and data.duration > 0 and data.expirationTime then
					buffFrame.cooldown:SetCooldown(data.expirationTime - data.duration, data.duration)
				end
				if data.count and data.count > 1 then
					buffFrame.count:SetText(data.count)
					buffFrame.count:Show()
				else
					buffFrame.count:Hide()
				end
				buffFrame:Show()
				buffsShown = buffsShown + 1
			else
				buffFrame:Hide()
			end
		end
	end

	local playerDebuffs = {}
	for i = 1, 40 do
		local name, _, icon, count, debuffType, duration, expirationTime, caster = UnitDebuff(unit, i)
		if not name then
			break
		end

		if caster == "player" or caster == "pet" or caster == "vehicle" then
			local remainingTime = 999999
			if duration and duration > 0 and expirationTime then
				remainingTime = expirationTime - now
			end

			playerDebuffs[#playerDebuffs + 1] = {
				icon = icon,
				count = count,
				debuffType = debuffType,
				duration = duration,
				expirationTime = expirationTime,
				remainingTime = remainingTime,
			}
		end
	end

	table.sort(playerDebuffs, SortByRemainingTime)

	local desiredOrder = buffsShown > 0 and 2 or 1
	if frame.debuffs and frame.debuffs.currentOrder ~= desiredOrder then
		PositionAuraRow(frame.debuffs, frame, frame.mirrored, "below", desiredOrder)
	end

	if frame.debuffs then
		for i = 1, #frame.debuffs do
			local debuffFrame = frame.debuffs[i]
			local data = playerDebuffs[i]
			if data then
				debuffFrame.icon:SetTexture(data.icon)
				local color = DebuffTypeColor[data.debuffType or "none"] or DebuffTypeColor["none"]
				debuffFrame.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
				debuffFrame.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
				debuffFrame.border:SetVertexColor(color[1], color[2], color[3])

				if data.duration and data.duration > 0 and data.expirationTime then
					debuffFrame.cooldown:SetCooldown(data.expirationTime - data.duration, data.duration)
				end
				if data.count and data.count > 1 then
					debuffFrame.count:SetText(data.count)
					debuffFrame.count:Show()
				else
					debuffFrame.count:Hide()
				end
				debuffFrame:Show()
			else
				debuffFrame:Hide()
			end
		end
	end
end

local function UpdateFocusAuras()
	UpdateUnitAuras("focus", UFI_FocusFrame)
end

local function UpdatePlayerAuras()
	if not UFI_PlayerFrame or not UFI_PlayerFrame.selfBuffs then
		return
	end

	local now = GetTime()
	local selfBuffs = {}

	for i = 1, 40 do
		local name, _, icon, count, _, duration, expirationTime, caster, _, _, spellId = UnitBuff("player", i)
		if not name then
			break
		end

		if
			(caster == "player" or caster == "pet" or caster == "vehicle")
			and not (spellId and SELF_BUFF_EXCLUSIONS[spellId])
		then
			local remainingTime = 999999
			if duration and duration > 0 and expirationTime then
				remainingTime = expirationTime - now
			end

			selfBuffs[#selfBuffs + 1] = {
				icon = icon,
				count = count,
				duration = duration,
				expirationTime = expirationTime,
				remainingTime = remainingTime,
			}
		end
	end

	table.sort(selfBuffs, SortByRemainingTime)

	for i = 1, #UFI_PlayerFrame.selfBuffs do
		local iconFrame = UFI_PlayerFrame.selfBuffs[i]
		local data = selfBuffs[i]

		if data then
			iconFrame.icon:SetTexture(data.icon)
			if data.duration and data.duration > 0 and data.expirationTime then
				iconFrame.cooldown:SetCooldown(data.expirationTime - data.duration, data.duration)
				iconFrame.cooldown:Show()
			else
				iconFrame.cooldown:Hide()
			end

			if data.count and data.count > 1 then
				iconFrame.count:SetText(data.count)
				iconFrame.count:Show()
			else
				iconFrame.count:Hide()
			end

			iconFrame.border:SetVertexColor(1, 1, 1)
			iconFrame:Show()
		else
			iconFrame.cooldown:Hide()
			iconFrame.count:Hide()
			iconFrame:Hide()
		end
	end
end

local function UpdateFocusFrame()
	if not UFI_FocusFrame then
		return
	end

	if UnitExists("focus") then
		UpdateFocusHealth()
		UpdateFocusPower()
		UpdateFocusPortrait()
		UpdateFocusName()
		UpdateFocusLevel()
		UpdateFocusClassification()
		UpdateFocusAuras()
	end
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
	UpdateUnitAuras("target", UFI_TargetFrame)
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

eventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_LOGIN" then
		-- Initialize database
		InitializeDatabase()

		-- Create frames on login
		UFI_PlayerFrame = CreatePlayerFrame()
		UFI_TargetFrame = CreateTargetFrame()
		UFI_FocusFrame = CreateFocusFrame()
		UFI_TargetOfTargetFrame = CreateTargetOfTargetFrame()
		UFI_BossFrameAnchor = CreateBossFrames()

		-- Hide default Blizzard frames
		PlayerFrame:UnregisterAllEvents()
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

		-- Also hide target of target frame if it exists
		if TargetFrameToT then
			TargetFrameToT:UnregisterAllEvents()
			TargetFrameToT:Hide()
			TargetFrameToT:SetAlpha(0)
		end

		-- Apply saved positions FIRST
		ApplyPosition("UFI_PlayerFrame")
		ApplyPosition("UFI_TargetFrame")
		ApplyPosition("UFI_TargetOfTargetFrame")
		ApplyPosition("UFI_FocusFrame")
		ApplyPosition("UFI_BossFrameAnchor")

		-- Create overlays for movable frames AFTER positioning
		CreateOverlay(UFI_PlayerFrame, "UFI_PlayerFrame")
		CreateOverlay(UFI_TargetFrame, "UFI_TargetFrame")
		if UFI_TargetOfTargetFrame then
			CreateOverlay(UFI_TargetOfTargetFrame, "UFI_TargetOfTargetFrame")
		end
		CreateOverlay(UFI_FocusFrame, "UFI_FocusFrame")
		if UFI_BossFrameAnchor then
			CreateOverlay(UFI_BossFrameAnchor, "UFI_BossFrameAnchor")
		end

		-- Hook into SetCVar to detect changes from Interface Options
		-- The Interface Options UI uses the old SetCVar() function which doesn't
		-- trigger CVAR_UPDATE events. Only C_CVar.SetCVar() triggers that event.
		-- This hook allows us to detect changes immediately without polling.
		hooksecurefunc("SetCVar", function(name, value)
			if name == "statusTextPercentage" then
				-- Update all visible frames when percentage display setting changes
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
				UpdateTargetOfTarget()
			end
		end)

		-- Restore unlocked state if it was unlocked
		if UnitFramesImprovedDB.isUnlocked and not InCombatLockdown() then
			UnlockFrames()
		end

		-- Display welcome message
		Print("|cff00ff00UnitFramesImproved v1.0.0 loaded!|r Type |cffffcc00/ufi help|r for commands.")

		-- Initial updates
		UpdatePlayerHealth()
		UpdatePlayerPower()
		UpdatePlayerPortrait()
		UpdatePlayerName()
		UpdatePlayerLevel()
		UpdatePlayerAuras()
		UpdatePlayerThreat()

		UpdateTargetOfTarget()

		-- Update focus frame if focus exists
		if UnitExists("focus") then
			UpdateFocusFrame()
		end

		UpdateAllBossFrames()
	elseif event == "PLAYER_TARGET_CHANGED" then
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
	elseif event == "PLAYER_ENTERING_WORLD" then
		UpdateTargetOfTarget()
		UpdateAllBossFrames()
		UpdatePlayerThreat()
	elseif event == "PLAYER_FOCUS_CHANGED" then
		UpdateFocusFrame()
		RefreshCastBar("focus")
	elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
		local unit = ...
		if not unit or unit == "player" then
			UpdatePlayerThreat()
		end
	elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		UpdatePlayerThreat()
		UpdatePlayerLevel()
	elseif event == "UNIT_HEALTH" then
		local unit = ...
		if unit == "player" then
			UpdatePlayerHealth()
		elseif unit == "target" then
			UpdateTargetHealth()
		elseif unit == "focus" then
			UpdateFocusHealth()
		elseif IsBossUnit(unit) then
			UpdateBossHealth(unit)
		end
	elseif event == "UNIT_MAXHEALTH" then
		local unit = ...
		if unit == "player" then
			UpdatePlayerHealth()
		elseif unit == "target" then
			UpdateTargetHealth()
		elseif unit == "focus" then
			UpdateFocusHealth()
		elseif IsBossUnit(unit) then
			UpdateBossHealth(unit)
		end
	elseif
		event == "UNIT_POWER_FREQUENT"
		or event == "UNIT_POWER_UPDATE"
		or event == "UNIT_MANA"
		or event == "UNIT_RAGE"
		or event == "UNIT_ENERGY"
		or event == "UNIT_FOCUS"
		or event == "UNIT_RUNIC_POWER"
	then
		local unit = ...
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
	elseif
		event == "UNIT_MAXPOWER"
		or event == "UNIT_MAXMANA"
		or event == "UNIT_MAXRAGE"
		or event == "UNIT_MAXENERGY"
		or event == "UNIT_MAXFOCUS"
		or event == "UNIT_MAXRUNIC_POWER"
	then
		local unit = ...
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
	elseif event == "UNIT_PORTRAIT_UPDATE" then
		local unit = ...
		if unit == "player" then
			UpdatePlayerPortrait()
		elseif unit == "target" then
			UpdateTargetPortrait()
		elseif unit == "focus" then
			UpdateFocusPortrait()
		elseif IsBossUnit(unit) then
			UpdateBossPortrait(unit)
		end
	elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" then
		local unit = ...
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
			UpdateBossFrame(unit)
		end
	elseif event == "UNIT_CLASSIFICATION_CHANGED" then
		local unit = ...
		if IsBossUnit(unit) then
			UpdateBossFrame(unit)
		end
	elseif event == "UNIT_DISPLAYPOWER" then
		local unit = ...
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
	elseif event == "UNIT_AURA" then
		local unit = ...
		if unit == "player" then
			UpdatePlayerAuras()
		elseif unit == "target" then
			UpdateTargetAuras()
		elseif unit == "focus" then
			UpdateFocusAuras()
		end
	elseif event == "UNIT_TARGET" then
		local unit = ...
		if unit == "target" then
			UpdateTargetOfTarget()
		end
	elseif event == "UNIT_TARGETABLE_CHANGED" then
		local unit = ...
		if IsBossUnit(unit) then
			UpdateBossFrame(unit)
		end
	elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" or event == "ENCOUNTER_END" then
		UpdateAllBossFrames()
	elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
		UpdateTargetOfTarget()
	elseif event == "PLAYER_UPDATE_RESTING" then
		UpdatePlayerLevel()

	-- Cast bar events
	elseif event == "UNIT_SPELLCAST_START" then
		local unit = ...
		BeginCast(unit, false)
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		local unit = ...
		BeginCast(unit, true)
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		local unit = ...
		StopCast(unit)
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		local unit = ...
		FailCast(unit, event == "UNIT_SPELLCAST_INTERRUPTED")
	elseif event == "UNIT_SPELLCAST_DELAYED" then
		local unit = ...
		AdjustCastTiming(unit, false)
	elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
		local unit = ...
		AdjustCastTiming(unit, true)
	elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
		local unit = ...
		local castBar = castBarsByUnit[unit]
		if castBar then
			castBar.notInterruptible = false
		end
	elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
		local unit = ...
		local castBar = castBarsByUnit[unit]
		if castBar then
			castBar.notInterruptible = true
		end
	elseif event == "PLAYER_LOGOUT" then
		if isUnlocked then
			return
		end

		-- Save all frame positions before logout
		for frameName, _ in pairs(defaultPositions) do
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
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Combat started
		OnCombatStart()
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- Combat ended
		OnCombatEnd()
		UpdateTargetOfTarget()
		UpdateAllBossFrames()
	end
end)

-- OnUpdate for cast bar
eventFrame:SetScript("OnUpdate", function()
	for _, castBar in pairs(castBarsByUnit) do
		if castBar.state ~= CASTBAR_STATE.HIDDEN then
			UpdateCastBar(castBar)
		end
	end
end)
