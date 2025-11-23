--[[
	UnitFramesImproved - Custom Unit Frames for WotLK
	
	This addon creates completely custom unit frames independent of Blizzard's
	default frames to avoid taint issues while providing enhanced visuals.
]]

---@diagnostic disable: undefined-global

-------------------------------------------------------------------------------
-- ADDON NAMESPACE REFERENCE
-------------------------------------------------------------------------------

local UFI = UnitFramesImproved

-------------------------------------------------------------------------------
-- ADDON INITIALIZATION
-------------------------------------------------------------------------------

-- Layout module references from core/layout.lua
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

local NAME_TEXT_COLOR_R, NAME_TEXT_COLOR_G, NAME_TEXT_COLOR_B =
	UFI.NAME_TEXT_COLOR_R, UFI.NAME_TEXT_COLOR_G, UFI.NAME_TEXT_COLOR_B

local MAX_BOSS_FRAMES = MAX_BOSS_FRAMES or 4
local DEFAULT_BOSS_FRAME_SCALE = Layout.DEFAULT_BOSS_FRAME_SCALE
local DEFAULT_FRAME_SCALES = Layout.DEFAULT_FRAME_SCALES

-- Player frames module references (will be initialized after Auras module)
local PlayerFrameModule
local CreatePlayerFrame
local GetPlayerFrame
local UpdatePlayerHealth
local UpdatePlayerPower
local UpdatePlayerPortrait
local UpdatePlayerName
local UpdatePlayerLevel
local UpdatePlayerAuras
local UpdatePlayerThreat

-- Utility function references from common/utils.lua (only frequently used ones)
local Utils = UFI.Utils
local CreateStatusBar = Utils.CreateStatusBar
local CreateFontString = Utils.CreateFontString
local CreatePortrait = Utils.CreatePortrait

--[[
Pixel Alignment Validation
- Temporarily enable a 1:1 UI scale with `/console UIScale 1` and reload to avoid filtering.
- Use the `/ufi unlock` overlay to confirm bars and portraits line up against the art cutouts.
- Toggle `ProjectedTextures` and inspect the cast bars; every edge should sit on whole pixels without shimmering.
- Restore your preferred scale after verification.
]]

-- Config table references from core/config.lua
local FRAME_TEXTURES = UFI.FRAME_TEXTURES
local ROGUE_FRAME_TEXTURES = UFI.ROGUE_FRAME_TEXTURES
local PLAYER_TEXTURE_COLORS = UFI.PLAYER_TEXTURE_COLORS

local ADDON_VERSION = UFI.VERSION
local DB_SCHEMA_VERSION = UFI.DB_SCHEMA_VERSION

-- Calculate boss frame stride (depends on layout data loaded earlier)
local BOSS_FRAME_STRIDE = UFI_LAYOUT.Art.height + UFI_LAYOUT.CastBar.OffsetY + 40
local BOSS_CLASSIFICATION_TEXTURES = UFI.BOSS_CLASSIFICATION_TEXTURES
local ROGUE_BOSS_CLASSIFICATION_TEXTURES = UFI.ROGUE_BOSS_CLASSIFICATION_TEXTURES

-- Boss frames module references (will be initialized after CastBar module)
local BossFrames
local IsBossUnit
local CreateBossFrames
local UpdateBossFrame
local UpdateAllBossFrames

local SELF_BUFF_EXCLUSIONS = UFI.SELF_BUFF_EXCLUSIONS

-- Positioning module reference (will be initialized after UpdatePlayerLevel is defined)
local Positioning = UFI.Positioning
local InitializeFramePosition
local CreateOverlay
local OnCombatStart
local OnCombatEnd
local SaveAllPositions

-------------------------------------------------------------------------------
-- UNIT FRAME FACTORY MODULE INITIALIZATION
-------------------------------------------------------------------------------

-- Initialize the unit frame factory module with dependencies
UFI.UnitFrame.Initialize({
	Utils = Utils,
	Layout = Layout,
	UFI_LAYOUT = UFI_LAYOUT,
	LayoutResolveRect = LayoutResolveRect,
	CreateStatusBar = CreateStatusBar,
	CreateFontString = CreateFontString,
	CreatePortrait = CreatePortrait,
	FRAME_TEXTURES = FRAME_TEXTURES,
	BOSS_CLASSIFICATION_TEXTURES = BOSS_CLASSIFICATION_TEXTURES,
	NAME_TEXT_COLOR_R = NAME_TEXT_COLOR_R,
	NAME_TEXT_COLOR_G = NAME_TEXT_COLOR_G,
	NAME_TEXT_COLOR_B = NAME_TEXT_COLOR_B,
	InitializeFramePosition = function(...)
		return Positioning.InitializeFramePosition(...)
	end,
})

