--[[
	Boss Frames Module
	
	Manages all boss unit frames (boss1-boss4) including creation, updates,
	and classification handling.
]]

---@diagnostic disable: undefined-global

local UFI = UnitFramesImproved
local BossFrames = {}
UFI.BossFrames = BossFrames

---@diagnostic disable-next-line: undefined-global
local MAX_BOSS_FRAMES = MAX_BOSS_FRAMES or 4

-------------------------------------------------------------------------------
-- MODULE STATE
-------------------------------------------------------------------------------

local bossFrames = {}
local bossFramesByUnit = {}

-------------------------------------------------------------------------------
-- DEPENDENCIES (injected via Initialize)
-------------------------------------------------------------------------------

local UnitFrameFactory
local CreateUnitFrame
local ApplyUnitFrameProfileDefaults
local MakeUnitFrameUpdater
local UpdateUnitFrameHealth
local UpdateUnitFramePower
local UpdateUnitFramePortrait
local UpdateUnitFrameName
local UpdateUnitFrameLevel

local CreateCastBar
local HideCastBar

local BOSS_CLASSIFICATION_TEXTURES
local FRAME_TEXTURES
local UFI_LAYOUT
local BOSS_FRAME_STRIDE
local InitializeFramePosition

-------------------------------------------------------------------------------
-- HELPER FUNCTIONS
-------------------------------------------------------------------------------

local function IsBossUnit(unit)
	return unit ~= nil and bossFramesByUnit[unit] ~= nil
end

local function GetBossFrame(unit)
	if not unit then
		return nil
	end

	return bossFramesByUnit[unit]
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

	if frame.castBar and frame.unit then
		HideCastBar(frame.unit)
	end

	frame.currentTexture = nil
end

local function ApplyBossClassification(frame, unit)
	ApplyBossTexture(frame, UnitClassification(unit))
end

-------------------------------------------------------------------------------
-- BOSS FRAME UPDATE FUNCTIONS
-------------------------------------------------------------------------------

-- Create boss updater functions using MakeUnitFrameUpdater
local ClearBossUnitFrame
local UpdateBossHealth
local UpdateBossPower
local UpdateBossPortrait
local UpdateBossName
local UpdateBossLevel
local UpdateBossClassification

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

-------------------------------------------------------------------------------
-- BOSS FRAME CREATION
-------------------------------------------------------------------------------

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
		frame:SetAttribute("*type2", "menu")
		frame.menu = UFI.Dropdown.ToggleMenu
		frame:RegisterForClicks("AnyUp")
		RegisterUnitWatch(frame)
		frame:Hide()

		-- Add OnUpdate polling for boss frames (handles dead player updates)
		-- Based on ElvUI's enableTargetUpdate pattern - polls every 0.5s when boss exists
		frame.onUpdateFrequency = 0.5
		local elapsed = 0
		frame:SetScript("OnUpdate", function(self, delta)
			if not self.unit then
				return -- RegisterUnitWatch cleared unit - no boss exists
			end

			elapsed = elapsed + delta
			if elapsed >= self.onUpdateFrequency then
				UpdateBossFrame(self.unit)
				elapsed = 0
			end
		end)

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
-- MODULE INITIALIZATION
-------------------------------------------------------------------------------

function BossFrames.Initialize(deps)
	-- Import dependencies
	UnitFrameFactory = deps.UnitFrameFactory
	CreateUnitFrame = UnitFrameFactory.CreateUnitFrame
	ApplyUnitFrameProfileDefaults = UnitFrameFactory.ApplyUnitFrameProfileDefaults
	MakeUnitFrameUpdater = UnitFrameFactory.MakeUnitFrameUpdater
	UpdateUnitFrameHealth = UnitFrameFactory.UpdateUnitFrameHealth
	UpdateUnitFramePower = UnitFrameFactory.UpdateUnitFramePower
	UpdateUnitFramePortrait = UnitFrameFactory.UpdateUnitFramePortrait
	UpdateUnitFrameName = UnitFrameFactory.UpdateUnitFrameName
	UpdateUnitFrameLevel = UnitFrameFactory.UpdateUnitFrameLevel

	CreateCastBar = deps.CreateCastBar
	HideCastBar = deps.HideCastBar

	BOSS_CLASSIFICATION_TEXTURES = deps.BOSS_CLASSIFICATION_TEXTURES
	FRAME_TEXTURES = deps.FRAME_TEXTURES
	UFI_LAYOUT = deps.UFI_LAYOUT
	BOSS_FRAME_STRIDE = deps.BOSS_FRAME_STRIDE
	InitializeFramePosition = deps.InitializeFramePosition

	-- Create boss updater functions after dependencies are loaded
	ClearBossUnitFrame = MakeUnitFrameUpdater(GetBossFrame, ClearBossFrame)
	UpdateBossHealth = MakeUnitFrameUpdater(GetBossFrame, UpdateUnitFrameHealth)
	UpdateBossPower = MakeUnitFrameUpdater(GetBossFrame, UpdateUnitFramePower)
	UpdateBossPortrait = MakeUnitFrameUpdater(GetBossFrame, UpdateUnitFramePortrait)
	UpdateBossName = MakeUnitFrameUpdater(GetBossFrame, UpdateUnitFrameName)
	UpdateBossLevel = MakeUnitFrameUpdater(GetBossFrame, UpdateUnitFrameLevel)
	UpdateBossClassification = MakeUnitFrameUpdater(GetBossFrame, ApplyBossClassification)

	-- Export globals for event handlers
	_G.UFI_ClearBossUnitFrame = ClearBossUnitFrame
	_G.UFI_UpdateBossHealth = UpdateBossHealth
	_G.UFI_UpdateBossPower = UpdateBossPower
	_G.UFI_UpdateBossPortrait = UpdateBossPortrait
	_G.UFI_UpdateBossName = UpdateBossName
	_G.UFI_UpdateBossLevel = UpdateBossLevel
	_G.UFI_UpdateBossClassification = UpdateBossClassification
end

-------------------------------------------------------------------------------
-- BOSS EVENT HANDLERS
-------------------------------------------------------------------------------

local function HandleEncounterEvent()
	UpdateAllBossFrames()
end

local function HandleUnitTargetableChanged(_, unit)
	if IsBossUnit(unit) then
		UpdateBossFrame(unit)
	end
end

-------------------------------------------------------------------------------
-- MODULE EXPORTS
-------------------------------------------------------------------------------

BossFrames.IsBossUnit = IsBossUnit
BossFrames.GetBossFrame = GetBossFrame
BossFrames.CreateBossFrames = CreateBossFrames
BossFrames.UpdateBossFrame = UpdateBossFrame
BossFrames.UpdateAllBossFrames = UpdateAllBossFrames

-- Export event handlers
BossFrames.HandleEncounterEvent = HandleEncounterEvent
BossFrames.HandleUnitTargetableChanged = HandleUnitTargetableChanged
_G.UFI_HandleEncounterEvent = HandleEncounterEvent
_G.UFI_HandleUnitTargetableChanged = HandleUnitTargetableChanged
