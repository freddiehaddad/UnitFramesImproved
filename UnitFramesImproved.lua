--[[
	UnitFramesImproved - Custom Unit Frames for WotLK
	
	This addon creates completely custom unit frames independent of Blizzard's
	default frames to avoid taint issues while providing enhanced visuals.
]]
--

-------------------------------------------------------------------------------
-- ADDON INITIALIZATION
-------------------------------------------------------------------------------

local addonName = "UnitFramesImproved"
local UFI = {} -- Main addon namespace

-- Frame references (global for debugging)
UFI_PlayerFrame = nil

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

-------------------------------------------------------------------------------
-- PLAYER FRAME CREATION
-------------------------------------------------------------------------------

local function CreatePlayerFrame()
	-- Main frame container (Button for secure click handling)
	local frame = CreateFrame("Button", "UFI_PlayerFrame", UIParent, "SecureUnitButtonTemplate")
	frame:SetSize(232, 100)
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -19, -4) -- Default Blizzard PlayerFrame position
	frame:SetFrameStrata("MEDIUM")
	frame:SetFrameLevel(1)
	frame:SetScale(1.15) -- Slightly larger than default

	-- Health bar (BACKGROUND layer - drawn first, below frame texture)
	frame.healthBar = CreateFrame("StatusBar", nil, frame)
	frame.healthBar:SetSize(108, 24)
	frame.healthBar:SetPoint("TOPLEFT", 97, -20)
	frame.healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	frame.healthBar:GetStatusBarTexture():SetHorizTile(false)
	frame.healthBar:GetStatusBarTexture():SetVertTile(false)
	frame.healthBar:GetStatusBarTexture():SetDrawLayer("BACKGROUND", -8)
	frame.healthBar:SetMinMaxValues(0, 100)
	frame.healthBar:SetValue(100)
	frame.healthBar:SetFrameLevel(frame:GetFrameLevel() - 1)

	-- Health bar background (black with 35% opacity)
	frame.healthBarBg = frame.healthBar:CreateTexture(nil, "BACKGROUND")
	frame.healthBarBg:SetTexture(0, 0, 0, 0.35)
	frame.healthBarBg:SetAllPoints(frame.healthBar)

	-- Remove default StatusBar background
	if frame.healthBar.SetBackdrop then
		frame.healthBar:SetBackdrop(nil)
	end

	-- Mana/Power bar (BACKGROUND layer - drawn first, below frame texture)
	frame.powerBar = CreateFrame("StatusBar", nil, frame)
	frame.powerBar:SetSize(108, 9)
	frame.powerBar:SetPoint("TOPLEFT", 97, -46)
	frame.powerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	frame.powerBar:GetStatusBarTexture():SetHorizTile(false)
	frame.powerBar:GetStatusBarTexture():SetVertTile(false)
	frame.powerBar:GetStatusBarTexture():SetDrawLayer("BACKGROUND", -8)
	frame.powerBar:SetMinMaxValues(0, 100)
	frame.powerBar:SetValue(100)
	frame.powerBar:SetFrameLevel(frame:GetFrameLevel() - 1)

	-- Power bar background (black with 35% opacity)
	frame.powerBarBg = frame.powerBar:CreateTexture(nil, "BACKGROUND")
	frame.powerBarBg:SetTexture(0, 0, 0, 0.35)
	frame.powerBarBg:SetAllPoints(frame.powerBar)

	-- Remove default StatusBar background
	if frame.powerBar.SetBackdrop then
		frame.powerBar:SetBackdrop(nil)
	end

	-- Border/Background texture (BORDER layer - drawn on top of bars)
	frame.texture = frame:CreateTexture(nil, "BORDER", nil, 0)
	frame.texture:SetTexture("Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare-Elite")
	frame.texture:SetSize(232, 110)
	frame.texture:SetPoint("TOPLEFT", 0, 0)
	-- Flip texture horizontally for player frame (target frame is default orientation)
	frame.texture:SetTexCoord(1, 0, 0, 1) -- Flipped: right to left, top to bottom

	-- Portrait (2D texture - BACKGROUND layer to ensure it's always below frame texture)
	frame.portrait = frame:CreateTexture(nil, "BACKGROUND", nil, 5)
	frame.portrait:SetSize(50, 48)
	frame.portrait:SetPoint("CENTER", frame, "TOPLEFT", 68, -38)
	SetPortraitTexture(frame.portrait, "player")

	-- Make portrait circular using texture coordinates to crop it
	-- This creates a circular crop by using the center portion of the portrait
	local circularCrop = 0.08 -- Crop edges to make it more circular
	frame.portrait:SetTexCoord(circularCrop, 1 - circularCrop, circularCrop, 1 - circularCrop)

	-- Circular mask for portrait using the frame texture itself as a mask
	-- The frame texture has a circular cutout, so we draw it again on top
	frame.portraitMask = frame:CreateTexture(nil, "BORDER", nil, 5)
	frame.portraitMask:SetTexture("Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare-Elite")
	frame.portraitMask:SetSize(232, 110)
	frame.portraitMask:SetPoint("TOPLEFT", 0, 0)
	frame.portraitMask:SetTexCoord(1, 0, 0, 1) -- Same flip as main texture
	frame.portraitMask:SetBlendMode("BLEND")

	-- Level/Rest indicator text (displayed in the circular area at bottom left of portrait)
	frame.levelText = frame:CreateFontString(nil, "OVERLAY")
	frame.levelText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	frame.levelText:SetPoint("CENTER", frame, "TOPLEFT", 48, -56) -- Position in the circular area
	frame.levelText:SetTextColor(1, 0.82, 0) -- Gold color

	-- Unit name (OVERLAY layer - drawn on top of everything)
	frame.nameText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.nameText:SetPoint("CENTER", frame.healthBar, "CENTER", 0, 6)
	frame.nameText:SetText(UnitName("player"))
	frame.nameText:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")
	frame.nameText:SetDrawLayer("OVERLAY", 7)

	-- Health text (OVERLAY layer - drawn on top of everything)
	frame.healthText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.healthText:SetPoint("CENTER", frame.healthBar, "CENTER", 0, -6)
	frame.healthText:SetText("")
	frame.healthText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	frame.healthText:SetTextColor(1, 1, 1) -- White color
	frame.healthText:SetDrawLayer("OVERLAY", 7)

	-- Power text (OVERLAY layer - drawn on top of everything)
	-- Must be child of main frame, not powerBar, to render above frame texture
	frame.powerText = frame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	frame.powerText:SetPoint("CENTER", frame.powerBar, "CENTER", 0, 1)
	frame.powerText:SetText("")
	frame.powerText:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")
	frame.powerText:SetDrawLayer("OVERLAY", 7)

	-- Enable mouse clicks and set up secure click handling
	frame:EnableMouse(true)
	frame:RegisterForClicks("AnyUp")

	-- Create custom dropdown menu
	local dropdown = CreateFrame("Frame", "UFI_PlayerFrameDropDown", UIParent, "UIDropDownMenuTemplate")
	dropdown.displayMode = "MENU"
	dropdown.initialize = function(self, level)
		if not level then
			return
		end

		local info = UIDropDownMenu_CreateInfo()

		-- Level 1: Main menu
		if level == 1 then
			-- Title - Player name in gold
			info.text = UnitName("player")
			info.isTitle = true
			info.notCheckable = true
			UIDropDownMenu_AddButton(info, level)

			-- Dungeon Difficulty submenu
			info = UIDropDownMenu_CreateInfo()
			info.text = DUNGEON_DIFFICULTY
			info.notCheckable = true
			info.hasArrow = true
			info.value = "DUNGEON_DIFFICULTY"
			UIDropDownMenu_AddButton(info, level)

			-- Raid Difficulty submenu
			info = UIDropDownMenu_CreateInfo()
			info.text = RAID_DIFFICULTY
			info.notCheckable = true
			info.hasArrow = true
			info.value = "RAID_DIFFICULTY"
			UIDropDownMenu_AddButton(info, level)

			-- Reset Instances submenu
			info = UIDropDownMenu_CreateInfo()
			info.text = RESET_INSTANCES
			info.notCheckable = true
			info.hasArrow = true
			info.value = "RESET_INSTANCES"
			UIDropDownMenu_AddButton(info, level)

			-- Raid Target Icon submenu
			info = UIDropDownMenu_CreateInfo()
			info.text = RAID_TARGET_ICON
			info.notCheckable = true
			info.hasArrow = true
			info.value = "RAID_TARGET"
			UIDropDownMenu_AddButton(info, level)

			-- Cancel
			info = UIDropDownMenu_CreateInfo()
			info.text = CANCEL
			info.notCheckable = true
			info.func = function()
				CloseDropDownMenus()
			end
			UIDropDownMenu_AddButton(info, level)

		-- Level 2: Dungeon Difficulty
		elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "DUNGEON_DIFFICULTY" then
			local currentDifficulty = GetDungeonDifficulty()

			info = UIDropDownMenu_CreateInfo()
			info.text = "5 Player"
			info.func = function()
				SetDungeonDifficulty(1)
			end
			info.checked = (currentDifficulty == 1)
			UIDropDownMenu_AddButton(info, level)

			info = UIDropDownMenu_CreateInfo()
			info.text = "5 Player (Heroic)"
			info.func = function()
				SetDungeonDifficulty(2)
			end
			info.checked = (currentDifficulty == 2)
			UIDropDownMenu_AddButton(info, level)

			info = UIDropDownMenu_CreateInfo()
			info.text = "5 Player (Mythic)"
			info.func = function()
				SetDungeonDifficulty(3)
			end
			info.checked = (currentDifficulty == 3)
			UIDropDownMenu_AddButton(info, level)

		-- Level 2: Raid Difficulty
		elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "RAID_DIFFICULTY" then
			local currentDifficulty = GetRaidDifficulty()

			info = UIDropDownMenu_CreateInfo()
			info.text = "Normal (10-25 Players)"
			info.func = function()
				SetRaidDifficulty(1)
			end
			info.checked = (currentDifficulty == 1)
			UIDropDownMenu_AddButton(info, level)

			info = UIDropDownMenu_CreateInfo()
			info.text = "Heroic (10-25 Players)"
			info.func = function()
				SetRaidDifficulty(2)
			end
			info.checked = (currentDifficulty == 2)
			UIDropDownMenu_AddButton(info, level)

			info = UIDropDownMenu_CreateInfo()
			info.text = "Mythic (10-25 Players)"
			info.func = function()
				SetRaidDifficulty(3)
			end
			info.checked = (currentDifficulty == 3)
			UIDropDownMenu_AddButton(info, level)

			info = UIDropDownMenu_CreateInfo()
			info.text = "Ascended (10-25 Players)" -- Custom for Ascended
			info.func = function()
				SetRaidDifficulty(4)
			end
			info.checked = (currentDifficulty == 4)
			UIDropDownMenu_AddButton(info, level)

		-- Level 2: Reset Instances
		elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "RESET_INSTANCES" then
			info = UIDropDownMenu_CreateInfo()
			info.text = RESET_ALL_DUNGEONS
			info.notCheckable = true
			info.func = function()
				StaticPopup_Show("CONFIRM_RESET_INSTANCES")
			end
			UIDropDownMenu_AddButton(info, level)

		-- Level 2: Raid Target Icons
		elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "RAID_TARGET" then
			local currentTarget = GetRaidTargetIndex("player")

			local icons = {
				{ name = RAID_TARGET_1, index = 1, r = 1.0, g = 1.0, b = 0.0 }, -- Star (Yellow)
				{ name = RAID_TARGET_2, index = 2, r = 1.0, g = 0.5, b = 0.0 }, -- Circle (Orange)
				{ name = RAID_TARGET_3, index = 3, r = 0.6, g = 0.4, b = 1.0 }, -- Diamond (Purple)
				{ name = RAID_TARGET_4, index = 4, r = 0.0, g = 1.0, b = 0.0 }, -- Triangle (Green)
				{ name = RAID_TARGET_5, index = 5, r = 0.7, g = 0.7, b = 0.7 }, -- Moon (Silver/Gray)
				{ name = RAID_TARGET_6, index = 6, r = 0.0, g = 0.5, b = 1.0 }, -- Square (Blue)
				{ name = RAID_TARGET_7, index = 7, r = 1.0, g = 0.0, b = 0.0 }, -- Cross (Red)
				{ name = RAID_TARGET_8, index = 8, r = 1.0, g = 1.0, b = 1.0 }, -- Skull (White)
			}

			for _, icon in ipairs(icons) do
				info = UIDropDownMenu_CreateInfo()
				info.text = icon.name
				info.func = function()
					SetRaidTarget("player", icon.index)
				end
				info.icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. icon.index
				info.tCoordLeft = 0
				info.tCoordRight = 1
				info.tCoordTop = 0
				info.tCoordBottom = 1
				info.colorCode = string.format("|cff%02x%02x%02x", icon.r * 255, icon.g * 255, icon.b * 255)
				info.checked = (currentTarget == icon.index)
				UIDropDownMenu_AddButton(info, level)
			end

			info = UIDropDownMenu_CreateInfo()
			info.text = RAID_TARGET_NONE
			info.func = function()
				SetRaidTarget("player", 0)
			end
			info.checked = (currentTarget == nil or currentTarget == 0)
			UIDropDownMenu_AddButton(info, level)
		end
	end

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

local function CreateTargetCastBar(parent)
	local castBar = CreateFrame("StatusBar", nil, parent)
	castBar:SetSize(148, 12)
	castBar:SetPoint("TOP", parent, "BOTTOM", 0, -6)
	castBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	castBar:GetStatusBarTexture():SetHorizTile(false)
	castBar:GetStatusBarTexture():SetVertTile(false)
	castBar:SetMinMaxValues(0, 1)
	castBar:SetValue(0)
	castBar:Hide()

	-- Background
	local bg = castBar:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(0, 0, 0, 0.5)
	bg:SetAllPoints(castBar)

	-- Border
	local border = castBar:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border-Small")
	border:SetSize(195, 50)
	border:SetPoint("TOP", castBar, "TOP", 0, 20)

	-- Text
	local text = castBar:CreateFontString(nil, "OVERLAY")
	text:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	text:SetPoint("LEFT", castBar, "LEFT", 2, 1)
	text:SetTextColor(1, 1, 1)
	castBar.text = text

	-- Time
	local time = castBar:CreateFontString(nil, "OVERLAY")
	time:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	time:SetPoint("RIGHT", castBar, "RIGHT", -2, 1)
	time:SetTextColor(1, 1, 1)
	castBar.time = time

	-- Icon
	local icon = castBar:CreateTexture(nil, "OVERLAY")
	icon:SetSize(16, 16)
	icon:SetPoint("RIGHT", castBar, "LEFT", -5, 0)
	castBar.icon = icon

	-- State
	castBar.state = CASTBAR_STATE.HIDDEN
	castBar.startTime = 0
	castBar.endTime = 0
	castBar.notInterruptible = false
	castBar.holdUntil = 0
	castBar.fadeStartTime = 0
	castBar.spellName = ""
	castBar.spellTexture = ""

	return castBar
end

local function UpdateTargetCastBar(castBar, elapsed)
	if not castBar or not UnitExists("target") then
		return
	end

	local currentTime = GetTime()
	local state = castBar.state

	-- State: FINISHED (holding before fade)
	if state == CASTBAR_STATE.FINISHED then
		if currentTime >= castBar.holdUntil then
			-- Transition to fading
			castBar.state = CASTBAR_STATE.FADING
			castBar.fadeStartTime = currentTime
		end
		return
	end

	-- State: FADING
	if state == CASTBAR_STATE.FADING then
		local fadeDuration = 1
		local fadeElapsed = currentTime - castBar.fadeStartTime

		if fadeElapsed >= fadeDuration then
			-- Fade complete
			castBar:Hide()
			castBar:SetAlpha(1)
			castBar.state = CASTBAR_STATE.HIDDEN
		else
			-- Still fading
			local alpha = 1 - (fadeElapsed / fadeDuration)
			castBar:SetAlpha(alpha)
		end
		return
	end

	-- State: CASTING or CHANNELING
	if state == CASTBAR_STATE.CASTING or state == CASTBAR_STATE.CHANNELING then
		local remaining = castBar.endTime - currentTime

		if remaining < 0 then
			-- Cast finished naturally, but wait for STOP event
			-- Just cap at 100%
			castBar:SetValue(1)
			return
		end

		-- Update progress
		local duration = castBar.endTime - castBar.startTime
		local progress

		if state == CASTBAR_STATE.CHANNELING then
			-- Channeling goes from full to empty
			progress = remaining / duration
		else
			-- Casting goes from empty to full
			progress = 1 - (remaining / duration)
		end

		castBar:SetValue(progress)

		-- Update time text
		castBar.time:SetText(string.format("%.1f", remaining))

		-- Set color based on interruptible status
		if castBar.notInterruptible then
			castBar:SetStatusBarColor(0.5, 0.5, 0.5) -- Gray
		else
			castBar:SetStatusBarColor(1, 0.7, 0) -- Yellow
		end
	end
end

local function CreateFocusCastBar(parent)
	local castBar = CreateFrame("StatusBar", nil, parent)
	castBar:SetSize(148, 12)
	castBar:SetPoint("TOP", parent, "BOTTOM", 0, -6)
	castBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	castBar:GetStatusBarTexture():SetHorizTile(false)
	castBar:GetStatusBarTexture():SetVertTile(false)
	castBar:SetMinMaxValues(0, 1)
	castBar:SetValue(0)
	castBar:Hide()

	-- Background
	local bg = castBar:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(0, 0, 0, 0.5)
	bg:SetAllPoints(castBar)

	-- Border
	local border = castBar:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border-Small")
	border:SetSize(195, 50)
	border:SetPoint("TOP", castBar, "TOP", 0, 20)

	-- Text
	local text = castBar:CreateFontString(nil, "OVERLAY")
	text:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	text:SetPoint("LEFT", castBar, "LEFT", 2, 1)
	text:SetTextColor(1, 1, 1)
	castBar.text = text

	-- Time
	local time = castBar:CreateFontString(nil, "OVERLAY")
	time:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	time:SetPoint("RIGHT", castBar, "RIGHT", -2, 1)
	time:SetTextColor(1, 1, 1)
	castBar.time = time

	-- Icon
	local icon = castBar:CreateTexture(nil, "OVERLAY")
	icon:SetSize(16, 16)
	icon:SetPoint("RIGHT", castBar, "LEFT", -5, 0)
	castBar.icon = icon

	-- State
	castBar.state = CASTBAR_STATE.HIDDEN
	castBar.startTime = 0
	castBar.endTime = 0
	castBar.notInterruptible = false
	castBar.holdUntil = 0
	castBar.fadeStartTime = 0
	castBar.spellName = ""
	castBar.spellTexture = ""

	return castBar
end

local function UpdateFocusCastBar(castBar, elapsed)
	if not castBar or not UnitExists("focus") then
		return
	end

	local currentTime = GetTime()
	local state = castBar.state

	-- State: FINISHED (holding before fade)
	if state == CASTBAR_STATE.FINISHED then
		if currentTime >= castBar.holdUntil then
			-- Transition to fading
			castBar.state = CASTBAR_STATE.FADING
			castBar.fadeStartTime = currentTime
		end
		return
	end

	-- State: FADING
	if state == CASTBAR_STATE.FADING then
		local fadeDuration = 1
		local fadeElapsed = currentTime - castBar.fadeStartTime

		if fadeElapsed >= fadeDuration then
			-- Fade complete
			castBar:Hide()
			castBar:SetAlpha(1)
			castBar.state = CASTBAR_STATE.HIDDEN
		else
			-- Still fading
			local alpha = 1 - (fadeElapsed / fadeDuration)
			castBar:SetAlpha(alpha)
		end
		return
	end

	-- State: CASTING or CHANNELING
	if state == CASTBAR_STATE.CASTING or state == CASTBAR_STATE.CHANNELING then
		local remaining = castBar.endTime - currentTime

		if remaining < 0 then
			-- Cast finished naturally, but wait for STOP event
			-- Just cap at 100%
			castBar:SetValue(1)
			return
		end

		-- Update progress
		local duration = castBar.endTime - castBar.startTime
		local progress

		if state == CASTBAR_STATE.CHANNELING then
			-- Channeling goes from full to empty
			progress = remaining / duration
		else
			-- Casting goes from empty to full
			progress = 1 - (remaining / duration)
		end

		castBar:SetValue(progress)

		-- Update time text
		castBar.time:SetText(string.format("%.1f", remaining))

		-- Set color based on interruptible status
		if castBar.notInterruptible then
			castBar:SetStatusBarColor(0.5, 0.5, 0.5) -- Gray
		else
			castBar:SetStatusBarColor(1, 0.7, 0) -- Yellow
		end
	end
end

-------------------------------------------------------------------------------
-- TARGET FRAME CREATION
-------------------------------------------------------------------------------

local function CreateTargetFrame()
	-- Main frame container (Button for secure click handling and menu support)
	local frame = CreateFrame("Button", "UFI_TargetFrame", UIParent, "SecureUnitButtonTemplate")
	frame:SetSize(232, 100)
	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 250, -4) -- Default Blizzard TargetFrame position
	frame:SetFrameStrata("MEDIUM")
	frame:SetFrameLevel(1)
	frame:SetScale(1.15)

	-- Health bar (BACKGROUND layer - drawn first, below frame texture)
	frame.healthBar = CreateFrame("StatusBar", nil, frame)
	frame.healthBar:SetSize(108, 24)
	frame.healthBar:SetPoint("TOPLEFT", 27, -20) -- Moved to left side for target frame
	frame.healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	frame.healthBar:GetStatusBarTexture():SetHorizTile(false)
	frame.healthBar:GetStatusBarTexture():SetVertTile(false)
	frame.healthBar:GetStatusBarTexture():SetDrawLayer("BACKGROUND", -8)
	frame.healthBar:SetMinMaxValues(0, 100)
	frame.healthBar:SetValue(100)
	frame.healthBar:SetFrameLevel(frame:GetFrameLevel() - 1)

	-- Health bar background (black with 35% opacity)
	frame.healthBarBg = frame.healthBar:CreateTexture(nil, "BACKGROUND")
	frame.healthBarBg:SetTexture(0, 0, 0, 0.35)
	frame.healthBarBg:SetAllPoints(frame.healthBar)

	-- Remove default StatusBar background
	if frame.healthBar.SetBackdrop then
		frame.healthBar:SetBackdrop(nil)
	end

	-- Mana/Power bar (BACKGROUND layer - drawn first, below frame texture)
	frame.powerBar = CreateFrame("StatusBar", nil, frame)
	frame.powerBar:SetSize(108, 9)
	frame.powerBar:SetPoint("TOPLEFT", 27, -46) -- Moved to left side for target frame
	frame.powerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	frame.powerBar:GetStatusBarTexture():SetHorizTile(false)
	frame.powerBar:GetStatusBarTexture():SetVertTile(false)
	frame.powerBar:GetStatusBarTexture():SetDrawLayer("BACKGROUND", -8)
	frame.powerBar:SetMinMaxValues(0, 100)
	frame.powerBar:SetValue(100)
	frame.powerBar:SetFrameLevel(frame:GetFrameLevel() - 1)

	-- Power bar background (black with 35% opacity)
	frame.powerBarBg = frame.powerBar:CreateTexture(nil, "BACKGROUND")
	frame.powerBarBg:SetTexture(0, 0, 0, 0.35)
	frame.powerBarBg:SetAllPoints(frame.powerBar)

	-- Remove default StatusBar background
	if frame.powerBar.SetBackdrop then
		frame.powerBar:SetBackdrop(nil)
	end

	-- Border/Background texture (BORDER layer - drawn on top of bars)
	frame.texture = frame:CreateTexture(nil, "BORDER", nil, 0)
	frame.texture:SetTexture("Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame")
	frame.texture:SetSize(232, 110)
	frame.texture:SetPoint("TOPLEFT", 0, 0)
	-- No flip needed for target frame - it faces the opposite direction from player

	-- Portrait (2D texture - BACKGROUND layer to ensure it's always below frame texture)
	frame.portrait = frame:CreateTexture(nil, "BACKGROUND", nil, 5)
	frame.portrait:SetSize(50, 48)
	frame.portrait:SetPoint("CENTER", frame, "TOPLEFT", 164, -38) -- Moved to right side for target frame

	-- Make portrait circular using texture coordinates to crop it
	local circularCrop = 0.08
	frame.portrait:SetTexCoord(circularCrop, 1 - circularCrop, circularCrop, 1 - circularCrop)

	-- Circular mask for portrait using the frame texture itself as a mask
	frame.portraitMask = frame:CreateTexture(nil, "BORDER", nil, 5)
	frame.portraitMask:SetTexture("Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame")
	frame.portraitMask:SetSize(232, 110)
	frame.portraitMask:SetPoint("TOPLEFT", 0, 0)
	frame.portraitMask:SetBlendMode("BLEND")

	-- Elite/Rare dragon texture
	frame.eliteTexture = frame:CreateTexture(nil, "OVERLAY")
	frame.eliteTexture:SetSize(232, 110)
	frame.eliteTexture:SetPoint("TOPLEFT", 0, 0)
	frame.eliteTexture:Hide()

	-- Level text (on right side for target frame)
	frame.levelText = frame:CreateFontString(nil, "OVERLAY")
	frame.levelText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	frame.levelText:SetPoint("CENTER", frame, "TOPLEFT", 184, -56) -- Moved to right side for target frame
	frame.levelText:SetTextColor(1, 0.82, 0)

	-- Unit name (OVERLAY layer - drawn on top of everything)
	-- Must be child of main frame, not healthBar, to render above frame texture
	frame.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.nameText:SetPoint("CENTER", frame.healthBar, "CENTER", 0, 6)
	frame.nameText:SetText("")
	frame.nameText:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")
	frame.nameText:SetDrawLayer("OVERLAY", 7)

	-- Health text (OVERLAY layer - drawn on top of everything)
	-- Must be child of main frame, not healthBar, to render above frame texture
	frame.healthText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.healthText:SetPoint("CENTER", frame.healthBar, "CENTER", 0, -6)
	frame.healthText:SetText("")
	frame.healthText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	frame.healthText:SetTextColor(1, 1, 1)
	frame.healthText:SetDrawLayer("OVERLAY", 7)

	-- Power text (OVERLAY layer - drawn on top of everything)
	-- Must be child of main frame, not powerBar, to render above frame texture
	frame.powerText = frame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	frame.powerText:SetPoint("CENTER", frame.powerBar, "CENTER", 0, 1)
	frame.powerText:SetText("")
	frame.powerText:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")
	frame.powerText:SetTextColor(1, 1, 1)
	frame.powerText:SetDrawLayer("OVERLAY", 7)

	-- Dead text overlay
	frame.deadText = frame:CreateFontString(nil, "OVERLAY")
	frame.deadText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	frame.deadText:SetPoint("CENTER", frame.healthBar, "CENTER", 0, 0)
	frame.deadText:SetTextColor(0.5, 0.5, 0.5)
	frame.deadText:Hide()

	-- Cast bar
	frame.castBar = CreateTargetCastBar(frame)

	-- Aura containers
	frame.buffs = {}
	frame.debuffs = {}
	frame.myDebuffs = {}

	-- Create buff icons (1 row, up to 5 buffs)
	for i = 1, 5 do
		local buff = CreateFrame("Frame", nil, frame)
		buff:SetSize(15, 15)
		if i == 1 then
			buff:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 28, 40)
		else
			buff:SetPoint("LEFT", frame.buffs[i - 1], "RIGHT", 2, 0)
		end

		buff.icon = buff:CreateTexture(nil, "ARTWORK")
		buff.icon:SetPoint("TOPLEFT", buff, "TOPLEFT", 1, -1)
		buff.icon:SetPoint("BOTTOMRIGHT", buff, "BOTTOMRIGHT", -1, 1)
		buff.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		buff.border = buff:CreateTexture(nil, "OVERLAY")
		buff.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
		buff.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
		buff.border:SetAllPoints()

		buff.cooldown = CreateFrame("Cooldown", nil, buff, "CooldownFrameTemplate")
		buff.cooldown:SetAllPoints()

		buff.count = buff:CreateFontString(nil, "OVERLAY")
		buff.count:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
		buff.count:SetPoint("BOTTOMRIGHT", buff, "BOTTOMRIGHT", 0, 0)

		buff:Hide()
		frame.buffs[i] = buff
	end

	-- Create debuff icons (1 row, up to 5 debuffs)
	for i = 1, 5 do
		local debuff = CreateFrame("Frame", nil, frame)
		debuff:SetSize(18, 18)
		if i == 1 then
			debuff:SetPoint("TOPLEFT", frame.buffs[1], "BOTTOMLEFT", 0, -2)
		else
			debuff:SetPoint("LEFT", frame.debuffs[i - 1], "RIGHT", 2, 0)
		end

		debuff.icon = debuff:CreateTexture(nil, "ARTWORK")
		debuff.icon:SetPoint("TOPLEFT", debuff, "TOPLEFT", 1, -1)
		debuff.icon:SetPoint("BOTTOMRIGHT", debuff, "BOTTOMRIGHT", -1, 1)
		debuff.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		debuff.border = debuff:CreateTexture(nil, "OVERLAY")
		debuff.border:SetAllPoints()

		debuff.cooldown = CreateFrame("Cooldown", nil, debuff, "CooldownFrameTemplate")
		debuff.cooldown:SetAllPoints()

		debuff.count = debuff:CreateFontString(nil, "OVERLAY")
		debuff.count:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
		debuff.count:SetPoint("BOTTOMRIGHT", debuff, "BOTTOMRIGHT", 0, 0)

		debuff:Hide()
		frame.debuffs[i] = debuff
	end

	-- Create my debuff icons (1 row, up to 5 debuffs)
	for i = 1, 5 do
		local myDebuff = CreateFrame("Frame", nil, frame)
		myDebuff:SetSize(20, 20)
		if i == 1 then
			myDebuff:SetPoint("TOPLEFT", frame.debuffs[1], "BOTTOMLEFT", 0, -2)
		else
			myDebuff:SetPoint("LEFT", frame.myDebuffs[i - 1], "RIGHT", 2, 0)
		end

		myDebuff.icon = myDebuff:CreateTexture(nil, "ARTWORK")
		myDebuff.icon:SetPoint("TOPLEFT", myDebuff, "TOPLEFT", 1, -1)
		myDebuff.icon:SetPoint("BOTTOMRIGHT", myDebuff, "BOTTOMRIGHT", -1, 1)
		myDebuff.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		myDebuff.border = myDebuff:CreateTexture(nil, "OVERLAY")
		myDebuff.border:SetAllPoints()

		myDebuff.cooldown = CreateFrame("Cooldown", nil, myDebuff, "CooldownFrameTemplate")
		myDebuff.cooldown:SetAllPoints()

		myDebuff.count = myDebuff:CreateFontString(nil, "OVERLAY")
		myDebuff.count:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
		myDebuff.count:SetPoint("BOTTOMRIGHT", myDebuff, "BOTTOMRIGHT", 0, 0)

		myDebuff:Hide()
		frame.myDebuffs[i] = myDebuff
	end

	-- Enable mouse clicks and set up secure click handling
	frame:EnableMouse(true)
	frame:RegisterForClicks("AnyUp")

	-- Create custom dropdown menu for target
	local targetDropdown = CreateFrame("Frame", "UFI_TargetFrameDropDown", UIParent, "UIDropDownMenuTemplate")
	targetDropdown.displayMode = "MENU"
	targetDropdown.initialize = function(self, level)
		if not level then
			return
		end

		local info = UIDropDownMenu_CreateInfo()

		-- Level 1: Main menu
		if level == 1 then
			-- Title - Target name
			info.text = UnitName("target") or "Target"
			info.isTitle = true
			info.notCheckable = true
			UIDropDownMenu_AddButton(info, level)

			-- Whisper
			info = UIDropDownMenu_CreateInfo()
			info.text = WHISPER
			info.notCheckable = true
			info.func = function()
				if UnitIsPlayer("target") then
					ChatFrame_SendTell(UnitName("target"))
				end
			end
			info.disabled = not UnitIsPlayer("target")
			UIDropDownMenu_AddButton(info, level)

			-- Inspect
			info = UIDropDownMenu_CreateInfo()
			info.text = INSPECT
			info.notCheckable = true
			info.func = function()
				InspectUnit("target")
			end
			info.disabled = not CanInspect("target")
			UIDropDownMenu_AddButton(info, level)

			-- Invite
			info = UIDropDownMenu_CreateInfo()
			info.text = INVITE
			info.notCheckable = true
			info.func = function()
				InviteUnit(UnitName("target"))
			end
			info.disabled = not UnitIsPlayer("target") or UnitInParty("target") or UnitInRaid("target")
			UIDropDownMenu_AddButton(info, level)

			-- Compare Achievements
			info = UIDropDownMenu_CreateInfo()
			info.text = COMPARE_ACHIEVEMENTS
			info.notCheckable = true
			info.func = function()
				if not AchievementFrame then
					AchievementFrame_LoadUI()
				end
				if AchievementFrame then
					AchievementFrame_DisplayComparison(UnitName("target"))
				end
			end
			info.disabled = not UnitIsPlayer("target")
			UIDropDownMenu_AddButton(info, level)

			-- Trade
			info = UIDropDownMenu_CreateInfo()
			info.text = TRADE
			info.notCheckable = true
			info.func = function()
				InitiateTrade("target")
			end
			info.disabled = not UnitIsPlayer("target") or not CheckInteractDistance("target", 2)
			UIDropDownMenu_AddButton(info, level)

			-- Follow
			info = UIDropDownMenu_CreateInfo()
			info.text = FOLLOW
			info.notCheckable = true
			info.func = function()
				FollowUnit("target")
			end
			info.disabled = not UnitIsPlayer("target")
			UIDropDownMenu_AddButton(info, level)

			-- Duel
			info = UIDropDownMenu_CreateInfo()
			info.text = DUEL
			info.notCheckable = true
			info.func = function()
				StartDuel("target")
			end
			info.disabled = not UnitIsPlayer("target") or not CheckInteractDistance("target", 3)
			UIDropDownMenu_AddButton(info, level)

			-- Raid Target Icon submenu
			info = UIDropDownMenu_CreateInfo()
			info.text = RAID_TARGET_ICON
			info.notCheckable = true
			info.hasArrow = true
			info.value = "RAID_TARGET"
			UIDropDownMenu_AddButton(info, level)

			-- Cancel
			info = UIDropDownMenu_CreateInfo()
			info.text = CANCEL
			info.notCheckable = true
			info.func = function()
				CloseDropDownMenus()
			end
			UIDropDownMenu_AddButton(info, level)

		-- Level 2: Raid Target Icons
		elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "RAID_TARGET" then
			local currentTarget = GetRaidTargetIndex("target")

			local icons = {
				{ name = RAID_TARGET_1, index = 1, r = 1.0, g = 1.0, b = 0.0 }, -- Star (Yellow)
				{ name = RAID_TARGET_2, index = 2, r = 1.0, g = 0.5, b = 0.0 }, -- Circle (Orange)
				{ name = RAID_TARGET_3, index = 3, r = 0.6, g = 0.4, b = 1.0 }, -- Diamond (Purple)
				{ name = RAID_TARGET_4, index = 4, r = 0.0, g = 1.0, b = 0.0 }, -- Triangle (Green)
				{ name = RAID_TARGET_5, index = 5, r = 0.7, g = 0.7, b = 0.7 }, -- Moon (Silver/Gray)
				{ name = RAID_TARGET_6, index = 6, r = 0.0, g = 0.5, b = 1.0 }, -- Square (Blue)
				{ name = RAID_TARGET_7, index = 7, r = 1.0, g = 0.0, b = 0.0 }, -- Cross (Red)
				{ name = RAID_TARGET_8, index = 8, r = 1.0, g = 1.0, b = 1.0 }, -- Skull (White)
			}

			for _, icon in ipairs(icons) do
				info = UIDropDownMenu_CreateInfo()
				info.text = icon.name
				info.func = function()
					SetRaidTarget("target", icon.index)
				end
				info.icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. icon.index
				info.tCoordLeft = 0
				info.tCoordRight = 1
				info.tCoordTop = 0
				info.tCoordBottom = 1
				info.colorCode = string.format("|cff%02x%02x%02x", icon.r * 255, icon.g * 255, icon.b * 255)
				info.checked = (currentTarget == icon.index)
				UIDropDownMenu_AddButton(info, level)
			end

			info = UIDropDownMenu_CreateInfo()
			info.text = RAID_TARGET_NONE
			info.func = function()
				SetRaidTarget("target", 0)
			end
			info.checked = (currentTarget == nil or currentTarget == 0)
			UIDropDownMenu_AddButton(info, level)
		end
	end

	-- Reference to player dropdown for when target is player
	local playerDropdown = UFI_PlayerFrameDropDown

	-- Initialize secure unit button with menu function
	SecureUnitButton_OnLoad(frame, "target", function(self, unit, button)
		-- Check if target is the player
		if UnitIsUnit("target", "player") then
			-- Show player menu instead
			ToggleDropDownMenu(1, nil, playerDropdown, self, 110, 45)
		else
			-- Show target menu
			ToggleDropDownMenu(1, nil, targetDropdown, self, 110, 45)
		end
	end)

	-- Use RegisterStateDriver for secure show/hide based on target existence
	RegisterStateDriver(frame, "visibility", "[exists] show; hide")

	return frame
