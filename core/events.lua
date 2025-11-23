--[[
	Events Module - Event handling and dispatching system
	
	This module manages all WoW event registration and dispatching for the addon's
	runtime behavior (excluding initial login/startup).
]]

---@diagnostic disable: undefined-global

-------------------------------------------------------------------------------
-- MODULE NAMESPACE
-------------------------------------------------------------------------------

local UFI = UnitFramesImproved
UFI.Events = {}
local Events = UFI.Events

-------------------------------------------------------------------------------
-- DEPENDENCIES (injected via Initialize)
-------------------------------------------------------------------------------

local OnCombatStart
local OnCombatEnd
local SaveAllPositions
local ApplyTargetOfTargetVisibilityDriver
local IsBossUnit
local UpdateAllBossFrames

-------------------------------------------------------------------------------
-- EVENT FRAME
-------------------------------------------------------------------------------

local eventFrame

-------------------------------------------------------------------------------
-- RUNTIME EVENT HANDLERS
-------------------------------------------------------------------------------

local function HandlePlayerEnteringWorld()
	ApplyTargetOfTargetVisibilityDriver()
	UFI_UpdateTargetOfTarget()
	UpdateAllBossFrames()
	UFI_UpdatePlayerThreat()
end

local function HandleThreatEvent(_, unit)
	if not unit or unit == "player" then
		UFI_UpdatePlayerThreat()
	end
end

local function HandleUnitHealthEvent(_, unit)
	if unit == "player" then
		UFI_UpdatePlayerHealth()
	elseif unit == "target" then
		UFI_UpdateTargetHealth()
	elseif unit == "focus" then
		UFI_UpdateFocusHealth()
	elseif IsBossUnit(unit) then
		UFI_UpdateBossHealth(unit)
	end
end

local function HandleUnitPowerEvent(_, unit)
	if unit == "player" then
		UFI_UpdatePlayerPower()
	elseif unit == "target" then
		UFI_UpdateTargetPower()
	elseif unit == "focus" then
		UFI_UpdateFocusPower()
	elseif IsBossUnit(unit) then
		UFI_UpdateBossPower(unit)
	end

	if UnitIsUnit(unit, "targettarget") then
		UFI_UpdateTargetOfTargetPower()
	end
end

local function HandleUnitPortraitEvent(_, unit)
	if unit == "player" then
		UFI_UpdatePlayerPortrait()
	elseif unit == "target" then
		UFI_UpdateTargetPortrait()
	elseif unit == "focus" then
		UFI_UpdateFocusPortrait()
	elseif IsBossUnit(unit) then
		UFI_UpdateBossPortrait(unit)
	end
end

local function HandleUnitNameOrLevelEvent(_, unit)
	if unit == "player" then
		UFI_UpdatePlayerName()
		UFI_UpdatePlayerLevel()
	elseif unit == "target" then
		UFI_UpdateTargetName()
		UFI_UpdateTargetLevel()
		UFI_UpdateTargetClassification()
	elseif unit == "focus" then
		UFI_UpdateFocusName()
		UFI_UpdateFocusLevel()
		UFI_UpdateFocusClassification()
	elseif unit == "targettarget" then
		UFI_UpdateTargetOfTargetName()
		UFI_UpdateTargetOfTargetLevel()
	elseif IsBossUnit(unit) then
		UFI_UpdateBossName(unit)
		UFI_UpdateBossLevel(unit)
		UFI_UpdateBossClassification(unit)
	end
end

local function HandleUnitClassificationChanged(_, unit)
	if unit == "target" then
		UFI_UpdateTargetClassification()
	elseif unit == "focus" then
		UFI_UpdateFocusClassification()
	end
	if IsBossUnit(unit) then
		UFI_UpdateBossClassification(unit)
	end
end

local function HandleUnitAuraEvent(_, unit)
	if unit == "player" then
		UFI_UpdatePlayerAuras()
	elseif unit == "target" then
		UFI_UpdateTargetAuras()
	elseif unit == "focus" then
		UFI_UpdateFocusAuras()
	end
end

local function HandlePlayerUpdateResting()
	UFI_UpdatePlayerLevel()
end

local function HandlePlayerLogout()
	SaveAllPositions()
end

local function HandlePlayerRegenDisabled()
	UFI_UpdatePlayerThreat()
	UFI_UpdatePlayerLevel()
	OnCombatStart()
end

local function HandlePlayerRegenEnabled()
	UFI_UpdatePlayerThreat()
	UFI_UpdatePlayerLevel()
	OnCombatEnd()
	ApplyTargetOfTargetVisibilityDriver()
	UFI_UpdateTargetOfTarget()
	UpdateAllBossFrames()
end

-------------------------------------------------------------------------------
-- EVENT HANDLERS TABLE
-------------------------------------------------------------------------------

