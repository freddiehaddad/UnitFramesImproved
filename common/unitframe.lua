--[[
	UnitFramesImproved - Unit Frame Factory
	
	Provides factory functions for creating unit frames and shared update functions
	that are used across all frame types (player, target, focus, ToT, boss).
]]

---@diagnostic disable: undefined-global

-------------------------------------------------------------------------------
-- MODULE SETUP
-------------------------------------------------------------------------------

local UFI = UnitFramesImproved

-- Module namespace
UFI.UnitFrame = UFI.UnitFrame or {}
local UnitFrame = UFI.UnitFrame

-- Dependencies (will be initialized)
local Utils
local Layout
local UFI_LAYOUT
local LayoutResolveRect
local CreateStatusBar
local CreateFontString
local CreatePortrait
local FRAME_TEXTURES
local BOSS_CLASSIFICATION_TEXTURES
local NAME_TEXT_COLOR_R, NAME_TEXT_COLOR_G, NAME_TEXT_COLOR_B
local InitializeFramePosition
local unpack

-- Forward declarations for frame accessors (will be set by main file)
local frameAccessors = {}

-------------------------------------------------------------------------------
-- UNIT FRAME FACTORY
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
	local visual = Utils.SetupUnitFrameBase(frame, texturePath, frame.mirrored)
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

	local texture = Utils.CreateUnitArtTexture(frame.visualLayer, texturePath, frame.mirrored, layer, subLevel)
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
		frame.buffs = Utils.CreateAuraRow(frame, buffsConfig)
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
		frame.debuffs = Utils.CreateAuraRow(frame, debuffsConfig)
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

-------------------------------------------------------------------------------
-- SHARED UPDATE FUNCTIONS
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

local function UpdateUnitFrameHealth(frame)
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

	local r, g, b = Utils.GetUnitColor(unit)
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
				frame.healthText:SetText(Utils.FormatStatusText(health, maxHealth))
			end
		end
	elseif frame.healthText then
		frame.healthText:SetText(Utils.FormatStatusText(health, maxHealth))
	end

	if profile.customHealthUpdate then
		profile.customHealthUpdate(frame, unit, health, maxHealth, statusKey)
	end
end

local function UpdateUnitFramePower(frame)
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
		frame.powerText:SetText(Utils.FormatStatusText(power, maxPower))
	end

	if profile.customPowerUpdate then
		profile.customPowerUpdate(frame, unit, power, maxPower, false)
	end
end

local function UpdateUnitFrameName(frame)
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
	local truncatedName = Utils.TruncateNameToFit(frame.nameText, UnitName(unit) or "", maxWidth)
	frame.nameText:SetText(truncatedName)

	local profile = GetFrameProfile(frame)
	if profile and profile.customNameUpdate then
		profile.customNameUpdate(frame, unit)
	end
end

local function UpdateUnitFramePortrait(frame)
	if not frame or not frame.portrait then
		return
	end

	local unit = ResolveProfileUnit(frame)
	if not unit or not UnitExists(unit) then
		return
	end

	SetPortraitTexture(frame.portrait, unit)
end

local function UpdateUnitFrameLevel(frame)
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

-------------------------------------------------------------------------------
-- MODULE INITIALIZATION
-------------------------------------------------------------------------------

function UnitFrame.Initialize(deps)
	-- Import dependencies
	Utils = deps.Utils
	Layout = deps.Layout
	UFI_LAYOUT = deps.UFI_LAYOUT
	LayoutResolveRect = deps.LayoutResolveRect
	CreateStatusBar = deps.CreateStatusBar
	CreateFontString = deps.CreateFontString
	CreatePortrait = deps.CreatePortrait
	FRAME_TEXTURES = deps.FRAME_TEXTURES
	BOSS_CLASSIFICATION_TEXTURES = deps.BOSS_CLASSIFICATION_TEXTURES
	NAME_TEXT_COLOR_R = deps.NAME_TEXT_COLOR_R
	NAME_TEXT_COLOR_G = deps.NAME_TEXT_COLOR_G
	NAME_TEXT_COLOR_B = deps.NAME_TEXT_COLOR_B
	InitializeFramePosition = deps.InitializeFramePosition
	unpack = deps.unpack
end

-------------------------------------------------------------------------------
-- MODULE EXPORTS
-------------------------------------------------------------------------------

-- Factory functions
UnitFrame.CreateUnitFrame = CreateUnitFrame
UnitFrame.ApplyUnitFrameProfileDefaults = ApplyUnitFrameProfileDefaults
UnitFrame.AttachStatusIndicator = AttachStatusIndicator
UnitFrame.AttachClassificationOverlay = AttachClassificationOverlay
UnitFrame.AttachAuraContainers = AttachAuraContainers
UnitFrame.MakeUnitFrameUpdater = MakeUnitFrameUpdater

-- Shared update functions
UnitFrame.GetFrameProfile = GetFrameProfile
UnitFrame.ResolveProfileUnit = ResolveProfileUnit
UnitFrame.ApplyLevelColorByDiff = ApplyLevelColorByDiff
UnitFrame.UpdateUnitFrameHealth = UpdateUnitFrameHealth
UnitFrame.UpdateUnitFramePower = UpdateUnitFramePower
UnitFrame.UpdateUnitFrameName = UpdateUnitFrameName
UnitFrame.UpdateUnitFramePortrait = UpdateUnitFramePortrait
UnitFrame.UpdateUnitFrameLevel = UpdateUnitFrameLevel
UnitFrame.UpdateClassificationOverlay = UpdateClassificationOverlay