end

-------------------------------------------------------------------------------
-- FOCUS FRAME CREATION
-------------------------------------------------------------------------------

local function CreateFocusFrame()
	-- Main frame container (Button for secure click handling)
	local frame = CreateFrame("Button", "UFI_FocusFrame", UIParent, "SecureUnitButtonTemplate")
	frame:SetSize(232, 100)

	frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 250, -250) -- Default Blizzard FocusFrame position
	frame:SetFrameStrata("MEDIUM")
	frame:SetFrameLevel(1)
	frame:SetScale(1.15)

	-- Health bar (BACKGROUND layer - drawn first, below frame texture)
	frame.healthBar = CreateFrame("StatusBar", nil, frame)
	frame.healthBar:SetSize(108, 24)
	frame.healthBar:SetPoint("TOPLEFT", 27, -20) -- Left side like target frame
	frame.healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	frame.healthBar:GetStatusBarTexture():SetHorizTile(false)
	frame.healthBar:GetStatusBarTexture():SetVertTile(false)
	frame.healthBar:GetStatusBarTexture():SetDrawLayer("BACKGROUND", -8)
	frame.healthBar:SetMinMaxValues(0, 100)
	frame.healthBar:SetValue(100)
	frame.healthBar:SetFrameLevel(frame:GetFrameLevel() - 1)

	-- Health bar background (black with 35% opacity)
	frame.healthBarBg = frame.healthBar:CreateTexture(nil, "BACKGROUND")
	frame.healthBarBg:SetTexture(0, 0, 0, 0.35)
	frame.healthBarBg:SetAllPoints(frame.healthBar)

	-- Remove default StatusBar background
	if frame.healthBar.SetBackdrop then
		frame.healthBar:SetBackdrop(nil)
	end

	-- Mana/Power bar (BACKGROUND layer - drawn first, below frame texture)
	frame.powerBar = CreateFrame("StatusBar", nil, frame)
	frame.powerBar:SetSize(108, 9)
	frame.powerBar:SetPoint("TOPLEFT", 27, -46) -- Left side like target frame
	frame.powerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	frame.powerBar:GetStatusBarTexture():SetHorizTile(false)
	frame.powerBar:GetStatusBarTexture():SetVertTile(false)
	frame.powerBar:GetStatusBarTexture():SetDrawLayer("BACKGROUND", -8)
	frame.powerBar:SetMinMaxValues(0, 100)
	frame.powerBar:SetValue(100)
	frame.powerBar:SetFrameLevel(frame:GetFrameLevel() - 1)

	-- Power bar background (black with 35% opacity)
	frame.powerBarBg = frame.powerBar:CreateTexture(nil, "BACKGROUND")
	frame.powerBarBg:SetTexture(0, 0, 0, 0.35)
	frame.powerBarBg:SetAllPoints(frame.powerBar)

	-- Remove default StatusBar background
	if frame.powerBar.SetBackdrop then
		frame.powerBar:SetBackdrop(nil)
	end

	-- Border/Background texture (BORDER layer - drawn on top of bars)
	frame.texture = frame:CreateTexture(nil, "BORDER", nil, 0)
	frame.texture:SetTexture("Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame")
	frame.texture:SetSize(232, 110)
	frame.texture:SetPoint("TOPLEFT", 0, 0)
	-- No flip needed for focus frame - same orientation as target

	-- Portrait (2D texture - BACKGROUND layer to ensure it's always below frame texture)
	frame.portrait = frame:CreateTexture(nil, "BACKGROUND", nil, 5)
	frame.portrait:SetSize(50, 48)
	frame.portrait:SetPoint("CENTER", frame, "TOPLEFT", 164, -38) -- Right side like target frame

	-- Make portrait circular using texture coordinates to crop it
	local circularCrop = 0.08
	frame.portrait:SetTexCoord(circularCrop, 1 - circularCrop, circularCrop, 1 - circularCrop)

	-- Circular mask for portrait using the frame texture itself as a mask
	frame.portraitMask = frame:CreateTexture(nil, "BORDER", nil, 5)
	frame.portraitMask:SetTexture("Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame")
	frame.portraitMask:SetSize(232, 110)
	frame.portraitMask:SetPoint("TOPLEFT", 0, 0)
	frame.portraitMask:SetBlendMode("BLEND")

	-- Elite/Rare dragon texture
	frame.eliteTexture = frame:CreateTexture(nil, "OVERLAY")
	frame.eliteTexture:SetSize(232, 110)
	frame.eliteTexture:SetPoint("TOPLEFT", 0, 0)
	frame.eliteTexture:Hide()

	-- Level text (on right side like target frame)
	frame.levelText = frame:CreateFontString(nil, "OVERLAY")
	frame.levelText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	frame.levelText:SetPoint("CENTER", frame, "TOPLEFT", 184, -56) -- Right side like target frame
	frame.levelText:SetTextColor(1, 0.82, 0)

	-- Unit name (OVERLAY layer - drawn on top of everything)
	frame.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.nameText:SetPoint("CENTER", frame.healthBar, "CENTER", 0, 6)
	frame.nameText:SetText("")
	frame.nameText:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")
	frame.nameText:SetDrawLayer("OVERLAY", 7)

	-- Health text (OVERLAY layer - drawn on top of everything)
	frame.healthText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.healthText:SetPoint("CENTER", frame.healthBar, "CENTER", 0, -6)
	frame.healthText:SetText("")
	frame.healthText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	frame.healthText:SetTextColor(1, 1, 1)
	frame.healthText:SetDrawLayer("OVERLAY", 7)

	-- Power text (OVERLAY layer - drawn on top of everything)
	frame.powerText = frame:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	frame.powerText:SetPoint("CENTER", frame.powerBar, "CENTER", 0, 1)
	frame.powerText:SetText("")
	frame.powerText:SetFont("Fonts\\FRIZQT__.TTF", 7, "OUTLINE")
	frame.powerText:SetTextColor(1, 1, 1)
	frame.powerText:SetDrawLayer("OVERLAY", 7)

	-- Dead text overlay
	frame.deadText = frame:CreateFontString(nil, "OVERLAY")
	frame.deadText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	frame.deadText:SetPoint("CENTER", frame.healthBar, "CENTER", 0, 0)
	frame.deadText:SetTextColor(0.5, 0.5, 0.5)
	frame.deadText:Hide()

	-- Cast bar
	frame.castBar = CreateFocusCastBar(frame)

	-- Aura containers
	frame.buffs = {}
	frame.debuffs = {}
	frame.myDebuffs = {}

	-- Create buff icons (1 row, up to 5 buffs)
	for i = 1, 5 do
		local buff = CreateFrame("Frame", nil, frame)
		buff:SetSize(15, 15)
		if i == 1 then
			buff:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 28, 40)
		else
			buff:SetPoint("LEFT", frame.buffs[i - 1], "RIGHT", 2, 0)
		end

		buff.icon = buff:CreateTexture(nil, "ARTWORK")
		buff.icon:SetPoint("TOPLEFT", buff, "TOPLEFT", 1, -1)
		buff.icon:SetPoint("BOTTOMRIGHT", buff, "BOTTOMRIGHT", -1, 1)
		buff.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		buff.border = buff:CreateTexture(nil, "OVERLAY")
		buff.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
		buff.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
		buff.border:SetAllPoints()

		buff.cooldown = CreateFrame("Cooldown", nil, buff, "CooldownFrameTemplate")
		buff.cooldown:SetAllPoints()

		buff.count = buff:CreateFontString(nil, "OVERLAY")
		buff.count:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
		buff.count:SetPoint("BOTTOMRIGHT", buff, "BOTTOMRIGHT", 0, 0)

		buff:Hide()
		frame.buffs[i] = buff
	end

	-- Create debuff icons (1 row, up to 5 debuffs)
	for i = 1, 5 do
		local debuff = CreateFrame("Frame", nil, frame)
		debuff:SetSize(18, 18)
		if i == 1 then
			debuff:SetPoint("TOPLEFT", frame.buffs[1], "BOTTOMLEFT", 0, -2)
		else
			debuff:SetPoint("LEFT", frame.debuffs[i - 1], "RIGHT", 2, 0)
		end

		debuff.icon = debuff:CreateTexture(nil, "ARTWORK")
		debuff.icon:SetPoint("TOPLEFT", debuff, "TOPLEFT", 1, -1)
		debuff.icon:SetPoint("BOTTOMRIGHT", debuff, "BOTTOMRIGHT", -1, 1)
		debuff.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		debuff.border = debuff:CreateTexture(nil, "OVERLAY")
		debuff.border:SetAllPoints()

		debuff.cooldown = CreateFrame("Cooldown", nil, debuff, "CooldownFrameTemplate")
		debuff.cooldown:SetAllPoints()

		debuff.count = debuff:CreateFontString(nil, "OVERLAY")
		debuff.count:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
		debuff.count:SetPoint("BOTTOMRIGHT", debuff, "BOTTOMRIGHT", 0, 0)

		debuff:Hide()
		frame.debuffs[i] = debuff
	end

	-- Create my debuff icons (1 row, up to 5 debuffs)
	for i = 1, 5 do
		local myDebuff = CreateFrame("Frame", nil, frame)
		myDebuff:SetSize(20, 20)
		if i == 1 then
			myDebuff:SetPoint("TOPLEFT", frame.debuffs[1], "BOTTOMLEFT", 0, -2)
		else
			myDebuff:SetPoint("LEFT", frame.myDebuffs[i - 1], "RIGHT", 2, 0)
		end

		myDebuff.icon = myDebuff:CreateTexture(nil, "ARTWORK")
		myDebuff.icon:SetPoint("TOPLEFT", myDebuff, "TOPLEFT", 1, -1)
		myDebuff.icon:SetPoint("BOTTOMRIGHT", myDebuff, "BOTTOMRIGHT", -1, 1)
		myDebuff.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		myDebuff.border = myDebuff:CreateTexture(nil, "OVERLAY")
		myDebuff.border:SetAllPoints()

		myDebuff.cooldown = CreateFrame("Cooldown", nil, myDebuff, "CooldownFrameTemplate")
		myDebuff.cooldown:SetAllPoints()

		myDebuff.count = myDebuff:CreateFontString(nil, "OVERLAY")
		myDebuff.count:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
		myDebuff.count:SetPoint("BOTTOMRIGHT", myDebuff, "BOTTOMRIGHT", 0, 0)

		myDebuff:Hide()
		frame.myDebuffs[i] = myDebuff
	end

	-- Enable mouse clicks
	frame:EnableMouse(true)
	frame:RegisterForClicks("AnyUp")

	-- Set unit for secure click handling
	frame:SetAttribute("unit", "focus")
	frame:SetAttribute("*type1", "target") -- Left click = target the unit
	frame:SetAttribute("*type2", "clearfocus") -- Right click = clear focus

	-- Use RegisterStateDriver for secure show/hide based on focus existence
	RegisterStateDriver(frame, "visibility", "[target=focus,exists] show; hide")

	return frame
