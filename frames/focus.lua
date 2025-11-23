--[[----------------------------------------------------------------------------
	UnitFramesImproved - Focus Frame
	
	Creates and manages the focus unit frame.
	
	Dependencies:
	- UnitFrameFactory (CreateUnitFrame, ApplyUnitFrameProfileDefaults, etc.)
	- CastBar (CreateCastBar)
------------------------------------------------------------------------------]]

---@diagnostic disable: undefined-global

local UFI = UnitFramesImproved
local FocusFrame = {}
UFI.FocusFrame = FocusFrame

-- Dependencies (injected via Initialize)
local UnitFrameFactory
local CreateCastBar
local RefreshCastBar
local UpdateUnitAuras
local FRAME_TEXTURES
local BOSS_CLASSIFICATION_TEXTURES

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

	-- Set up right-click menu using oUF dropdown pattern
	frame.menu = UFI.Dropdown.ToggleMenu
	frame:SetAttribute("unit", "focus")
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("*type2", "menu")
	frame:RegisterForClicks("AnyUp")

	RegisterStateDriver(frame, "visibility", "[target=focus,exists,nodead] show; hide")

	return frame
end

local function GetFocusFrame()
	return UFI_FocusFrame
end

-------------------------------------------------------------------------------
-- FOCUS FRAME UPDATERS (Forward declarations - created in Initialize)
-------------------------------------------------------------------------------

local UpdateFocusHealth
local UpdateFocusPower
local UpdateFocusPortrait
local UpdateFocusName
local UpdateFocusLevel
local UpdateFocusClassification
local UpdateFocusAuras

-------------------------------------------------------------------------------
-- FOCUS FRAME UPDATE
-------------------------------------------------------------------------------

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
-- MODULE INITIALIZATION
-------------------------------------------------------------------------------

function FocusFrame.Initialize(deps)
	-- Inject dependencies
	UnitFrameFactory = deps.UnitFrameFactory
	CreateCastBar = deps.CreateCastBar
	RefreshCastBar = deps.RefreshCastBar
	UpdateUnitAuras = deps.UpdateUnitAuras
	FRAME_TEXTURES = deps.FRAME_TEXTURES
	BOSS_CLASSIFICATION_TEXTURES = deps.BOSS_CLASSIFICATION_TEXTURES

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

	-- Create updater wrappers (must be done after dependencies are injected)
	UpdateFocusHealth = UnitFrameFactory.MakeUnitFrameUpdater(GetFocusFrame, UpdateUnitFrameHealth)
	UpdateFocusPower = UnitFrameFactory.MakeUnitFrameUpdater(GetFocusFrame, UpdateUnitFramePower)
	UpdateFocusPortrait = UnitFrameFactory.MakeUnitFrameUpdater(GetFocusFrame, UpdateUnitFramePortrait)
	UpdateFocusName = UnitFrameFactory.MakeUnitFrameUpdater(GetFocusFrame, UpdateUnitFrameName)
	UpdateFocusLevel = UnitFrameFactory.MakeUnitFrameUpdater(GetFocusFrame, UpdateUnitFrameLevel)
	UpdateFocusClassification = UnitFrameFactory.MakeUnitFrameUpdater(GetFocusFrame, UpdateClassificationOverlay)
	UpdateFocusAuras = UnitFrameFactory.MakeUnitFrameUpdater(GetFocusFrame, function(frame)
		UpdateUnitAuras("focus", frame)
	end)

	-- Export updaters globally for event handlers (after they're created)
	_G.UFI_UpdateFocusHealth = UpdateFocusHealth
	_G.UFI_UpdateFocusPower = UpdateFocusPower
	_G.UFI_UpdateFocusPortrait = UpdateFocusPortrait
	_G.UFI_UpdateFocusName = UpdateFocusName
	_G.UFI_UpdateFocusLevel = UpdateFocusLevel
	_G.UFI_UpdateFocusClassification = UpdateFocusClassification
	_G.UFI_UpdateFocusAuras = UpdateFocusAuras
	_G.UFI_UpdateFocusFrame = UpdateFocusFrame
end

-------------------------------------------------------------------------------
-- FOCUS EVENT HANDLER
-------------------------------------------------------------------------------

local function HandlePlayerFocusChanged()
	UpdateFocusFrame()
	RefreshCastBar("focus")
end

-------------------------------------------------------------------------------
-- MODULE EXPORTS
-------------------------------------------------------------------------------

-- Export functions
FocusFrame.CreateFocusFrame = CreateFocusFrame
FocusFrame.GetFocusFrame = GetFocusFrame
FocusFrame.UpdateFocusFrame = UpdateFocusFrame

-- Export event handler
FocusFrame.HandlePlayerFocusChanged = HandlePlayerFocusChanged
_G.UFI_HandlePlayerFocusChanged = HandlePlayerFocusChanged
