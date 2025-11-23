--[[----------------------------------------------------------------------------
	UnitFramesImproved - Target Frame
	
	Creates and manages the target unit frame.
	
	Dependencies:
	- UnitFrameFactory (CreateUnitFrame, ApplyUnitFrameProfileDefaults, etc.)
	- CastBar (CreateCastBar, RefreshCastBar)
	- Auras (UpdateUnitAuras)
	- TargetOfTarget (UpdateTargetOfTarget)
	- Config (FRAME_TEXTURES, ROGUE_FRAME_TEXTURES, BOSS_CLASSIFICATION_TEXTURES, ROGUE_BOSS_CLASSIFICATION_TEXTURES)
	- Layout (for combo points positioning)
------------------------------------------------------------------------------]]

---@diagnostic disable: undefined-global

local UFI = UnitFramesImproved
local TargetFrameModule = {}
UFI.TargetFrame = TargetFrameModule

-- Dependencies (injected via Initialize)
local UnitFrameFactory
local CreateCastBar
local RefreshCastBar
local UpdateUnitAuras
local UpdateTargetOfTarget
local FRAME_TEXTURES
local ROGUE_FRAME_TEXTURES
local BOSS_CLASSIFICATION_TEXTURES
local ROGUE_BOSS_CLASSIFICATION_TEXTURES
local Layout
local UFI_LAYOUT
local LayoutResolveRect

-- Local references to factory functions
local CreateUnitFrame
local ApplyUnitFrameProfileDefaults
local AttachStatusIndicator
local AttachClassificationOverlay
local AttachAuraContainers
local UpdateUnitFrameHealth
local UpdateUnitFramePower
local UpdateUnitFramePortrait
local UpdateUnitFrameName
local UpdateUnitFrameLevel
local UpdateClassificationOverlay
local GetFrameProfile

-- Local references to Utils
local CreateFontString

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
	if frame.ufProfile then
		frame.ufProfile.classificationTextures = BOSS_CLASSIFICATION_TEXTURES
	end

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

	-- Set up right-click menu using oUF dropdown pattern
	frame.menu = UFI.Dropdown.ToggleMenu
	frame:SetAttribute("unit", "target")
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("*type2", "menu")
	frame:RegisterForClicks("AnyUp")

	RegisterStateDriver(frame, "visibility", "[exists] show; hide")

	return frame
end

local function GetTargetFrame()
	return UFI_TargetFrame
end

-------------------------------------------------------------------------------
-- TARGET FRAME UPDATERS (Forward declarations - created in Initialize)
-------------------------------------------------------------------------------

local UpdateTargetHealth
local UpdateTargetPower
local UpdateTargetPortrait
local UpdateTargetName
local UpdateTargetLevel
local UpdateTargetClassification
local UpdateTargetComboPoints
local UpdateTargetAuras

-------------------------------------------------------------------------------
-- TARGET FRAME CLASSIFICATION UPDATE
-------------------------------------------------------------------------------

-- Custom classification update for rogue/druid texture swapping
local function PerformTargetClassificationUpdate(frame)
	frame = frame or UFI_TargetFrame
	if not frame then
		return
	end
	local profile = GetFrameProfile(frame)
	if not profile then
		return
	end
	local unit = profile.unit or "target"
	if not UnitExists(unit) then
		return
	end
	local classification = UnitClassification(unit) or "normal"
	local _, playerClass = UnitClass("player")
	local form = GetShapeshiftForm() or 0
	local useRogue = (playerClass == "ROGUE") or (playerClass == "DRUID" and form == 3)
	local function ResolveBasePath(isRogueVariant, classKey)
		classKey = string.lower(classKey or "normal")
		if classKey == "worldboss" then
			classKey = "elite"
		end
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
		profile.classificationTextures = rogueVariant and ROGUE_BOSS_CLASSIFICATION_TEXTURES
			or BOSS_CLASSIFICATION_TEXTURES
	end
	UpdateClassificationOverlay(frame)
	UpdateTargetPortrait()
end

-------------------------------------------------------------------------------
-- TARGET FRAME COMBO POINTS UPDATE
-------------------------------------------------------------------------------

-- Update combo points display on target frame
local function PerformTargetComboPointsUpdate()
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
		if not r then
			r, g, b = 1, 1, 0
		end
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
-- TARGET FRAME AURAS UPDATE
-------------------------------------------------------------------------------

local function PerformTargetAurasUpdate()
	UpdateUnitAuras("target", UFI_TargetFrame, true)
end