-- Event handler table maps WoW events to handler functions
-- Note: HandlePlayerLogin is intentionally excluded - it's called directly
-- from the main file as it contains initialization logic, not runtime behavior
local EVENT_HANDLERS

-------------------------------------------------------------------------------
-- MODULE INITIALIZATION
-------------------------------------------------------------------------------

function Events.Initialize(deps)
	-- Inject dependencies
	OnCombatStart = deps.OnCombatStart
	OnCombatEnd = deps.OnCombatEnd
	SaveAllPositions = deps.SaveAllPositions
	ApplyTargetOfTargetVisibilityDriver = deps.ApplyTargetOfTargetVisibilityDriver
	IsBossUnit = deps.IsBossUnit
	UpdateAllBossFrames = deps.UpdateAllBossFrames

	-- Note: All Update* and Handle* event handlers are exported as UFI_-prefixed globals by their
	-- respective frame modules (player, target, focus, boss, targetoftarget, castbar) during their
	-- Initialize() calls. We access them directly from _G here to avoid namespace collisions.

	-- Create event frame
	eventFrame = CreateFrame("Frame")

	-- Register all WoW events
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

	-- Build event handlers table (must be done after frame modules export their handlers to _G)
	EVENT_HANDLERS = {
		PLAYER_LOGIN = deps.HandlePlayerLogin, -- Injected from main file
		PLAYER_LOGOUT = HandlePlayerLogout,
		PLAYER_TARGET_CHANGED = UFI_HandlePlayerTargetChanged, -- From target module
		PLAYER_ENTERING_WORLD = HandlePlayerEnteringWorld,
		PLAYER_FOCUS_CHANGED = UFI_HandlePlayerFocusChanged, -- From focus module
		PLAYER_UPDATE_RESTING = HandlePlayerUpdateResting,
		PLAYER_REGEN_DISABLED = HandlePlayerRegenDisabled,
		PLAYER_REGEN_ENABLED = HandlePlayerRegenEnabled,
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
		UNIT_COMBO_POINTS = UFI_UpdateTargetComboPoints, -- From target module
		PLAYER_COMBO_POINTS = UFI_UpdateTargetComboPoints, -- From target module
		UPDATE_SHAPESHIFT_FORM = function()
			UFI_UpdateTargetClassification() -- From target module
			UFI_UpdateTargetComboPoints() -- From target module
		end,
		UNIT_AURA = HandleUnitAuraEvent,
		UNIT_TARGET = UFI_HandleUnitTargetEvent, -- From targetoftarget module
		UNIT_TARGETABLE_CHANGED = UFI_HandleUnitTargetableChanged, -- From boss module
		INSTANCE_ENCOUNTER_ENGAGE_UNIT = UFI_HandleEncounterEvent, -- From boss module
		ENCOUNTER_END = UFI_HandleEncounterEvent, -- From boss module
		PARTY_MEMBERS_CHANGED = UFI_HandleRosterEvent, -- From targetoftarget module
		RAID_ROSTER_UPDATE = UFI_HandleRosterEvent, -- From targetoftarget module
		UNIT_SPELLCAST_START = UFI_HandleSpellcastStart, -- From castbar module
		UNIT_SPELLCAST_CHANNEL_START = UFI_HandleSpellcastChannelStart, -- From castbar module
		UNIT_SPELLCAST_STOP = UFI_HandleSpellcastStop, -- From castbar module
		UNIT_SPELLCAST_CHANNEL_STOP = UFI_HandleSpellcastStop, -- From castbar module
		UNIT_SPELLCAST_FAILED = UFI_HandleSpellcastFailed, -- From castbar module
		UNIT_SPELLCAST_INTERRUPTED = UFI_HandleSpellcastInterrupted, -- From castbar module
		UNIT_SPELLCAST_DELAYED = UFI_HandleSpellcastDelayed, -- From castbar module
		UNIT_SPELLCAST_CHANNEL_UPDATE = UFI_HandleSpellcastChannelUpdate, -- From castbar module
		UNIT_SPELLCAST_INTERRUPTIBLE = UFI_HandleSpellcastInterruptible, -- From castbar module
		UNIT_SPELLCAST_NOT_INTERRUPTIBLE = UFI_HandleSpellcastNotInterruptible, -- From castbar module
	}

	-- Set up event dispatcher
	-- Table-driven dispatcher keeps the event handler list declarative and easy to audit.
	eventFrame:SetScript("OnEvent", function(_, event, ...)
		local handler = EVENT_HANDLERS[event]
		if handler then
			handler(event, ...)
		end
	end)

	-- Set up OnUpdate for cast bar polling
	-- Poll cast bars outside the event system so channel/channel updates continue during fades.
	eventFrame:SetScript("OnUpdate", function()
		for _, castBar in pairs(deps.castBarsByUnit) do
			if castBar.state ~= deps.CASTBAR_STATE.HIDDEN then
				deps.UpdateCastBar(castBar)
			end
		end
	end)
end