end

-------------------------------------------------------------------------------
-- TARGET OF TARGET FRAME CREATION
-------------------------------------------------------------------------------

local function CreateTargetOfTargetFrame()
	-- Main frame container - SAME SIZE as player frame, will scale down (Button for secure click handling)
	local frame = CreateFrame("Button", "UFI_TargetOfTargetFrame", UIParent, "SecureUnitButtonTemplate")
	frame:SetSize(232, 100) -- Same as player frame
	frame:SetPoint("TOP", UFI_TargetFrame, "BOTTOM", 95, 80) -- Below target portrait
	frame:SetFrameStrata("MEDIUM")
	frame:SetFrameLevel(1)
	frame:SetScale(0.6) -- Scale to 50% (half size)

	-- Health bar - SAME as player frame
	frame.healthBar = CreateFrame("StatusBar", nil, frame)
	frame.healthBar:SetSize(108, 24)
	frame.healthBar:SetPoint("TOPLEFT", 97, -20)
	frame.healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	frame.healthBar:GetStatusBarTexture():SetHorizTile(false)
	frame.healthBar:GetStatusBarTexture():SetVertTile(false)
	frame.healthBar:GetStatusBarTexture():SetDrawLayer("BACKGROUND", -8)
	frame.healthBar:SetMinMaxValues(0, 100)
	frame.healthBar:SetValue(100)
	frame.healthBar:SetFrameLevel(frame:GetFrameLevel() - 1)

	-- Health bar background
	frame.healthBarBg = frame.healthBar:CreateTexture(nil, "BACKGROUND")
	frame.healthBarBg:SetTexture(0, 0, 0, 0.35)
	frame.healthBarBg:SetAllPoints(frame.healthBar)

	if frame.healthBar.SetBackdrop then
		frame.healthBar:SetBackdrop(nil)
	end

	-- Power bar - SAME as player frame
	frame.powerBar = CreateFrame("StatusBar", nil, frame)
	frame.powerBar:SetSize(108, 9)
	frame.powerBar:SetPoint("TOPLEFT", 97, -46)
	frame.powerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	frame.powerBar:GetStatusBarTexture():SetHorizTile(false)
	frame.powerBar:GetStatusBarTexture():SetVertTile(false)
	frame.powerBar:GetStatusBarTexture():SetDrawLayer("BACKGROUND", -8)
	frame.powerBar:SetMinMaxValues(0, 100)
	frame.powerBar:SetValue(100)
	frame.powerBar:SetFrameLevel(frame:GetFrameLevel() - 1)

	-- Power bar background
	frame.powerBarBg = frame.powerBar:CreateTexture(nil, "BACKGROUND")
	frame.powerBarBg:SetTexture(0, 0, 0, 0.35)
	frame.powerBarBg:SetAllPoints(frame.powerBar)

	if frame.powerBar.SetBackdrop then
		frame.powerBar:SetBackdrop(nil)
	end

	-- Frame texture - use BORDER layer to match target frame
	frame.texture = frame:CreateTexture(nil, "BORDER", nil, 0)
	frame.texture:SetTexture("Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame")
	frame.texture:SetPoint("TOPLEFT", 0, 0)
	frame.texture:SetSize(232, 110)
	frame.texture:SetTexCoord(1, 0, 0, 1) -- Flipped like player frame

	-- Portrait - SAME as player frame
	frame.portrait = frame:CreateTexture(nil, "BACKGROUND")
	frame.portrait:SetSize(50, 48)
	frame.portrait:SetPoint("CENTER", frame, "TOPLEFT", 68, -38)
	local circularCrop = 0.08
	frame.portrait:SetTexCoord(circularCrop, 1 - circularCrop, circularCrop, 1 - circularCrop)

	-- Name text - centered on health bar like player frame
	frame.nameText = frame.healthBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.nameText:SetPoint("CENTER", frame.healthBar, "CENTER", 0, 0)
	frame.nameText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")

	-- Level text
	frame.levelText = frame:CreateFontString(nil, "OVERLAY")
	frame.levelText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	frame.levelText:SetPoint("CENTER", frame, "TOPLEFT", 48, -56)
	frame.levelText:SetTextColor(1, 0.82, 0) -- Gold color

	-- Enable mouse clicks
	frame:EnableMouse(true)
	frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	-- Set unit for secure click handling
	frame:SetAttribute("unit", "targettarget")
	frame:SetAttribute("*type1", "target") -- Left click = target the unit

	-- Use RegisterStateDriver for secure show/hide based on targettarget existence
	RegisterStateDriver(frame, "visibility", "[target=targettarget,exists] show; hide")

	return frame