-------------------------------------------------------------------------------
-- TARGET CHANGED EVENT HANDLER
-------------------------------------------------------------------------------

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
	-- Note: UpdatePlayerThreat() is called from main file's event handler
	UpdateTargetComboPoints()
end

-------------------------------------------------------------------------------
-- MODULE INITIALIZATION
-------------------------------------------------------------------------------

function TargetFrameModule.Initialize(deps)
	-- Inject dependencies
	UnitFrameFactory = deps.UnitFrameFactory
	CreateCastBar = deps.CreateCastBar
	RefreshCastBar = deps.RefreshCastBar
	UpdateUnitAuras = deps.UpdateUnitAuras
	UpdateTargetOfTarget = deps.UpdateTargetOfTarget
	FRAME_TEXTURES = deps.FRAME_TEXTURES
	ROGUE_FRAME_TEXTURES = deps.ROGUE_FRAME_TEXTURES
	BOSS_CLASSIFICATION_TEXTURES = deps.BOSS_CLASSIFICATION_TEXTURES
	ROGUE_BOSS_CLASSIFICATION_TEXTURES = deps.ROGUE_BOSS_CLASSIFICATION_TEXTURES
	Layout = deps.Layout
	UFI_LAYOUT = Layout.DATA
	LayoutResolveRect = Layout.ResolveRect
	-- Note: SecureUnitButton_OnLoad is accessed as Blizzard global, not injected
	CreateFontString = deps.Utils.CreateFontString

	-- Cache factory functions
	CreateUnitFrame = UnitFrameFactory.CreateUnitFrame
	ApplyUnitFrameProfileDefaults = UnitFrameFactory.ApplyUnitFrameProfileDefaults
	AttachStatusIndicator = UnitFrameFactory.AttachStatusIndicator
	AttachClassificationOverlay = UnitFrameFactory.AttachClassificationOverlay
	AttachAuraContainers = UnitFrameFactory.AttachAuraContainers
	UpdateUnitFrameHealth = UnitFrameFactory.UpdateUnitFrameHealth
	UpdateUnitFramePower = UnitFrameFactory.UpdateUnitFramePower
	UpdateUnitFramePortrait = UnitFrameFactory.UpdateUnitFramePortrait
	UpdateUnitFrameName = UnitFrameFactory.UpdateUnitFrameName
	UpdateUnitFrameLevel = UnitFrameFactory.UpdateUnitFrameLevel
	UpdateClassificationOverlay = UnitFrameFactory.UpdateClassificationOverlay
	GetFrameProfile = UnitFrameFactory.GetFrameProfile

	-- Create updater wrappers (must be done after dependencies are injected)
	UpdateTargetHealth = UnitFrameFactory.MakeUnitFrameUpdater(GetTargetFrame, UpdateUnitFrameHealth)
	UpdateTargetPower = UnitFrameFactory.MakeUnitFrameUpdater(GetTargetFrame, UpdateUnitFramePower)
	UpdateTargetPortrait = UnitFrameFactory.MakeUnitFrameUpdater(GetTargetFrame, UpdateUnitFramePortrait)
	UpdateTargetName = UnitFrameFactory.MakeUnitFrameUpdater(GetTargetFrame, UpdateUnitFrameName)
	UpdateTargetLevel = UnitFrameFactory.MakeUnitFrameUpdater(GetTargetFrame, UpdateUnitFrameLevel)
	UpdateTargetClassification = PerformTargetClassificationUpdate
	UpdateTargetComboPoints = PerformTargetComboPointsUpdate
	UpdateTargetAuras = PerformTargetAurasUpdate

	-- Export updaters globally for event handlers (after they're created)
	_G.UFI_UpdateTargetHealth = UpdateTargetHealth
	_G.UFI_UpdateTargetPower = UpdateTargetPower
	_G.UFI_UpdateTargetPortrait = UpdateTargetPortrait
	_G.UFI_UpdateTargetName = UpdateTargetName
	_G.UFI_UpdateTargetLevel = UpdateTargetLevel
	_G.UFI_UpdateTargetClassification = UpdateTargetClassification
	_G.UFI_UpdateTargetComboPoints = UpdateTargetComboPoints
	_G.UFI_UpdateTargetAuras = UpdateTargetAuras
	_G.UFI_HandlePlayerTargetChanged = HandlePlayerTargetChanged
end

-- Export functions
TargetFrameModule.CreateTargetFrame = CreateTargetFrame
TargetFrameModule.GetTargetFrame = GetTargetFrame
TargetFrameModule.HandlePlayerTargetChanged = HandlePlayerTargetChanged