-- Create local references to unit frame factory functions
local UnitFrameFactory = UFI.UnitFrame
local CreateUnitFrame = UnitFrameFactory.CreateUnitFrame
local ApplyUnitFrameProfileDefaults = UnitFrameFactory.ApplyUnitFrameProfileDefaults
local AttachStatusIndicator = UnitFrameFactory.AttachStatusIndicator
local AttachClassificationOverlay = UnitFrameFactory.AttachClassificationOverlay
local AttachAuraContainers = UnitFrameFactory.AttachAuraContainers
local MakeUnitFrameUpdater = UnitFrameFactory.MakeUnitFrameUpdater
local GetFrameProfile = UnitFrameFactory.GetFrameProfile
local ResolveProfileUnit = UnitFrameFactory.ResolveProfileUnit
local ApplyLevelColorByDiff = UnitFrameFactory.ApplyLevelColorByDiff
local UpdateUnitFrameHealth = UnitFrameFactory.UpdateUnitFrameHealth
local UpdateUnitFramePower = UnitFrameFactory.UpdateUnitFramePower
local UpdateUnitFrameName = UnitFrameFactory.UpdateUnitFrameName
local UpdateUnitFramePortrait = UnitFrameFactory.UpdateUnitFramePortrait
local UpdateUnitFrameLevel = UnitFrameFactory.UpdateUnitFrameLevel
local UpdateClassificationOverlay = UnitFrameFactory.UpdateClassificationOverlay

-------------------------------------------------------------------------------
-- AURAS MODULE INITIALIZATION
-------------------------------------------------------------------------------

-- Initialize the auras module with dependencies
UFI.Auras.Initialize({
	Utils = Utils,
})

-- Create local references to auras functions
local AurasModule = UFI.Auras
local UpdateUnitAuras = AurasModule.UpdateUnitAuras

-------------------------------------------------------------------------------
-- PLAYER FRAME MODULE INITIALIZATION
-------------------------------------------------------------------------------

-- Initialize the player frame module with dependencies
UFI.PlayerFrame.Initialize({
	UnitFrameFactory = UFI.UnitFrame,
	Utils = Utils,
	FRAME_TEXTURES = FRAME_TEXTURES,
	PLAYER_TEXTURE_COLORS = PLAYER_TEXTURE_COLORS,
	SELF_BUFF_EXCLUSIONS = SELF_BUFF_EXCLUSIONS,
})

-- Create local references to player frame functions
PlayerFrameModule = UFI.PlayerFrame
CreatePlayerFrame = PlayerFrameModule.CreatePlayerFrame
GetPlayerFrame = PlayerFrameModule.GetPlayerFrame
UpdatePlayerHealth = PlayerFrameModule.UpdatePlayerHealth
UpdatePlayerPower = PlayerFrameModule.UpdatePlayerPower
UpdatePlayerPortrait = PlayerFrameModule.UpdatePlayerPortrait
UpdatePlayerName = PlayerFrameModule.UpdatePlayerName
UpdatePlayerLevel = PlayerFrameModule.UpdatePlayerLevel
UpdatePlayerAuras = PlayerFrameModule.UpdatePlayerAuras
UpdatePlayerThreat = PlayerFrameModule.UpdatePlayerThreat

-------------------------------------------------------------------------------
-- CAST BAR MODULE INITIALIZATION
-------------------------------------------------------------------------------

-- Initialize the cast bar module with dependencies
UFI.CastBar.Initialize({
	LayoutResolveRect = LayoutResolveRect,
	UFI_LAYOUT = UFI_LAYOUT,
	STATUSBAR_TEXTURE = STATUSBAR_TEXTURE,
	FONT_DEFAULT = FONT_DEFAULT,
})

-- Create local references to cast bar functions
local CastBar = UFI.CastBar
local CreateCastBar = CastBar.CreateCastBar
local BeginCast = CastBar.BeginCast
local StopCast = CastBar.StopCast
local FailCast = CastBar.FailCast
local AdjustCastTiming = CastBar.AdjustCastTiming
local HideCastBar = CastBar.HideCastBar
local RefreshCastBar = CastBar.RefreshCastBar
local UpdateCastBar = CastBar.UpdateCastBar
local castBarsByUnit = CastBar.GetCastBarsByUnit()
local CASTBAR_STATE = CastBar.STATE