end

-------------------------------------------------------------------------------
-- PLAYER FRAME UPDATE FUNCTIONS
-------------------------------------------------------------------------------

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

	-- Set text
	local healthText = AbbreviateNumber(health) .. " / " .. AbbreviateNumber(maxHealth)
	UFI_PlayerFrame.healthText:SetText(healthText)
end

local function UpdatePlayerPower()
	if not UFI_PlayerFrame then
		return
	end

	local power = UnitPower("player")
	local maxPower = UnitPowerMax("player")
	local powerType = UnitPowerType("player")

	UFI_PlayerFrame.powerBar:SetMinMaxValues(0, maxPower)
	UFI_PlayerFrame.powerBar:SetValue(power)

	-- Ensure texture stays in BACKGROUND layer
	UFI_PlayerFrame.powerBar:GetStatusBarTexture():SetDrawLayer("BACKGROUND", -8)

	-- Set color based on power type
	local info = PowerBarColor[powerType]
	if info then
		UFI_PlayerFrame.powerBar:SetStatusBarColor(info.r, info.g, info.b)
	end

	-- Set text
	local powerText = AbbreviateNumber(power) .. " / " .. AbbreviateNumber(maxPower)
	UFI_PlayerFrame.powerText:SetText(powerText)
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

	if IsResting() then
		-- Show "zzz" when resting
		UFI_PlayerFrame.levelText:SetText("zzz")
		UFI_PlayerFrame.levelText:SetTextColor(1, 0.82, 0) -- Gold for rest
	else
		-- Show level number when not resting
		local level = UnitLevel("player")
		UFI_PlayerFrame.levelText:SetText(level)
		UFI_PlayerFrame.levelText:SetTextColor(1, 0.82, 0) -- Gold for level
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
		local healthText = AbbreviateNumber(health) .. " / " .. AbbreviateNumber(maxHealth)
		UFI_TargetFrame.healthText:SetText(healthText)
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
		UFI_TargetFrame.powerBar:Hide()
		UFI_TargetFrame.powerText:Hide()
		return
	end

	UFI_TargetFrame.powerBar:Show()
	UFI_TargetFrame.powerText:Show()

	UFI_TargetFrame.powerBar:SetMinMaxValues(0, maxPower)
	UFI_TargetFrame.powerBar:SetValue(power)

	-- Ensure texture stays in BACKGROUND layer
	UFI_TargetFrame.powerBar:GetStatusBarTexture():SetDrawLayer("BACKGROUND", -8)

	-- Set color based on power type
	local info = PowerBarColor[powerType]
	if info then
		UFI_TargetFrame.powerBar:SetStatusBarColor(info.r, info.g, info.b)
	end

	-- Set text
	local powerText = AbbreviateNumber(power) .. " / " .. AbbreviateNumber(maxPower)
	UFI_TargetFrame.powerText:SetText(powerText)
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
end

