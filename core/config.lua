--[[
	UnitFramesImproved - Configuration Tables
	Provides: Texture paths, config tables, exclusion lists
]]

---@diagnostic disable: undefined-global

local UFI = UnitFramesImproved

-------------------------------------------------------------------------------
-- TEXTURE PATHS
-------------------------------------------------------------------------------

-- Central lookup for base frame textures keyed by classification.
UFI.FRAME_TEXTURES = {
	default = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame",
	player = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare",
	elite = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Elite",
	rare = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare",
	rareElite = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare-Elite",
}

-- Rogue variant textures (root-level BLPs only) mapped by classification key
UFI.ROGUE_FRAME_TEXTURES = {
	default = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-RogueTargetingFrame",
	player = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-RogueTargetingFrame-Rare",
	elite = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-RogueTargetingFrame-Elite",
	rare = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-RogueTargetingFrame-Rare",
	rareElite = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-RogueTargetingFrame-Rare-Elite",
}

-- Alternate vertex colors applied to the player frame under specific states.
UFI.PLAYER_TEXTURE_COLORS = {
	normal = { r = 1, g = 1, b = 1 },
	threat = { r = 1, g = 0.3, b = 0.3 },
}

-------------------------------------------------------------------------------
-- BOSS FRAME CONFIGURATION
-------------------------------------------------------------------------------

-- Boss classification texture mapping (worldboss, elite, rare, rareelite)
UFI.BOSS_CLASSIFICATION_TEXTURES = {
	worldboss = UFI.FRAME_TEXTURES.elite,
	elite = UFI.FRAME_TEXTURES.elite,
	rare = UFI.FRAME_TEXTURES.rare,
	rareelite = UFI.FRAME_TEXTURES.rareElite,
}

UFI.ROGUE_BOSS_CLASSIFICATION_TEXTURES = {
	worldboss = UFI.ROGUE_FRAME_TEXTURES.elite,
	elite = UFI.ROGUE_FRAME_TEXTURES.elite,
	rare = UFI.ROGUE_FRAME_TEXTURES.rare,
	rareelite = UFI.ROGUE_FRAME_TEXTURES.rareElite,
}

-------------------------------------------------------------------------------
-- BUFF/DEBUFF EXCLUSIONS
-------------------------------------------------------------------------------

-- Self-cast buffs to exclude from the player frame's self-buff display
UFI.SELF_BUFF_EXCLUSIONS = {
	[72221] = true, -- Luck of the Draw
	[91769] = true, -- Keeper's Scroll: Steadfast
	[91794] = true,
	[91796] = true,
	[91803] = true, -- Keeper's Scroll: Ghost Runner
	[91810] = true, -- Keeper's Scroll: Gathering Speed
	[91814] = true,
	[170021] = true,
	[498752] = true,
	[984540] = true, -- Dread Harvest Golem's Raven Familiar
	[993943] = true, -- Titan Scroll: Norgannon
	[993955] = true, -- Titan Scroll: Khaz'goroth
	[993957] = true, -- Titan Scroll: Eonar
	[993959] = true, -- Titan Scroll: Aggramar
	[993961] = true, -- Titan Scroll: Golganneth
	[997615] = true, -- Resting
	[997616] = true, -- Well Rested
	[9930942] = true, -- Potion of Repuation
	[9931032] = true,
}

-------------------------------------------------------------------------------
-- RAID TARGET ICONS
-------------------------------------------------------------------------------

-- Precomputed raid target dropdown entries with colorized labels.
UFI.RAID_TARGET_ICON_OPTIONS = {
	{ name = RAID_TARGET_1, index = 1, r = 1.0, g = 1.0, b = 0.0 },
	{ name = RAID_TARGET_2, index = 2, r = 1.0, g = 0.5, b = 0.0 },
	{ name = RAID_TARGET_3, index = 3, r = 0.6, g = 0.4, b = 1.0 },
	{ name = RAID_TARGET_4, index = 4, r = 0.0, g = 1.0, b = 0.0 },
	{ name = RAID_TARGET_5, index = 5, r = 0.7, g = 0.7, b = 0.7 },
	{ name = RAID_TARGET_6, index = 6, r = 0.0, g = 0.5, b = 1.0 },
	{ name = RAID_TARGET_7, index = 7, r = 1.0, g = 0.0, b = 0.0 },
	{ name = RAID_TARGET_8, index = 8, r = 1.0, g = 1.0, b = 1.0 },
}