-------------------------------------------------------------------------------
-- BOSS FRAMES MODULE INITIALIZATION
-------------------------------------------------------------------------------

-- Initialize the boss frames module with dependencies
UFI.BossFrames.Initialize({
	UnitFrameFactory = UFI.UnitFrame,
	CreateCastBar = CreateCastBar,
	CASTBAR_STATE = CASTBAR_STATE,
	BOSS_CLASSIFICATION_TEXTURES = BOSS_CLASSIFICATION_TEXTURES,
	FRAME_TEXTURES = FRAME_TEXTURES,
	UFI_LAYOUT = UFI_LAYOUT,
	BOSS_FRAME_STRIDE = BOSS_FRAME_STRIDE,
	InitializeFramePosition = function(...)
		return Positioning.InitializeFramePosition(...)
	end,
})

-- Create local references to boss frames functions
BossFrames = UFI.BossFrames
IsBossUnit = BossFrames.IsBossUnit
CreateBossFrames = BossFrames.CreateBossFrames
UpdateBossFrame = BossFrames.UpdateBossFrame
UpdateAllBossFrames = BossFrames.UpdateAllBossFrames

-------------------------------------------------------------------------------
-- FOCUS FRAME MODULE INITIALIZATION
-------------------------------------------------------------------------------

-- Initialize the focus frame module with dependencies
UFI.FocusFrame.Initialize({
	UnitFrameFactory = UFI.UnitFrame,
	CreateCastBar = CreateCastBar,
	RefreshCastBar = RefreshCastBar,
	UpdateUnitAuras = UpdateUnitAuras,
	FRAME_TEXTURES = FRAME_TEXTURES,
	BOSS_CLASSIFICATION_TEXTURES = BOSS_CLASSIFICATION_TEXTURES,
})

-- Create local references to focus frame functions
local FocusFrameModule = UFI.FocusFrame
local CreateFocusFrame = FocusFrameModule.CreateFocusFrame
local GetFocusFrame = FocusFrameModule.GetFocusFrame
local UpdateFocusFrame = FocusFrameModule.UpdateFocusFrame

-------------------------------------------------------------------------------
-- TARGET OF TARGET FRAME MODULE INITIALIZATION
-------------------------------------------------------------------------------

-- Initialize the target-of-target frame module with dependencies
UFI.TargetOfTargetFrame.Initialize({
	UnitFrameFactory = UFI.UnitFrame,
})

-- Create local references to target-of-target frame functions
local TargetOfTargetFrameModule = UFI.TargetOfTargetFrame
local CreateTargetOfTargetFrame = TargetOfTargetFrameModule.CreateTargetOfTargetFrame
local GetTargetOfTargetFrame = TargetOfTargetFrameModule.GetTargetOfTargetFrame
local UpdateTargetOfTarget = TargetOfTargetFrameModule.UpdateTargetOfTarget
local ApplyTargetOfTargetVisibilityDriver = TargetOfTargetFrameModule.ApplyTargetOfTargetVisibilityDriver
local ShouldShowTargetOfTarget = TargetOfTargetFrameModule.ShouldShowTargetOfTarget

-------------------------------------------------------------------------------
-- TARGET FRAME MODULE INITIALIZATION
-------------------------------------------------------------------------------

-- Initialize the target frame module with dependencies
UFI.TargetFrame.Initialize({
	UnitFrameFactory = UFI.UnitFrame,
	CreateCastBar = CreateCastBar,
	RefreshCastBar = RefreshCastBar,
	UpdateUnitAuras = UpdateUnitAuras,
	UpdateTargetOfTarget = UpdateTargetOfTarget,
	FRAME_TEXTURES = FRAME_TEXTURES,
	ROGUE_FRAME_TEXTURES = ROGUE_FRAME_TEXTURES,
	BOSS_CLASSIFICATION_TEXTURES = BOSS_CLASSIFICATION_TEXTURES,
	ROGUE_BOSS_CLASSIFICATION_TEXTURES = ROGUE_BOSS_CLASSIFICATION_TEXTURES,
	Layout = Layout,
	Utils = Utils,
})