local function UpdateTargetOfTargetPower()
	if not UFI_TargetOfTargetFrame or not UnitExists("targettarget") then
		return
	end

	local power = UnitPower("targettarget")
	local maxPower = UnitPowerMax("targettarget")
	local powerType = UnitPowerType("targettarget")

	UFI_TargetOfTargetFrame.powerBar:SetMinMaxValues(0, maxPower)
	UFI_TargetOfTargetFrame.powerBar:SetValue(power)

	local info = PowerBarColor[powerType]
	if info then
		UFI_TargetOfTargetFrame.powerBar:SetStatusBarColor(info.r, info.g, info.b)
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

	if UnitExists("targettarget") then
		UpdateTargetOfTargetHealth()
		UpdateTargetOfTargetPower()
		UpdateTargetOfTargetPortrait()
		UpdateTargetOfTargetName()
		UpdateTargetOfTargetLevel()
	end
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

	UFI_FocusFrame.healthBar:SetMinMaxValues(0, maxHealth)
	UFI_FocusFrame.healthBar:SetValue(health)

	-- Set color based on unit type and state
	local r, g, b = GetUnitColor("focus")
	UFI_FocusFrame.healthBar:SetStatusBarColor(r, g, b)

	-- Check if dead
	if UnitIsDead("focus") then
		UFI_FocusFrame.deadText:SetText("Dead")
		UFI_FocusFrame.deadText:Show()
		UFI_FocusFrame.healthText:Hide()
	elseif UnitIsGhost("focus") then
		UFI_FocusFrame.deadText:SetText("Ghost")
		UFI_FocusFrame.deadText:Show()
		UFI_FocusFrame.healthText:Hide()
	else
		UFI_FocusFrame.deadText:Hide()
		UFI_FocusFrame.healthText:Show()
		-- Set text
		local healthText = AbbreviateNumber(health) .. " / " .. AbbreviateNumber(maxHealth)
		UFI_FocusFrame.healthText:SetText(healthText)
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
		UFI_FocusFrame.powerBar:Hide()
		UFI_FocusFrame.powerText:Hide()
		return
	end

	UFI_FocusFrame.powerBar:Show()
	UFI_FocusFrame.powerText:Show()

	UFI_FocusFrame.powerBar:SetMinMaxValues(0, maxPower)
	UFI_FocusFrame.powerBar:SetValue(power)

	-- Ensure texture stays in BACKGROUND layer
	UFI_FocusFrame.powerBar:GetStatusBarTexture():SetDrawLayer("BACKGROUND", -8)

	-- Set color based on power type
	local info = PowerBarColor[powerType]
	if info then
		UFI_FocusFrame.powerBar:SetStatusBarColor(info.r, info.g, info.b)
	end

	-- Set text
	local powerText = AbbreviateNumber(power) .. " / " .. AbbreviateNumber(maxPower)
	UFI_FocusFrame.powerText:SetText(powerText)
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

