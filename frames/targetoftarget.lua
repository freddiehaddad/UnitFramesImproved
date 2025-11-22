--[[----------------------------------------------------------------------------
	UnitFramesImproved - Target of Target Frame
	
	Creates and manages the target-of-target unit frame, including visibility
	driver system that respects Blizzard's showTargetOfTarget and 
	targetOfTargetMode CVars with combat fallback handling.
	
	Dependencies:
	- UnitFrameFactory (CreateUnitFrame, ApplyUnitFrameProfileDefaults, etc.)
------------------------------------------------------------------------------]]

---@diagnostic disable: undefined-global

local UFI = UnitFramesImproved
local TargetOfTargetFrame = {}
UFI.TargetOfTargetFrame = TargetOfTargetFrame

-- Dependencies (injected via Initialize)
local UnitFrameFactory
local CreateUnitFrame
local ApplyUnitFrameProfileDefaults
local UpdateUnitFrameHealth
local UpdateUnitFramePower
local UpdateUnitFramePortrait
local UpdateUnitFrameName
local UpdateUnitFrameLevel

-------------------------------------------------------------------------------
-- MODULE STATE - Visibility Driver System
-------------------------------------------------------------------------------

local targetOfTargetVisibilityDriver = nil
local targetOfTargetDriverActive = false
local pendingTargetOfTargetDriver = nil
local pendingTargetOfTargetDriverActivation = false

-------------------------------------------------------------------------------
-- TARGET OF TARGET FRAME CREATION
-------------------------------------------------------------------------------

local function CreateTargetOfTargetFrame()
	local frame = CreateUnitFrame({
		name = "UFI_TargetOfTargetFrame",
		unit = "targettarget",
		mirrored = true,
		frameLevel = 25,
		frameStrata = "LOW",
		textStyles = {
			name = { y = 6, size = 20, flags = "OUTLINE", drawLayer = 7 },
			health = false,
			power = false,
		},
	})

	frame:SetFrameLevel(25)
	frame.visualLayer:SetFrameLevel(25)

	frame:SetAttribute("unit", "targettarget")
	frame:SetAttribute("type1", "target")

	ApplyUnitFrameProfileDefaults(frame, {
		power = { hideTextWhenNoPower = true },
		level = { colorByPlayerDiff = true },
	})

	frame:Hide()

	return frame
end

local function GetTargetOfTargetFrame()
	return UFI_TargetOfTargetFrame
end

-------------------------------------------------------------------------------
-- VISIBILITY DRIVER SYSTEM
-------------------------------------------------------------------------------

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

-------------------------------------------------------------------------------
-- TARGET OF TARGET UPDATERS (Forward declarations - created in Initialize)
-------------------------------------------------------------------------------

local UpdateTargetOfTargetHealth
local UpdateTargetOfTargetPower
local UpdateTargetOfTargetPortrait
local UpdateTargetOfTargetName
local UpdateTargetOfTargetLevel

-------------------------------------------------------------------------------
-- TARGET OF TARGET UPDATE
-------------------------------------------------------------------------------

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
-- MODULE INITIALIZATION
-------------------------------------------------------------------------------

function TargetOfTargetFrame.Initialize(deps)
	-- Inject dependencies
	UnitFrameFactory = deps.UnitFrameFactory
	
	-- Cache factory functions
	CreateUnitFrame = UnitFrameFactory.CreateUnitFrame
	ApplyUnitFrameProfileDefaults = UnitFrameFactory.ApplyUnitFrameProfileDefaults
	UpdateUnitFrameHealth = UnitFrameFactory.UpdateUnitFrameHealth
	UpdateUnitFramePower = UnitFrameFactory.UpdateUnitFramePower
	UpdateUnitFramePortrait = UnitFrameFactory.UpdateUnitFramePortrait
	UpdateUnitFrameName = UnitFrameFactory.UpdateUnitFrameName
	UpdateUnitFrameLevel = UnitFrameFactory.UpdateUnitFrameLevel
	
	-- Create updater wrappers (must be done after dependencies are injected)
	UpdateTargetOfTargetHealth = UnitFrameFactory.MakeUnitFrameUpdater(GetTargetOfTargetFrame, UpdateUnitFrameHealth)
	UpdateTargetOfTargetPower = UnitFrameFactory.MakeUnitFrameUpdater(GetTargetOfTargetFrame, UpdateUnitFramePower)
	UpdateTargetOfTargetPortrait = UnitFrameFactory.MakeUnitFrameUpdater(GetTargetOfTargetFrame, UpdateUnitFramePortrait)
	UpdateTargetOfTargetName = UnitFrameFactory.MakeUnitFrameUpdater(GetTargetOfTargetFrame, UpdateUnitFrameName)
	UpdateTargetOfTargetLevel = UnitFrameFactory.MakeUnitFrameUpdater(GetTargetOfTargetFrame, UpdateUnitFrameLevel)
	
	-- Export updaters globally for event handlers (after they're created)
	_G.UFI_UpdateTargetOfTargetHealth = UpdateTargetOfTargetHealth
	_G.UFI_UpdateTargetOfTargetPower = UpdateTargetOfTargetPower
	_G.UFI_UpdateTargetOfTargetPortrait = UpdateTargetOfTargetPortrait
	_G.UFI_UpdateTargetOfTargetName = UpdateTargetOfTargetName
	_G.UFI_UpdateTargetOfTargetLevel = UpdateTargetOfTargetLevel
	_G.UFI_UpdateTargetOfTarget = UpdateTargetOfTarget
end

-------------------------------------------------------------------------------
-- TARGET OF TARGET EVENT HANDLERS
-------------------------------------------------------------------------------

local function HandleRosterEvent()
	ApplyTargetOfTargetVisibilityDriver()
	UpdateTargetOfTarget()
end

local function HandleUnitTargetEvent(_, unit)
	if unit == "target" then
		UpdateTargetOfTarget()
	end
end

-------------------------------------------------------------------------------
-- MODULE EXPORTS
-------------------------------------------------------------------------------

-- Export functions
TargetOfTargetFrame.CreateTargetOfTargetFrame = CreateTargetOfTargetFrame
TargetOfTargetFrame.GetTargetOfTargetFrame = GetTargetOfTargetFrame
TargetOfTargetFrame.UpdateTargetOfTarget = UpdateTargetOfTarget
TargetOfTargetFrame.ApplyTargetOfTargetVisibilityDriver = ApplyTargetOfTargetVisibilityDriver
TargetOfTargetFrame.ShouldShowTargetOfTarget = ShouldShowTargetOfTarget

-- Export event handlers
TargetOfTargetFrame.HandleRosterEvent = HandleRosterEvent
TargetOfTargetFrame.HandleUnitTargetEvent = HandleUnitTargetEvent
_G.UFI_HandleRosterEvent = HandleRosterEvent
_G.UFI_HandleUnitTargetEvent = HandleUnitTargetEvent
