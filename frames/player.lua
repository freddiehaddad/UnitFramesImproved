--[[----------------------------------------------------------------------------
	UnitFramesImproved - Player Frame
	
	Creates and manages the player unit frame.
	
	Dependencies:
	- UnitFrameFactory (CreateUnitFrame, ApplyUnitFrameProfileDefaults, etc.)
	- Utils (CreateAuraRow)
	- Config (FRAME_TEXTURES, PLAYER_TEXTURE_COLORS, SELF_BUFF_EXCLUSIONS)
------------------------------------------------------------------------------]]

---@diagnostic disable: undefined-global

local UFI = UnitFramesImproved
local PlayerFrameModule = {}
UFI.PlayerFrame = PlayerFrameModule

-- Dependencies (injected via Initialize)
local UnitFrameFactory
local Utils
local FRAME_TEXTURES
local PLAYER_TEXTURE_COLORS
local SELF_BUFF_EXCLUSIONS

-- Local references to factory functions
local CreateUnitFrame
local ApplyUnitFrameProfileDefaults
local MakeUnitFrameUpdater
local UpdateUnitFrameHealth
local UpdateUnitFramePower
local UpdateUnitFramePortrait
local UpdateUnitFrameName

-- Forward declarations
local GetPlayerFrame
local CreatePlayerFrame
local UpdatePlayerLevel
local UpdatePlayerHealth
local UpdatePlayerPower
local UpdatePlayerPortrait
local UpdatePlayerName

-------------------------------------------------------------------------------
-- FRAME ACCESSOR
-------------------------------------------------------------------------------

GetPlayerFrame = function()
	return UFI_PlayerFrame
end

-------------------------------------------------------------------------------
-- PLAYER FRAME CREATION
-------------------------------------------------------------------------------

CreatePlayerFrame = function()
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
	frame.selfBuffs = Utils.CreateAuraRow(frame, {
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

	-- Set up right-click menu using oUF dropdown pattern
	frame.menu = UFI.Dropdown.ToggleMenu
	frame:SetAttribute("unit", "player")
	frame:SetAttribute("*type1", "target")
	frame:SetAttribute("*type2", "menu")
	frame:RegisterForClicks("AnyUp")

	frame:Show()
	return frame
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

		local isPlayerAura = (caster == "player" or caster == "pet" or caster == "vehicle")
		local isNotExcluded = not SELF_BUFF_EXCLUSIONS[spellId]
		local isShortDuration = (duration and duration > 0 and duration <= 120)

		if isPlayerAura and isNotExcluded and isShortDuration then
			shown = shown + 1
			if shown > iconCount then
				break
			end

			local iconFrame = icons[shown]
			iconFrame.icon:SetTexture(icon)

			if count and count > 1 then
				iconFrame.count:SetText(count)
				iconFrame.count:Show()
			else
				iconFrame.count:Hide()
			end

			if duration and duration > 0 then
				CooldownFrame_Set(iconFrame.cooldown, expirationTime - duration, duration, 1)
				iconFrame.cooldown:Show()
			else
				iconFrame.cooldown:Hide()
			end

			iconFrame:Show()
		end
	end
end

-------------------------------------------------------------------------------
-- MODULE INITIALIZATION
-------------------------------------------------------------------------------

function PlayerFrameModule.Initialize(deps)
	-- Inject dependencies
	UnitFrameFactory = deps.UnitFrameFactory
	Utils = deps.Utils
	FRAME_TEXTURES = deps.FRAME_TEXTURES
	PLAYER_TEXTURE_COLORS = deps.PLAYER_TEXTURE_COLORS
	SELF_BUFF_EXCLUSIONS = deps.SELF_BUFF_EXCLUSIONS

	-- Extract factory functions
	CreateUnitFrame = UnitFrameFactory.CreateUnitFrame
	ApplyUnitFrameProfileDefaults = UnitFrameFactory.ApplyUnitFrameProfileDefaults
	MakeUnitFrameUpdater = UnitFrameFactory.MakeUnitFrameUpdater
	UpdateUnitFrameHealth = UnitFrameFactory.UpdateUnitFrameHealth
	UpdateUnitFramePower = UnitFrameFactory.UpdateUnitFramePower
	UpdateUnitFramePortrait = UnitFrameFactory.UpdateUnitFramePortrait
	UpdateUnitFrameName = UnitFrameFactory.UpdateUnitFrameName

	-- Create updater functions now that MakeUnitFrameUpdater is available
	UpdatePlayerHealth = MakeUnitFrameUpdater(GetPlayerFrame, UpdateUnitFrameHealth)
	UpdatePlayerPower = MakeUnitFrameUpdater(GetPlayerFrame, UpdateUnitFramePower)
	UpdatePlayerPortrait = MakeUnitFrameUpdater(GetPlayerFrame, UpdateUnitFramePortrait)
	UpdatePlayerName = MakeUnitFrameUpdater(GetPlayerFrame, UpdateUnitFrameName)

	-- Export to module namespace
	PlayerFrameModule.UpdatePlayerHealth = UpdatePlayerHealth
	PlayerFrameModule.UpdatePlayerPower = UpdatePlayerPower
	PlayerFrameModule.UpdatePlayerPortrait = UpdatePlayerPortrait
	PlayerFrameModule.UpdatePlayerName = UpdatePlayerName
	PlayerFrameModule.UpdatePlayerLevel = UpdatePlayerLevel
	PlayerFrameModule.UpdatePlayerThreat = UpdatePlayerThreat
	PlayerFrameModule.UpdatePlayerAuras = UpdatePlayerAuras

	-- Export to global namespace for event handlers
	_G.UFI_GetPlayerFrame = GetPlayerFrame
	_G.UFI_CreatePlayerFrame = CreatePlayerFrame
	_G.UFI_UpdatePlayerHealth = UpdatePlayerHealth
	_G.UFI_UpdatePlayerPower = UpdatePlayerPower
	_G.UFI_UpdatePlayerPortrait = UpdatePlayerPortrait
	_G.UFI_UpdatePlayerName = UpdatePlayerName
	_G.UFI_UpdatePlayerLevel = UpdatePlayerLevel
	_G.UFI_UpdatePlayerThreat = UpdatePlayerThreat
	_G.UFI_UpdatePlayerAuras = UpdatePlayerAuras
end

-------------------------------------------------------------------------------
-- MODULE EXPORTS
-------------------------------------------------------------------------------

PlayerFrameModule.GetPlayerFrame = GetPlayerFrame
PlayerFrameModule.CreatePlayerFrame = CreatePlayerFrame
-- Note: Update functions are exported in Initialize() after they're created