local function UpdateFocusAuras()
	if not UFI_FocusFrame or not UnitExists("focus") then
		-- Hide all auras
		for i = 1, 5 do
			UFI_FocusFrame.buffs[i]:Hide()
			UFI_FocusFrame.debuffs[i]:Hide()
			UFI_FocusFrame.myDebuffs[i]:Hide()
		end
		return
	end

	-- Collect all buffs and sort by duration (shortest first)
	local allBuffs = {}
	for i = 1, 40 do
		local name, rank, icon, count, debuffType, duration, expirationTime = UnitBuff("focus", i)
		if not name then
			break
		end

		local remainingTime = 999999 -- Default for permanent buffs (no duration)
		if duration and duration > 0 and expirationTime then
			remainingTime = expirationTime - GetTime()
		end

		table.insert(allBuffs, {
			icon = icon,
			count = count,
			duration = duration,
			expirationTime = expirationTime,
			remainingTime = remainingTime,
		})
	end

	-- Sort buffs: shortest duration first
	table.sort(allBuffs, function(a, b)
		return a.remainingTime < b.remainingTime
	end)

	-- Display up to 5 buffs
	for i = 1, 5 do
		if allBuffs[i] then
			local buff = UFI_FocusFrame.buffs[i]
			buff.icon:SetTexture(allBuffs[i].icon)

			-- Set cooldown for OmniCC
			if allBuffs[i].duration and allBuffs[i].duration > 0 and allBuffs[i].expirationTime then
				buff.cooldown:SetCooldown(allBuffs[i].expirationTime - allBuffs[i].duration, allBuffs[i].duration)
			end

			if allBuffs[i].count and allBuffs[i].count > 1 then
				buff.count:SetText(allBuffs[i].count)
				buff.count:Show()
			else
				buff.count:Hide()
			end
			buff:Show()
		else
			UFI_FocusFrame.buffs[i]:Hide()
		end
	end

	-- Collect all debuffs, separating player's from others'
	local myDebuffs = {}
	local otherDebuffs = {}

	for i = 1, 40 do
		local name, rank, icon, count, debuffType, duration, expirationTime, caster = UnitDebuff("focus", i)
		if not name then
			break
		end

		local remainingTime = 999999 -- Default for permanent debuffs
		if duration and duration > 0 and expirationTime then
			remainingTime = expirationTime - GetTime()
		end

		local debuffData = {
			icon = icon,
			count = count,
			debuffType = debuffType,
			duration = duration,
			expirationTime = expirationTime,
			remainingTime = remainingTime,
		}

		if caster == "player" then
			table.insert(myDebuffs, debuffData)
		else
			table.insert(otherDebuffs, debuffData)
		end
	end

	-- Sort both lists by duration (shortest first)
	table.sort(myDebuffs, function(a, b)
		return a.remainingTime < b.remainingTime
	end)
	table.sort(otherDebuffs, function(a, b)
		return a.remainingTime < b.remainingTime
	end)

	-- Combine: my debuffs first, then others' debuffs
	local allDebuffs = {}
	for _, debuff in ipairs(myDebuffs) do
		table.insert(allDebuffs, debuff)
	end
	for _, debuff in ipairs(otherDebuffs) do
		table.insert(allDebuffs, debuff)
	end

	-- Display up to 5 debuffs in row 2
	for i = 1, 5 do
		if allDebuffs[i] then
			local debuff = UFI_FocusFrame.debuffs[i]
			debuff.icon:SetTexture(allDebuffs[i].icon)

			-- Set border color based on debuff type
			local color = DebuffTypeColor[allDebuffs[i].debuffType or "none"] or DebuffTypeColor["none"]
			debuff.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
			debuff.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
			debuff.border:SetVertexColor(color[1], color[2], color[3])

			-- Set cooldown for OmniCC
			if allDebuffs[i].duration and allDebuffs[i].duration > 0 and allDebuffs[i].expirationTime then
				debuff.cooldown:SetCooldown(
					allDebuffs[i].expirationTime - allDebuffs[i].duration,
					allDebuffs[i].duration
				)
			end

			if allDebuffs[i].count and allDebuffs[i].count > 1 then
				debuff.count:SetText(allDebuffs[i].count)
				debuff.count:Show()
			else
				debuff.count:Hide()
			end
			debuff:Show()
		else
			UFI_FocusFrame.debuffs[i]:Hide()
		end
	end

	-- Hide row 3 (myDebuffs) - no longer used
	for i = 1, 5 do
		UFI_FocusFrame.myDebuffs[i]:Hide()
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
	if not UFI_TargetFrame or not UnitExists("target") then
		-- Hide all auras
		for i = 1, 5 do
			UFI_TargetFrame.buffs[i]:Hide()
			UFI_TargetFrame.debuffs[i]:Hide()
			UFI_TargetFrame.myDebuffs[i]:Hide()
		end
		return
	end

	-- Collect all buffs and sort by duration (shortest first)
	local allBuffs = {}
	for i = 1, 40 do
		local name, rank, icon, count, debuffType, duration, expirationTime = UnitBuff("target", i)
		if not name then
			break
		end

		local remainingTime = 999999 -- Default for permanent buffs (no duration)
		if duration and duration > 0 and expirationTime then
			remainingTime = expirationTime - GetTime()
		end

		table.insert(allBuffs, {
			icon = icon,
			count = count,
			duration = duration,
			expirationTime = expirationTime,
			remainingTime = remainingTime,
		})
	end

	-- Sort buffs: shortest duration first
	table.sort(allBuffs, function(a, b)
		return a.remainingTime < b.remainingTime
	end)

	-- Display up to 5 buffs
	for i = 1, 5 do
		if allBuffs[i] then
			local buff = UFI_TargetFrame.buffs[i]
			buff.icon:SetTexture(allBuffs[i].icon)

			-- Set cooldown for OmniCC
			if allBuffs[i].duration and allBuffs[i].duration > 0 and allBuffs[i].expirationTime then
				buff.cooldown:SetCooldown(allBuffs[i].expirationTime - allBuffs[i].duration, allBuffs[i].duration)
			end

			if allBuffs[i].count and allBuffs[i].count > 1 then
				buff.count:SetText(allBuffs[i].count)
				buff.count:Show()
			else
				buff.count:Hide()
			end
			buff:Show()
		else
			UFI_TargetFrame.buffs[i]:Hide()
		end
	end

	-- Collect all debuffs, separating player's from others'
	local myDebuffs = {}
	local otherDebuffs = {}

	for i = 1, 40 do
		local name, rank, icon, count, debuffType, duration, expirationTime, caster = UnitDebuff("target", i)
		if not name then
			break
		end

		local remainingTime = 999999 -- Default for permanent debuffs
		if duration and duration > 0 and expirationTime then
			remainingTime = expirationTime - GetTime()
		end

		local debuffData = {
			icon = icon,
			count = count,
			debuffType = debuffType,
			duration = duration,
			expirationTime = expirationTime,
			remainingTime = remainingTime,
		}

		if caster == "player" then
			table.insert(myDebuffs, debuffData)
		else
			table.insert(otherDebuffs, debuffData)
		end
	end

	-- Sort both lists by duration (shortest first)
	table.sort(myDebuffs, function(a, b)
		return a.remainingTime < b.remainingTime
	end)
	table.sort(otherDebuffs, function(a, b)
		return a.remainingTime < b.remainingTime
	end)

	-- Combine: my debuffs first, then others' debuffs
	local allDebuffs = {}
	for _, debuff in ipairs(myDebuffs) do
		table.insert(allDebuffs, debuff)
	end
	for _, debuff in ipairs(otherDebuffs) do
		table.insert(allDebuffs, debuff)
	end

	-- Display up to 5 debuffs in row 2
	for i = 1, 5 do
		if allDebuffs[i] then
			local debuff = UFI_TargetFrame.debuffs[i]
			debuff.icon:SetTexture(allDebuffs[i].icon)

			-- Set border color based on debuff type
			local color = DebuffTypeColor[allDebuffs[i].debuffType or "none"] or DebuffTypeColor["none"]
			debuff.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
			debuff.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
			debuff.border:SetVertexColor(color[1], color[2], color[3])

			-- Set cooldown for OmniCC
			if allDebuffs[i].duration and allDebuffs[i].duration > 0 and allDebuffs[i].expirationTime then
				debuff.cooldown:SetCooldown(
					allDebuffs[i].expirationTime - allDebuffs[i].duration,
					allDebuffs[i].duration
				)
			end

			if allDebuffs[i].count and allDebuffs[i].count > 1 then
				debuff.count:SetText(allDebuffs[i].count)
				debuff.count:Show()
			else
				debuff.count:Hide()
			end
			debuff:Show()
		else
			UFI_TargetFrame.debuffs[i]:Hide()
		end
	end

	-- Hide row 3 (myDebuffs) - no longer used
	for i = 1, 5 do
		UFI_TargetFrame.myDebuffs[i]:Hide()
	end