-- Create local references to target frame functions
local TargetFrameModule = UFI.TargetFrame
local CreateTargetFrame = TargetFrameModule.CreateTargetFrame
local GetTargetFrame = TargetFrameModule.GetTargetFrame
local HandlePlayerTargetChanged = TargetFrameModule.HandlePlayerTargetChanged

-------------------------------------------------------------------------------
-- UNIT FRAME FACTORY

-------------------------------------------------------------------------------
-- EVENT HANDLING
-------------------------------------------------------------------------------
-- POSITIONING MODULE INITIALIZATION
-------------------------------------------------------------------------------

-- Initialize the positioning module with dependencies
Positioning.Initialize({
	ADDON_VERSION = ADDON_VERSION,
	DB_SCHEMA_VERSION = DB_SCHEMA_VERSION,
	DEFAULT_FRAME_SCALES = DEFAULT_FRAME_SCALES,
	BOSS_FRAME_STRIDE = BOSS_FRAME_STRIDE,
	Utils = Utils,
})

-- Create local references to positioning functions
InitializeFramePosition = Positioning.InitializeFramePosition
CreateOverlay = Positioning.CreateOverlay
OnCombatStart = Positioning.OnCombatStart
OnCombatEnd = Positioning.OnCombatEnd
SaveAllPositions = Positioning.SaveAllPositions

-------------------------------------------------------------------------------
-- PLAYER LOGIN HANDLER
-------------------------------------------------------------------------------

local function HandlePlayerLogin()
	Positioning.InitializeDatabase()

	UFI_PlayerFrame = CreatePlayerFrame()
	UFI_TargetFrame = CreateTargetFrame()
	UFI_FocusFrame = CreateFocusFrame()
	Positioning.ApplyFocusFrameScale()
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

	Positioning.ApplyPosition("UFI_PlayerFrame")
	Positioning.ApplyPosition("UFI_TargetFrame")
	Positioning.ApplyPosition("UFI_TargetOfTargetFrame")
	Positioning.ApplyPosition("UFI_FocusFrame")
	Positioning.ApplyPosition("UFI_BossFrameAnchor")

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
			UFI_UpdatePlayerHealth()
			UFI_UpdatePlayerPower()
			if UnitExists("target") then
				UFI_UpdateTargetHealth()
				UFI_UpdateTargetPower()
			end
			if UnitExists("focus") then
				UFI_UpdateFocusHealth()
				UFI_UpdateFocusPower()
			end
			UpdateAllBossFrames()
		elseif name == "showTargetOfTarget" or name == "targetOfTargetMode" then
			ApplyTargetOfTargetVisibilityDriver()
			UFI_UpdateTargetOfTarget()
		elseif name == "fullSizeFocusFrame" then
			Positioning.ApplyFocusFrameScale()
		end
	end)

	if UnitFramesImprovedDB.isUnlocked and not InCombatLockdown() then
		Positioning.UnlockFrames()
	end

	UFI.Print(
		"|cff00ff00UnitFramesImproved v" .. ADDON_VERSION .. " loaded!|r Type |cffffcc00/ufi help|r for commands."
	)

	UFI_UpdatePlayerHealth()
	UFI_UpdatePlayerPower()
	UFI_UpdatePlayerPortrait()
	UFI_UpdatePlayerName()
	UFI_UpdatePlayerLevel()
	UFI_UpdatePlayerAuras()
	UFI_UpdatePlayerThreat()

	UFI_UpdateTargetOfTarget()

	if UnitExists("focus") then
		UFI_UpdateFocusFrame()
	end

	UpdateAllBossFrames()
end

-------------------------------------------------------------------------------
-- EVENTS MODULE INITIALIZATION
-------------------------------------------------------------------------------

-- Initialize the events module with dependencies
-- Note: This must be called AFTER all frame modules have been initialized
-- so their event handlers are exported to globals
UFI.Events.Initialize({
	HandlePlayerLogin = HandlePlayerLogin,
	OnCombatStart = OnCombatStart,
	OnCombatEnd = OnCombatEnd,
	SaveAllPositions = SaveAllPositions,
	ApplyTargetOfTargetVisibilityDriver = ApplyTargetOfTargetVisibilityDriver,
	IsBossUnit = IsBossUnit,
	UpdateAllBossFrames = UpdateAllBossFrames,
	castBarsByUnit = castBarsByUnit,
	CASTBAR_STATE = CASTBAR_STATE,
	UpdateCastBar = UpdateCastBar,
})