end

-------------------------------------------------------------------------------
-- EVENT HANDLING
-------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("UNIT_MAXHEALTH")
eventFrame:RegisterEvent("UNIT_POWER_FREQUENT")
eventFrame:RegisterEvent("UNIT_POWER_UPDATE")
eventFrame:RegisterEvent("UNIT_RAGE")
eventFrame:RegisterEvent("UNIT_ENERGY")
eventFrame:RegisterEvent("UNIT_FOCUS")
eventFrame:RegisterEvent("UNIT_RUNIC_POWER")
eventFrame:RegisterEvent("UNIT_MAXPOWER")
eventFrame:RegisterEvent("UNIT_PORTRAIT_UPDATE")
eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
eventFrame:RegisterEvent("UNIT_LEVEL")
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

eventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_LOGIN" then
		-- Create frames on login
		UFI_PlayerFrame = CreatePlayerFrame()
		UFI_TargetFrame = CreateTargetFrame()
		UFI_FocusFrame = CreateFocusFrame()
		UFI_TargetOfTargetFrame = CreateTargetOfTargetFrame()

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

		-- Also hide target of target frame if it exists
		if TargetFrameToT then
			TargetFrameToT:UnregisterAllEvents()
			TargetFrameToT:Hide()
			TargetFrameToT:SetAlpha(0)
		end

		-- Initial updates
		UpdatePlayerHealth()
		UpdatePlayerPower()
		UpdatePlayerPortrait()
		UpdatePlayerName()
		UpdatePlayerLevel()

		-- Update focus frame if focus exists
		if UnitExists("focus") then
			UpdateFocusFrame()
		end
	elseif event == "PLAYER_TARGET_CHANGED" then
		UpdateTargetHealth()
		UpdateTargetPower()
		UpdateTargetPortrait()
		UpdateTargetName()
		UpdateTargetLevel()
		UpdateTargetClassification()
		UpdateTargetAuras()
		UpdateTargetOfTarget()

		-- Check if target is already casting/channeling when we target them
		if UFI_TargetFrame and UFI_TargetFrame.castBar then
			local castBar = UFI_TargetFrame.castBar
			local name, nameSubtext, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible =
				UnitCastingInfo("target")
			if name then
				-- Target is casting
				castBar.value = (GetTime() * 1000 - startTime) / (endTime - startTime)
				castBar.startTime = startTime
				castBar.endTime = endTime
				castBar.casting = true
				castBar.channeling = false
				castBar.state = CASTBAR_STATE.CASTING

				castBar.icon:SetTexture(texture)
				castBar.text:SetText(text)
				castBar:SetStatusBarColor(1.0, 0.7, 0.0)
				castBar:SetValue(castBar.value)
				castBar:Show()
			else
				-- Check if channeling
				name, nameSubtext, text, texture, startTime, endTime, isTradeSkill, notInterruptible =
					UnitChannelInfo("target")
				if name then
					castBar.value = (endTime - GetTime() * 1000) / (endTime - startTime)
					castBar.startTime = startTime
					castBar.endTime = endTime
					castBar.casting = false
					castBar.channeling = true
					castBar.state = CASTBAR_STATE.CHANNELING

					castBar.icon:SetTexture(texture)
					castBar.text:SetText(text)
					castBar:SetStatusBarColor(0.0, 1.0, 0.0)
					castBar:SetValue(castBar.value)
					castBar:Show()
				else
					-- Not casting or channeling
					castBar.state = CASTBAR_STATE.HIDDEN
					castBar:Hide()
				end
			end
		end
	elseif event == "PLAYER_FOCUS_CHANGED" then
		UpdateFocusFrame()

		-- Check if focus is already casting/channeling when we focus them
		if UFI_FocusFrame and UFI_FocusFrame.castBar then
			local castBar = UFI_FocusFrame.castBar
			local name, nameSubtext, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible =
				UnitCastingInfo("focus")
			if name then
				-- Focus is casting
				castBar.value = (GetTime() * 1000 - startTime) / (endTime - startTime)
				castBar.startTime = startTime
				castBar.endTime = endTime
				castBar.spellName = text
				castBar.spellTexture = texture
				castBar.notInterruptible = notInterruptible
				castBar.state = CASTBAR_STATE.CASTING
				castBar.icon:SetTexture(texture)
				castBar.text:SetText(text)
				castBar:SetStatusBarColor(1.0, 0.7, 0.0)
				castBar:SetValue(castBar.value)
				castBar:Show()
			else
				-- Check for channeling
				name, nameSubtext, text, texture, startTime, endTime, isTradeSkill, notInterruptible =
					UnitChannelInfo("focus")
				if name then
					castBar.value = (endTime - GetTime() * 1000) / (endTime - startTime)
					castBar.startTime = startTime
					castBar.endTime = endTime
					castBar.spellName = text
					castBar.spellTexture = texture
					castBar.notInterruptible = notInterruptible
					castBar.state = CASTBAR_STATE.CHANNELING
					castBar.icon:SetTexture(texture)
					castBar.text:SetText(text)
					castBar:SetStatusBarColor(0.0, 1.0, 0.0)
					castBar:SetValue(castBar.value)
					castBar:Show()
				else
					-- Not casting or channeling
					castBar.state = CASTBAR_STATE.HIDDEN
					castBar:Hide()
				end
			end
		end
	elseif event == "UNIT_HEALTH" then
		local unit = ...
		if unit == "player" then
			UpdatePlayerHealth()
		elseif unit == "target" then
			UpdateTargetHealth()
		elseif unit == "focus" then
			UpdateFocusHealth()
		end
	elseif event == "UNIT_MAXHEALTH" then
		local unit = ...
		if unit == "player" then
			UpdatePlayerHealth()
		elseif unit == "target" then
			UpdateTargetHealth()
		elseif unit == "focus" then
			UpdateFocusHealth()
		end
	elseif
		event == "UNIT_POWER_FREQUENT"
		or event == "UNIT_POWER_UPDATE"
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
		end
	elseif event == "UNIT_MAXPOWER" then
		local unit = ...
		if unit == "player" then
			UpdatePlayerPower()
		elseif unit == "target" then
			UpdateTargetPower()
		elseif unit == "focus" then
			UpdateFocusPower()
		end
	elseif event == "UNIT_PORTRAIT_UPDATE" then
		local unit = ...
		if unit == "player" then
			UpdatePlayerPortrait()
		elseif unit == "target" then
			UpdateTargetPortrait()
		elseif unit == "focus" then
			UpdateFocusPortrait()
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
		end
	elseif event == "UNIT_AURA" then
		local unit = ...
		if unit == "target" then
			UpdateTargetAuras()
		elseif unit == "focus" then
			UpdateFocusAuras()
		end
	elseif event == "UNIT_TARGET" then
		local unit = ...
		if unit == "target" then
			UpdateTargetOfTarget()
		end
	elseif event == "PLAYER_UPDATE_RESTING" then
		UpdatePlayerLevel()

	-- Cast bar events
	elseif event == "UNIT_SPELLCAST_START" then
		local unit = ...
		if unit == "target" and UFI_TargetFrame and UFI_TargetFrame.castBar then
			-- WotLK 3.3.5: name, nameSubtext, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible
			local name, nameSubtext, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible =
				UnitCastingInfo(unit)
			if name then
				local castBar = UFI_TargetFrame.castBar
				castBar.state = CASTBAR_STATE.CASTING
				castBar.startTime = startTime / 1000
				castBar.endTime = endTime / 1000
				castBar.notInterruptible = notInterruptible or false
				castBar.spellName = name
				castBar.spellTexture = texture
				castBar.text:SetText(name)
				castBar.icon:SetTexture(texture)
				castBar:SetAlpha(1)
				castBar:Show()
			end
		elseif unit == "focus" and UFI_FocusFrame and UFI_FocusFrame.castBar then
			local name, nameSubtext, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible =
				UnitCastingInfo(unit)
			if name then
				local castBar = UFI_FocusFrame.castBar
				castBar.state = CASTBAR_STATE.CASTING
				castBar.startTime = startTime / 1000
				castBar.endTime = endTime / 1000
				castBar.notInterruptible = notInterruptible or false
				castBar.spellName = name
				castBar.spellTexture = texture
				castBar.text:SetText(name)
				castBar.icon:SetTexture(texture)
				castBar:SetAlpha(1)
				castBar:Show()
			end
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		local unit = ...
		if unit == "target" and UFI_TargetFrame and UFI_TargetFrame.castBar then
			-- WotLK 3.3.5: name, nameSubtext, text, texture, startTime, endTime, isTradeSkill, notInterruptible (no castID)
			local name, nameSubtext, text, texture, startTime, endTime, isTradeSkill, notInterruptible =
				UnitChannelInfo(unit)
			if name then
				local castBar = UFI_TargetFrame.castBar
				castBar.state = CASTBAR_STATE.CHANNELING
				castBar.startTime = startTime / 1000
				castBar.endTime = endTime / 1000
				castBar.notInterruptible = notInterruptible or false
				castBar.spellName = name
				castBar.spellTexture = texture
				castBar.text:SetText(name)
				castBar.icon:SetTexture(texture)
				castBar:SetAlpha(1)
				castBar:Show()
			end
		elseif unit == "focus" and UFI_FocusFrame and UFI_FocusFrame.castBar then
			local name, nameSubtext, text, texture, startTime, endTime, isTradeSkill, notInterruptible =
				UnitChannelInfo(unit)
			if name then
				local castBar = UFI_FocusFrame.castBar
				castBar.state = CASTBAR_STATE.CHANNELING
				castBar.startTime = startTime / 1000
				castBar.endTime = endTime / 1000
				castBar.notInterruptible = notInterruptible or false
				castBar.spellName = name
				castBar.spellTexture = texture
				castBar.text:SetText(name)
				castBar.icon:SetTexture(texture)
				castBar:SetAlpha(1)
				castBar:Show()
			end
		end
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		local unit = ...
		if unit == "target" and UFI_TargetFrame and UFI_TargetFrame.castBar then
			local castBar = UFI_TargetFrame.castBar
			if castBar.state == CASTBAR_STATE.CASTING or castBar.state == CASTBAR_STATE.CHANNELING then
				castBar.state = CASTBAR_STATE.FADING
				castBar.fadeStartTime = GetTime()
			end
		elseif unit == "focus" and UFI_FocusFrame and UFI_FocusFrame.castBar then
			local castBar = UFI_FocusFrame.castBar
			if castBar.state == CASTBAR_STATE.CASTING or castBar.state == CASTBAR_STATE.CHANNELING then
				castBar.state = CASTBAR_STATE.FADING
				castBar.fadeStartTime = GetTime()
			end
		end
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		local unit = ...
		if unit == "target" and UFI_TargetFrame and UFI_TargetFrame.castBar then
			local castBar = UFI_TargetFrame.castBar
			if castBar.state ~= CASTBAR_STATE.FINISHED then
				if event == "UNIT_SPELLCAST_INTERRUPTED" then
					castBar:SetStatusBarColor(1, 0, 0) -- Red
					castBar.text:SetText("Interrupted")
				else
					castBar:SetStatusBarColor(0.5, 0.5, 0.5) -- Gray
					castBar.text:SetText("Failed")
				end
				castBar:SetValue(1)
				castBar:SetAlpha(1)
				castBar:Show()
				castBar.state = CASTBAR_STATE.FINISHED
				castBar.holdUntil = GetTime() + 0.5
			end
		elseif unit == "focus" and UFI_FocusFrame and UFI_FocusFrame.castBar then
			local castBar = UFI_FocusFrame.castBar
			if castBar.state ~= CASTBAR_STATE.FINISHED then
				if event == "UNIT_SPELLCAST_INTERRUPTED" then
					castBar:SetStatusBarColor(1, 0, 0) -- Red
					castBar.text:SetText("Interrupted")
				else
					castBar:SetStatusBarColor(0.5, 0.5, 0.5) -- Gray
					castBar.text:SetText("Failed")
				end
				castBar:SetValue(1)
				castBar:SetAlpha(1)
				castBar:Show()
				castBar.state = CASTBAR_STATE.FINISHED
				castBar.holdUntil = GetTime() + 0.5
			end
		end
	elseif event == "UNIT_SPELLCAST_DELAYED" then
		local unit = ...
		if unit == "target" and UFI_TargetFrame and UFI_TargetFrame.castBar then
			local name, nameSubtext, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible =
				UnitCastingInfo(unit)
			if name then
				local castBar = UFI_TargetFrame.castBar
				castBar.startTime = startTime / 1000
				castBar.endTime = endTime / 1000
			end
		elseif unit == "focus" and UFI_FocusFrame and UFI_FocusFrame.castBar then
			local name, nameSubtext, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible =
				UnitCastingInfo(unit)
			if name then
				local castBar = UFI_FocusFrame.castBar
				castBar.startTime = startTime / 1000
				castBar.endTime = endTime / 1000
			end
		end
	elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
		local unit = ...
		if unit == "target" and UFI_TargetFrame and UFI_TargetFrame.castBar then
			local name, nameSubtext, text, texture, startTime, endTime, isTradeSkill, notInterruptible =
				UnitChannelInfo(unit)
			if name then
				local castBar = UFI_TargetFrame.castBar
				castBar.startTime = startTime / 1000
				castBar.endTime = endTime / 1000
			end
		elseif unit == "focus" and UFI_FocusFrame and UFI_FocusFrame.castBar then
			local name, nameSubtext, text, texture, startTime, endTime, isTradeSkill, notInterruptible =
				UnitChannelInfo(unit)
			if name then
				local castBar = UFI_FocusFrame.castBar
				castBar.startTime = startTime / 1000
				castBar.endTime = endTime / 1000
			end
		end
	elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
		local unit = ...
		if unit == "target" and UFI_TargetFrame and UFI_TargetFrame.castBar then
			UFI_TargetFrame.castBar.notInterruptible = false
		elseif unit == "focus" and UFI_FocusFrame and UFI_FocusFrame.castBar then
			UFI_FocusFrame.castBar.notInterruptible = false
		end
	elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
		local unit = ...
		if unit == "target" and UFI_TargetFrame and UFI_TargetFrame.castBar then
			UFI_TargetFrame.castBar.notInterruptible = true
		elseif unit == "focus" and UFI_FocusFrame and UFI_FocusFrame.castBar then
			UFI_FocusFrame.castBar.notInterruptible = true
		end
	end
end)

-- OnUpdate for cast bar
eventFrame:SetScript("OnUpdate", function(self, elapsed)
	if UFI_TargetFrame and UFI_TargetFrame.castBar then
		local state = UFI_TargetFrame.castBar.state
		if state ~= CASTBAR_STATE.HIDDEN then
			UpdateTargetCastBar(UFI_TargetFrame.castBar, elapsed)
		end
	end

	if UFI_FocusFrame and UFI_FocusFrame.castBar then
		local state = UFI_FocusFrame.castBar.state
		if state ~= CASTBAR_STATE.HIDDEN then
			UpdateFocusCastBar(UFI_FocusFrame.castBar, elapsed)
		end
	end
end)
