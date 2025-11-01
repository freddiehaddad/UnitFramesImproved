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
-- SHARED CONSTANTS AND HELPERS
-------------------------------------------------------------------------------

local STATUSBAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local FONT_DEFAULT = "Fonts\\FRIZQT__.TTF"

local FRAME_TEXTURES = {
	player = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare-Elite",
	default = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame",
	elite = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Elite",
	rare = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare",
	rareElite = "Interface\\AddOns\\UnitFramesImproved\\Textures\\UI-TargetingFrame-Rare-Elite",
}

local SELF_BUFF_EXCLUSIONS = {
	[72221] = true, -- Luck of the Draw
	[91769] = true, -- Keeper's Scroll: Steadfast
	[91794] = true,
	[91796] = true,
	[91803] = true, -- Keeper's Scroll: Ghost Runner
	[91810] = true, -- Keeper's Scroll: Gathering Speed
	[91814] = true,
	[170021] = true,
	[498752] = true,
	[993943] = true, -- Titan Scroll: Norgannon
	[993955] = true, -- Titan Scroll: Khaz'goroth
	[993957] = true, -- Titan Scroll: Eonar
	[993959] = true, -- Titan Scroll: Aggramar
	[993961] = true, -- Titan Scroll: Golganneth
	[9931032] = true,
}

local function CreateStatusBar(parent, size, anchor)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetSize(size.width, size.height)
	local point = (anchor and anchor.point) or "CENTER"
	local relativeTo = (anchor and anchor.relativeTo) or parent
	local relativePoint = (anchor and anchor.relativePoint) or point
	local offsetX = (anchor and anchor.x) or 0
	local offsetY = (anchor and anchor.y) or 0
	bar:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
	bar:SetStatusBarTexture(STATUSBAR_TEXTURE)
	bar:GetStatusBarTexture():SetHorizTile(false)
	bar:GetStatusBarTexture():SetVertTile(false)
	bar:GetStatusBarTexture():SetDrawLayer("BACKGROUND", -8)
	bar:SetMinMaxValues(0, 100)
	bar:SetValue(100)
	local parentLevel = parent:GetFrameLevel() or 0
	bar:SetFrameLevel(math.max(parentLevel - 1, 0))

	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(0, 0, 0, 0.35)
	bg:SetAllPoints(bar)
	bar.bg = bg

	if bar.SetBackdrop then
		bar:SetBackdrop(nil)
	end

	return bar
end

local function AttachFrameTexture(frame, texturePath, opts)
	local layer = opts and opts.layer or "BORDER"
	local subLevel = opts and opts.subLevel or 0
	local texture = frame:CreateTexture(nil, layer, nil, subLevel)
	texture:SetTexture(texturePath)
	texture:SetSize(opts and opts.width or 232, opts and opts.height or 110)
	local point = opts and opts.point or "TOPLEFT"
	local relativeTo = opts and opts.relativeTo or frame
	local relativePoint = opts and opts.relativePoint or point
	local offsetX = opts and opts.x or 0
	local offsetY = opts and opts.y or 0
	texture:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY)
	if opts and opts.mirror then
		texture:SetTexCoord(1, 0, 0, 1)
	end
	return texture
end

local function CreateFontString(parent, fontOptions)
	local fontString = parent:CreateFontString(nil, "OVERLAY")
	fontString:SetFont(fontOptions.path or FONT_DEFAULT, fontOptions.size, fontOptions.flags or "OUTLINE")
	local relativeTo = fontOptions.relativeTo or parent
	local relativePoint = fontOptions.relativePoint or fontOptions.point
	fontString:SetPoint(fontOptions.point, relativeTo, relativePoint, fontOptions.x or 0, fontOptions.y or 0)
	if fontOptions.color then
		fontString:SetTextColor(fontOptions.color.r, fontOptions.color.g, fontOptions.color.b)
	end
	fontString:SetDrawLayer("OVERLAY", fontOptions.drawLayer or 7)
	return fontString
end

local function CreatePortrait(frame, opts)
	local portrait = frame:CreateTexture(nil, "BACKGROUND", nil, 5)
	portrait:SetSize(opts.width or 50, opts.height or 48)
	portrait:SetPoint(opts.point, opts.relativeTo or frame, opts.relativePoint or opts.point, opts.x or 0, opts.y or 0)
	local crop = opts.crop or 0.08
	portrait:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
	return portrait
end

local function CreateAuraIcon(parent, size)
	local iconFrame = CreateFrame("Frame", nil, parent)
	iconFrame:SetSize(size, size)

	iconFrame.icon = iconFrame:CreateTexture(nil, "ARTWORK")
	iconFrame.icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
	iconFrame.icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
	iconFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	iconFrame.border = iconFrame:CreateTexture(nil, "OVERLAY")
	iconFrame.border:SetAllPoints()
	iconFrame.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
	iconFrame.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)

	iconFrame.cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
	iconFrame.cooldown:SetAllPoints()

	iconFrame.count = iconFrame:CreateFontString(nil, "OVERLAY")
	iconFrame.count:SetFont(FONT_DEFAULT, 10, "OUTLINE")
	iconFrame.count:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)

	iconFrame:Hide()
	return iconFrame
end

local function CreateAuraRow(parent, rowOptions)
	local icons = {}
	for i = 1, rowOptions.count do
		local icon = CreateAuraIcon(parent, rowOptions.size)
		if i == 1 then
			local anchor = rowOptions.anchor
			icon:SetPoint(
				anchor.point,
				anchor.relativeTo or parent,
				anchor.relativePoint or anchor.point,
				anchor.x or 0,
				anchor.y or 0
			)
		else
			icon:SetPoint("LEFT", icons[i - 1], "RIGHT", rowOptions.spacing or 2, 0)
		end
		icons[i] = icon
	end
	return icons
end

local function SetAuraRowAnchor(row, anchor)
	if not row or not row[1] or not anchor then
		return
	end

	local firstIcon = row[1]
	local point = anchor.point or "TOPLEFT"
	local relativePoint = anchor.relativePoint or point
	local xOffset = anchor.x or 0
	local yOffset = anchor.y or 0
	local relativeTo = anchor.relativeTo or firstIcon:GetParent()

	firstIcon:ClearAllPoints()
	firstIcon:SetPoint(point, relativeTo, relativePoint, xOffset, yOffset)
end

local RAID_TARGET_ICON_OPTIONS = {
	{ name = RAID_TARGET_1, index = 1, r = 1.0, g = 1.0, b = 0.0 },
	{ name = RAID_TARGET_2, index = 2, r = 1.0, g = 0.5, b = 0.0 },
	{ name = RAID_TARGET_3, index = 3, r = 0.6, g = 0.4, b = 1.0 },
	{ name = RAID_TARGET_4, index = 4, r = 0.0, g = 1.0, b = 0.0 },
	{ name = RAID_TARGET_5, index = 5, r = 0.7, g = 0.7, b = 0.7 },
	{ name = RAID_TARGET_6, index = 6, r = 0.0, g = 0.5, b = 1.0 },
	{ name = RAID_TARGET_7, index = 7, r = 1.0, g = 0.0, b = 0.0 },
	{ name = RAID_TARGET_8, index = 8, r = 1.0, g = 1.0, b = 1.0 },
}

local function CreateUnitInteractionDropdown(unit, dropdownName, options)
	local fallbackTitle = (options and options.fallbackTitle) or unit
	local extraLevel1Buttons = options and options.extraLevel1Buttons
	local level1Builder = options and options.level1Builder

	local level2Handlers
	if options then
		local provided = options.level2Handlers
		local legacy = options.extraLevel2Handlers
		if provided and legacy and provided ~= legacy then
			level2Handlers = {}
			for key, handler in pairs(legacy) do
				level2Handlers[key] = handler
			end
			for key, handler in pairs(provided) do
				level2Handlers[key] = handler
			end
		else
			level2Handlers = provided or legacy
		end
	end

	local dropdown = CreateFrame("Frame", dropdownName, UIParent, "UIDropDownMenuTemplate")
	dropdown.displayMode = "MENU"

	local function AddButton(level, builder)
		local info = UIDropDownMenu_CreateInfo()
		builder(info)
		UIDropDownMenu_AddButton(info, level)
	end

	local function AddRaidTargetMenu(level)
		local currentTarget = GetRaidTargetIndex(unit)

		for _, icon in ipairs(RAID_TARGET_ICON_OPTIONS) do
			local iconIndex = icon.index
			local iconName = icon.name
			local r, g, b = icon.r, icon.g, icon.b
			AddButton(level, function(info)
				info.text = iconName
				info.func = function()
					SetRaidTarget(unit, iconIndex)
				end
				info.icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. iconIndex
				info.tCoordLeft = 0
				info.tCoordRight = 1
				info.tCoordTop = 0
				info.tCoordBottom = 1
				info.colorCode = string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
				info.checked = (currentTarget == iconIndex)
			end)
		end

		AddButton(level, function(info)
			info.text = RAID_TARGET_NONE
			info.func = function()
				SetRaidTarget(unit, 0)
			end
			info.checked = (currentTarget == nil or currentTarget == 0)
		end)
	end

	local function AddLevelOneButtons(level)
		local unitName = UnitName(unit)
		local isPlayer = UnitIsPlayer(unit)

		AddButton(level, function(info)
			info.text = unitName or fallbackTitle
			info.isTitle = true
			info.notCheckable = true
		end)

		AddButton(level, function(info)
			local targetName = unitName
			info.text = WHISPER
			info.notCheckable = true
			info.func = function()
				if targetName then
					ChatFrame_SendTell(targetName)
				end
			end
			info.disabled = not (isPlayer and targetName)
		end)

		AddButton(level, function(info)
			info.text = INSPECT
			info.notCheckable = true
			info.func = function()
				InspectUnit(unit)
			end
			info.disabled = not CanInspect(unit)
		end)

		AddButton(level, function(info)
			local targetName = unitName
			info.text = INVITE
			info.notCheckable = true
			info.func = function()
				if targetName then
					InviteUnit(targetName)
				end
			end
			info.disabled = not (isPlayer and targetName and not UnitInParty(unit) and not UnitInRaid(unit))
		end)

		AddButton(level, function(info)
			local targetName = unitName
			info.text = COMPARE_ACHIEVEMENTS
			info.notCheckable = true
			info.func = function()
				if not AchievementFrame then
					AchievementFrame_LoadUI()
				end
				if AchievementFrame and targetName then
					AchievementFrame_DisplayComparison(targetName)
				end
			end
			info.disabled = not (isPlayer and targetName)
		end)

		AddButton(level, function(info)
			info.text = TRADE
			info.notCheckable = true
			info.func = function()
				InitiateTrade(unit)
			end
			info.disabled = not (isPlayer and CheckInteractDistance(unit, 2))
		end)

		AddButton(level, function(info)
			info.text = FOLLOW
			info.notCheckable = true
			info.func = function()
				FollowUnit(unit)
			end
			info.disabled = not isPlayer
		end)

		AddButton(level, function(info)
			info.text = DUEL
			info.notCheckable = true
			info.func = function()
				StartDuel(unit)
			end
			info.disabled = not (isPlayer and CheckInteractDistance(unit, 3))
		end)

		AddButton(level, function(info)
			info.text = RAID_TARGET_ICON
			info.notCheckable = true
			info.hasArrow = true
			info.value = "RAID_TARGET"
		end)

		if extraLevel1Buttons then
			extraLevel1Buttons(level, unit, AddButton)
		end

		AddButton(level, function(info)
			info.text = CANCEL
			info.notCheckable = true
			info.func = CloseDropDownMenus
		end)
	end

	dropdown.initialize = function(self, level)
		if not level then
			return
		end

		if level == 1 then
			if level1Builder then
				level1Builder(level, unit, AddButton, fallbackTitle)
			else
				AddLevelOneButtons(level)
			end
		elseif level == 2 and UIDROPDOWNMENU_MENU_VALUE == "RAID_TARGET" then
			AddRaidTargetMenu(level)
		elseif level2Handlers then
			local handler = level2Handlers[UIDROPDOWNMENU_MENU_VALUE]
			if handler then
				handler(level, unit, AddButton)
			end
		end
	end

	return dropdown
end

-------------------------------------------------------------------------------
-- MOVABLE FRAMES SYSTEM
-------------------------------------------------------------------------------

-- State variables
local frameOverlays = {}
local isUnlocked = false
local pendingPositions = {}

-- Default frame positions
local defaultPositions = {
	UFI_PlayerFrame = {
		point = "TOPLEFT",
		relativePoint = "TOPLEFT",
		x = -19,
		y = -4,
	},
	UFI_TargetFrame = {
		point = "TOPLEFT",
		relativePoint = "TOPLEFT",
		x = 250,
		y = -4,
	},
	UFI_FocusFrame = {
		point = "TOPLEFT",
		relativePoint = "TOPLEFT",
		x = 250,
		y = -250,
	},
}

-- Initialize saved variables
local function InitializeDatabase()
	if not UnitFramesImprovedDB then
		UnitFramesImprovedDB = {
			version = "1.0.0",
			isUnlocked = false,
			positions = {},
		}
	end

	-- Migrate old versions if needed
	if not UnitFramesImprovedDB.version or UnitFramesImprovedDB.version < "1.0.0" then
		UnitFramesImprovedDB.version = "1.0.0"
	end
end

-- Validate position data
local function ValidatePosition(pos)
	if not pos then
		return false
	end
	if type(pos.x) ~= "number" or type(pos.y) ~= "number" then
		return false
	end
	if not pos.point or not pos.relativePoint then
		return false
	end

	-- Check if position is within screen bounds (with some margin)
	local screenWidth = GetScreenWidth()
	local screenHeight = GetScreenHeight()

	if pos.x < -300 or pos.x > screenWidth + 100 then
		return false
	end
	if pos.y > 100 or pos.y < -screenHeight - 100 then
		return false
	end

	return true
end

-- Check if frames can be repositioned
local function CanRepositionFrames()
	return not InCombatLockdown()
end

-- Save position for a frame
local function SavePosition(frameName, point, relativePoint, x, y)
	if not UnitFramesImprovedDB.positions then
		UnitFramesImprovedDB.positions = {}
	end

	UnitFramesImprovedDB.positions[frameName] = {
		point = point,
		relativePoint = relativePoint,
		x = x,
		y = y,
	}
end

-- Apply position to a frame
local function ApplyPosition(frameName)
	local frame = _G[frameName]
	if not frame then
		return
	end

	local pos = UnitFramesImprovedDB.positions[frameName]
	if not pos or not ValidatePosition(pos) then
		-- Use default position
		pos = defaultPositions[frameName]
		if not pos then
			return
		end
	end

	if CanRepositionFrames() then
		frame:ClearAllPoints()
		frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
		pendingPositions[frameName] = nil

		-- Sync overlay position to match frame
		local overlay = frameOverlays[frameName]
		if overlay then
			overlay:ClearAllPoints()
			overlay:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
		end
	else
		-- Save for later
		pendingPositions[frameName] = true
	end
end

-- Apply all pending positions (called after combat ends)
local function ApplyPendingPositions()
	if not CanRepositionFrames() then
		return
	end

	for frameName, _ in pairs(pendingPositions) do
		ApplyPosition(frameName)
	end

	if next(pendingPositions) then
		Print("Frame positions applied!")
	end
end

-- Reset frame to default position
local function ResetFramePosition(frameName)
	local pos = defaultPositions[frameName]
	if not pos then
		Print("Unknown frame: " .. frameName)
		return
	end

	SavePosition(frameName, pos.point, pos.relativePoint, pos.x, pos.y)
	ApplyPosition(frameName)
	Print("Reset " .. frameName .. " to default position")
end

-- Create overlay for a frame
local function CreateOverlay(frame, frameName)
	local overlay = CreateFrame("Frame", frameName .. "_Overlay", UIParent)
	overlay:SetFrameStrata("HIGH")
	overlay:SetFrameLevel(100)
	overlay:EnableMouse(false)
	overlay:SetMovable(true)
	overlay:RegisterForDrag("LeftButton")
	overlay:SetClampedToScreen(true)
	overlay:Hide()

	-- Match frame's size and position exactly
	overlay:SetSize(frame:GetWidth(), frame:GetHeight())
	overlay:SetScale(frame:GetScale())
	local point, relativeTo, relativePoint, x, y = frame:GetPoint()
	overlay:SetPoint(point, relativeTo, relativePoint, x, y)

	-- Visual border
	overlay.border = overlay:CreateTexture(nil, "OVERLAY")
	overlay.border:SetAllPoints()
	overlay.border:SetColorTexture(0, 1, 0, 0.5)

	-- Label
	overlay.label = overlay:CreateFontString(nil, "OVERLAY")
	overlay.label:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
	overlay.label:SetPoint("CENTER")
	overlay.label:SetText(frameName:gsub("UFI_", ""))

	-- Store frame reference
	overlay.secureFrame = frame
	overlay.isDragging = false
	overlay.dragStartX = 0
	overlay.dragStartY = 0

	-- Mouse down - prepare for drag
	overlay:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" and isUnlocked then
			self.isDragging = true
			self.dragStartX, self.dragStartY = GetCursorPosition()
			local scale = self:GetEffectiveScale()
			self.dragStartX = self.dragStartX / scale
			self.dragStartY = self.dragStartY / scale

			local _, _, _, x, y = self:GetPoint()
			self.startX = x
			self.startY = y

			-- Visual feedback
			self:SetFrameLevel(110)
			self.border:SetColorTexture(1, 1, 0, 0.7) -- Yellow while dragging
		end
	end)

	-- Mouse up - finish drag
	overlay:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and self.isDragging then
			self.isDragging = false

			-- Reset frame level
			self:SetFrameLevel(100)
			self.border:SetColorTexture(0, 1, 0, 0.5) -- Back to green

			-- Get new position from overlay
			local point, _, relativePoint, x, y = self:GetPoint()

			-- Save position
			SavePosition(frameName, point, relativePoint, x, y)

			-- Try to apply to actual frame
			if CanRepositionFrames() then
				frame:ClearAllPoints()
				frame:SetPoint(point, UIParent, relativePoint, x, y)
				Print(frameName:gsub("UFI_", "") .. " position updated!")
			else
				pendingPositions[frameName] = true
				self.border:SetColorTexture(1, 0.5, 0, 0.5) -- Orange for pending
				Print(frameName:gsub("UFI_", "") .. " position saved! Will apply after combat.")
			end
		end
	end)

	-- Update position while dragging
	overlay:SetScript("OnUpdate", function(self)
		if self.isDragging then
			-- Check if mouse button is still down
			if not IsMouseButtonDown("LeftButton") then
				-- Mouse was released, finish the drag
				self.isDragging = false

				-- Reset frame level
				self:SetFrameLevel(100)
				self.border:SetColorTexture(0, 1, 0, 0.5) -- Back to green

				-- Get new position from overlay
				local point, _, relativePoint, x, y = self:GetPoint()

				-- Save position
				SavePosition(frameName, point, relativePoint, x, y)

				-- Try to apply to actual frame
				if CanRepositionFrames() then
					frame:ClearAllPoints()
					frame:SetPoint(point, UIParent, relativePoint, x, y)
					Print(frameName:gsub("UFI_", "") .. " position updated!")
				else
					pendingPositions[frameName] = true
					self.border:SetColorTexture(1, 0.5, 0, 0.5) -- Orange for pending
					Print(frameName:gsub("UFI_", "") .. " position saved! Will apply after combat.")
				end
				return
			end

			local cursorX, cursorY = GetCursorPosition()
			local scale = self:GetEffectiveScale()
			cursorX = cursorX / scale
			cursorY = cursorY / scale

			local deltaX = cursorX - self.dragStartX
			local deltaY = cursorY - self.dragStartY

			local newX = self.startX + deltaX
			local newY = self.startY + deltaY

			self:ClearAllPoints()
			self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", newX, newY)
		end
	end)

	-- Mouse enter/leave for better visual feedback
	overlay:SetScript("OnEnter", function(self)
		if isUnlocked and not self.isDragging then
			self.border:SetColorTexture(0.5, 1, 0.5, 0.7) -- Brighter green on hover
		end
	end)

	overlay:SetScript("OnLeave", function(self)
		if isUnlocked and not self.isDragging then
			self.border:SetColorTexture(0, 1, 0, 0.5) -- Normal green
		end
	end)

	-- Store reference
	frameOverlays[frameName] = overlay

	return overlay
end

-- Unlock frames for movement
local function UnlockFrames()
	if InCombatLockdown() then
		Print("|cffff0000Cannot unlock frames during combat!|r")
		return
	end

	isUnlocked = true
	UnitFramesImprovedDB.isUnlocked = true

	for frameName, overlay in pairs(frameOverlays) do
		overlay:Show()
		overlay:EnableMouse(true)
		overlay.border:SetColorTexture(0, 1, 0, 0.5) -- Green for unlocked
	end

	Print("Frames unlocked! Drag to reposition. Type /ufi lock to save.")
end

-- Lock frames and save positions
local function LockFrames()
	isUnlocked = false
	UnitFramesImprovedDB.isUnlocked = false

	-- Hide overlays
	for _, overlay in pairs(frameOverlays) do
		overlay:Hide()
		overlay:EnableMouse(false)
	end

	-- Apply any pending positions if possible
	if CanRepositionFrames() then
		ApplyPendingPositions()
		Print("Frames locked and positions saved!")
	else
		Print("Frames locked! Positions will apply after combat.")
	end
end

-- Handle combat start
local function OnCombatStart()
	if isUnlocked then
		-- Disable dragging during combat
		for _, overlay in pairs(frameOverlays) do
			overlay:EnableMouse(false)
			overlay.border:SetColorTexture(1, 0, 0, 0.5) -- Red for locked
			overlay.label:SetText(overlay.label:GetText() .. " (COMBAT)")
		end
		Print("|cffff8800Frame movement disabled during combat!|r")
	end
end

-- Handle combat end
local function OnCombatEnd()
	-- Apply pending positions
	ApplyPendingPositions()

	-- Re-enable dragging if unlocked
	if isUnlocked then
		for _, overlay in pairs(frameOverlays) do
			overlay:EnableMouse(true)
			overlay.border:SetColorTexture(0, 1, 0, 0.5) -- Back to green
			overlay.label:SetText(overlay.label:GetText():gsub(" %(COMBAT%)", ""))
		end
		Print("Frame movement re-enabled!")
	end
end

-- Slash command handler
SLASH_UFI1 = "/ufi"
SlashCmdList["UFI"] = function(msg)
	local cmd, arg = msg:match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()

	if cmd == "unlock" then
		UnlockFrames()
	elseif cmd == "lock" then
		LockFrames()
	elseif cmd == "reset" then
		if arg and arg ~= "" then
			local frameName = "UFI_" .. arg:sub(1, 1):upper() .. arg:sub(2):lower() .. "Frame"
			ResetFramePosition(frameName)
		else
			-- Reset all frames
			for frameName, _ in pairs(defaultPositions) do
				ResetFramePosition(frameName)
			end
		end
	elseif cmd == "help" or cmd == "" then
		Print("|cff00ff00UnitFramesImproved v1.0.0|r")
		Print("Available commands:")
		Print("  |cffffcc00/ufi unlock|r - Unlock frames for repositioning")
		Print("  |cffffcc00/ufi lock|r - Lock frames and save positions")
		Print("  |cffffcc00/ufi reset [frame]|r - Reset frame(s) to default position")
		Print(
			"    Examples: |cff888888/ufi reset player|r, |cff888888/ufi reset target|r, |cff888888/ufi reset|r (resets all)"
		)
		Print("  |cffffcc00/ufi help|r - Show this help message")
	else
		Print("Unknown command. Type |cffffcc00/ufi help|r for available commands.")
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
	frame:SetFrameStrata("LOW")
	frame:SetFrameLevel(5)
	frame:SetScale(1.15) -- Slightly larger than default

	local visual = CreateFrame("Frame", nil, frame)
	visual:SetAllPoints(frame)
	visual:SetFrameStrata("LOW")
	visual:SetFrameLevel(frame:GetFrameLevel() + 15)
	frame.visualLayer = visual

	frame.healthBar = CreateStatusBar(visual, { width = 108, height = 24 }, {
		point = "TOPLEFT",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = 97,
		y = -20,
	})

	frame.powerBar = CreateStatusBar(visual, { width = 108, height = 9 }, {
		point = "TOPLEFT",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = 97,
		y = -46,
	})

	frame.texture = AttachFrameTexture(visual, FRAME_TEXTURES.player, { mirror = true })

	frame.portrait = CreatePortrait(visual, {
		point = "CENTER",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = 68,
		y = -38,
	})
	SetPortraitTexture(frame.portrait, "player")

	frame.portraitMask = AttachFrameTexture(visual, FRAME_TEXTURES.player, { mirror = true, subLevel = 5 })
	frame.portraitMask:SetBlendMode("BLEND")

	-- Level/Rest indicator text (displayed in the circular area at bottom left of portrait)
	frame.levelText = CreateFontString(visual, {
		point = "CENTER",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = 48,
		y = -56,
		size = 8,
		flags = "OUTLINE",
		drawLayer = 0,
		color = { r = 1, g = 0.82, b = 0 },
	})
	frame.levelText:SetParent(visual)

	-- Unit name (OVERLAY layer - drawn on top of everything)
	frame.nameText = CreateFontString(frame.healthBar, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = 6,
		size = 7,
		flags = "OUTLINE",
		drawLayer = 7,
	})
	frame.nameText:SetText(UnitName("player"))

	-- Health text (OVERLAY layer - drawn on top of everything)
	frame.healthText = CreateFontString(frame.healthBar, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = -6,
		size = 8,
		flags = "OUTLINE",
		drawLayer = 7,
		color = { r = 1, g = 1, b = 1 },
	})
	frame.healthText:SetText("")

	-- Power text (OVERLAY layer - drawn on top of everything)
	-- Must be child of main frame, not powerBar, to render above frame texture
	frame.powerText = CreateFontString(visual, {
		point = "CENTER",
		relativeTo = frame.powerBar,
		relativePoint = "CENTER",
		x = 0,
		y = 1,
		size = 7,
		flags = "OUTLINE",
		drawLayer = 7,
		color = { r = 1, g = 1, b = 1 },
	})
	frame.powerText:SetText("")

	frame.selfBuffs = CreateAuraRow(frame, {
		count = 5,
		size = 20,
		spacing = 2,
		anchor = {
			point = "BOTTOMLEFT",
			relativeTo = frame.healthBar,
			relativePoint = "TOPLEFT",
			x = 2,
			y = 4,
		},
	})
	for i = 1, #frame.selfBuffs do
		frame.selfBuffs[i]:SetParent(visual)
	end
	for i = 1, #frame.selfBuffs do
		frame.selfBuffs[i].border:SetVertexColor(1, 1, 1)
	end

	-- Enable mouse clicks and set up secure click handling
	frame:EnableMouse(true)
	frame:RegisterForClicks("AnyUp")

	-- Create custom dropdown menu via shared helper
	local dropdown = CreateUnitInteractionDropdown("player", "UFI_PlayerFrameDropDown", {
		fallbackTitle = PLAYER or "Player",
		level1Builder = function(level, unitId, addButton, defaultTitle)
			if level ~= 1 then
				return
			end

			local unitName = UnitName(unitId) or defaultTitle or "Player"

			addButton(level, function(info)
				info.text = unitName
				info.isTitle = true
				info.notCheckable = true
			end)

			addButton(level, function(info)
				info.text = DUNGEON_DIFFICULTY
				info.notCheckable = true
				info.hasArrow = true
				info.value = "DUNGEON_DIFFICULTY"
			end)

			addButton(level, function(info)
				info.text = RAID_DIFFICULTY
				info.notCheckable = true
				info.hasArrow = true
				info.value = "RAID_DIFFICULTY"
			end)

			addButton(level, function(info)
				info.text = RESET_INSTANCES
				info.notCheckable = true
				info.hasArrow = true
				info.value = "RESET_INSTANCES"
			end)

			addButton(level, function(info)
				info.text = RAID_TARGET_ICON
				info.notCheckable = true
				info.hasArrow = true
				info.value = "RAID_TARGET"
			end)

			local partyMemberCount = GetNumPartyMembers()
			local raidMemberCount = GetNumRaidMembers()
			if partyMemberCount > 0 or raidMemberCount > 0 then
				local isRaid = raidMemberCount > 0
				local leaveText
				if isRaid then
					leaveText = LEAVE_RAID or LEAVE_GROUP or LEAVE_PARTY or "Leave Raid"
				else
					leaveText = LEAVE_PARTY or LEAVE_GROUP or "Leave Party"
				end

				addButton(level, function(leaveInfo)
					leaveInfo.text = leaveText
					leaveInfo.notCheckable = true
					leaveInfo.func = function()
						LeaveParty()
					end
				end)
			end

			addButton(level, function(info)
				info.text = CANCEL
				info.notCheckable = true
				info.func = function()
					CloseDropDownMenus()
				end
			end)
		end,
		level2Handlers = {
			DUNGEON_DIFFICULTY = function(level, unitId, addButton)
				local currentDifficulty = GetDungeonDifficulty()
				local options = {
					{ text = "5 Player", value = 1 },
					{ text = "5 Player (Heroic)", value = 2 },
					{ text = "5 Player (Mythic)", value = 3 },
				}

				for _, option in ipairs(options) do
					addButton(level, function(info)
						info.text = option.text
						info.func = function()
							SetDungeonDifficulty(option.value)
						end
						info.checked = (currentDifficulty == option.value)
					end)
				end
			end,
			RAID_DIFFICULTY = function(level, unitId, addButton)
				local currentDifficulty = GetRaidDifficulty()
				local options = {
					{ text = "Normal (10-25 Players)", value = 1 },
					{ text = "Heroic (10-25 Players)", value = 2 },
					{ text = "Mythic (10-25 Players)", value = 3 },
					{ text = "Ascended (10-25 Players)", value = 4 },
				}

				for _, option in ipairs(options) do
					addButton(level, function(info)
						info.text = option.text
						info.func = function()
							SetRaidDifficulty(option.value)
						end
						info.checked = (currentDifficulty == option.value)
					end)
				end
			end,
			RESET_INSTANCES = function(level, unitId, addButton)
				addButton(level, function(info)
					info.text = RESET_ALL_DUNGEONS
					info.notCheckable = true
					info.func = function()
						StaticPopup_Show("CONFIRM_RESET_INSTANCES")
					end
				end)
			end,
		},
	})

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

local castBarsByUnit = {}

local function CreateCastBar(parent, unit, options)
	options = options or {}

	local castBar = CreateFrame("StatusBar", nil, parent)
	castBar:SetSize(options.width or 148, options.height or 12)
	local anchor = options.anchor or { point = "TOP", relativeTo = parent, relativePoint = "BOTTOM", x = 0, y = -6 }
	castBar:SetPoint(
		anchor.point,
		anchor.relativeTo or parent,
		anchor.relativePoint or anchor.point,
		anchor.x or 0,
		anchor.y or -6
	)
	castBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	castBar:GetStatusBarTexture():SetHorizTile(false)
	castBar:GetStatusBarTexture():SetVertTile(false)
	castBar:SetMinMaxValues(0, 1)
	castBar:SetValue(0)
	castBar:Hide()

	local bg = castBar:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(0, 0, 0, 0.5)
	bg:SetAllPoints(castBar)

	local border = castBar:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border-Small")
	border:SetSize(195, 50)
	border:SetPoint("TOP", castBar, "TOP", 0, 20)

	local text = castBar:CreateFontString(nil, "OVERLAY")
	text:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	text:SetPoint("LEFT", castBar, "LEFT", 2, 1)
	text:SetTextColor(1, 1, 1)
	castBar.text = text

	local time = castBar:CreateFontString(nil, "OVERLAY")
	time:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
	time:SetPoint("RIGHT", castBar, "RIGHT", -2, 1)
	time:SetTextColor(1, 1, 1)
	castBar.time = time

	local icon = castBar:CreateTexture(nil, "OVERLAY")
	icon:SetSize(16, 16)
	icon:SetPoint("RIGHT", castBar, "LEFT", options.iconOffsetX or -5, options.iconOffsetY or 0)
	castBar.icon = icon

	castBar.unit = unit
	castBar.state = CASTBAR_STATE.HIDDEN
	castBar.startTime = 0
	castBar.endTime = 0
	castBar.notInterruptible = false
	castBar.holdUntil = 0
	castBar.fadeStartTime = 0
	castBar.spellName = ""
	castBar.spellTexture = ""

	castBarsByUnit[unit] = castBar
	return castBar
end

local function UpdateCastBar(castBar)
	if not castBar or castBar.state == CASTBAR_STATE.HIDDEN then
		return
	end

	local unit = castBar.unit
	if not unit or not UnitExists(unit) then
		castBar:Hide()
		castBar.state = CASTBAR_STATE.HIDDEN
		return
	end

	local currentTime = GetTime()
	local state = castBar.state

	if state == CASTBAR_STATE.FINISHED then
		if currentTime >= castBar.holdUntil then
			castBar.state = CASTBAR_STATE.FADING
			castBar.fadeStartTime = currentTime
		end
		return
	end

	if state == CASTBAR_STATE.FADING then
		local fadeDuration = 1
		local fadeElapsed = currentTime - castBar.fadeStartTime

		if fadeElapsed >= fadeDuration then
			castBar:Hide()
			castBar:SetAlpha(1)
			castBar.state = CASTBAR_STATE.HIDDEN
		else
			local alpha = 1 - (fadeElapsed / fadeDuration)
			castBar:SetAlpha(alpha)
		end
		return
	end

	if state == CASTBAR_STATE.CASTING or state == CASTBAR_STATE.CHANNELING then
		local remaining = castBar.endTime - currentTime
		if remaining < 0 then
			castBar:SetValue(1)
			return
		end

		local duration = castBar.endTime - castBar.startTime
		local progress
		if state == CASTBAR_STATE.CHANNELING then
			progress = duration > 0 and (remaining / duration) or 0
		else
			progress = duration > 0 and (1 - (remaining / duration)) or 0
		end

		castBar:SetValue(progress)
		castBar.time:SetText(string.format("%.1f", remaining))

		if castBar.notInterruptible then
			castBar:SetStatusBarColor(0.5, 0.5, 0.5)
		else
			castBar:SetStatusBarColor(1, 0.7, 0)
		end
	end
end

local function BeginCast(unit, isChannel)
	local castBar = castBarsByUnit[unit]
	if not castBar then
		return
	end

	local info = isChannel and { UnitChannelInfo(unit) } or { UnitCastingInfo(unit) }
	local name = info[1]
	if not name then
		return
	end

	local texture = info[4]
	local startTime = info[5]
	local endTime = info[6]
	local notInterruptible = isChannel and (info[8] or false) or (info[9] or false)

	castBar.state = isChannel and CASTBAR_STATE.CHANNELING or CASTBAR_STATE.CASTING
	castBar.startTime = (startTime or 0) / 1000
	castBar.endTime = (endTime or 0) / 1000
	castBar.notInterruptible = notInterruptible
	castBar.holdUntil = 0
	castBar.fadeStartTime = 0
	castBar.spellName = name
	castBar.spellTexture = texture or ""
	castBar:SetAlpha(1)
	castBar:SetValue(isChannel and 1 or 0)
	castBar.text:SetText(name)
	castBar.time:SetText("")
	castBar.icon:SetTexture(texture)
	castBar:SetStatusBarColor(1, 0.7, 0)
	castBar:Show()
	UpdateCastBar(castBar)
end

local function StopCast(unit)
	local castBar = castBarsByUnit[unit]
	if not castBar then
		return
	end

	if castBar.state == CASTBAR_STATE.CASTING or castBar.state == CASTBAR_STATE.CHANNELING then
		castBar.state = CASTBAR_STATE.FADING
		castBar.fadeStartTime = GetTime()
	end
end

local function FailCast(unit, wasInterrupted)
	local castBar = castBarsByUnit[unit]
	if not castBar then
		return
	end

	if castBar.state ~= CASTBAR_STATE.FINISHED then
		if wasInterrupted then
			castBar:SetStatusBarColor(1, 0, 0)
			castBar.text:SetText("Interrupted")
		else
			castBar:SetStatusBarColor(0.5, 0.5, 0.5)
			castBar.text:SetText("Failed")
		end
		castBar:SetValue(1)
		castBar:SetAlpha(1)
		castBar:Show()
		castBar.state = CASTBAR_STATE.FINISHED
		castBar.holdUntil = GetTime() + 0.5
	end
end

local function AdjustCastTiming(unit, isChannel)
	local castBar = castBarsByUnit[unit]
	if not castBar then
		return
	end

	local info = isChannel and { UnitChannelInfo(unit) } or { UnitCastingInfo(unit) }
	if not info[1] then
		return
	end

	castBar.startTime = (info[5] or 0) / 1000
	castBar.endTime = (info[6] or 0) / 1000

	if not isChannel then
		castBar.notInterruptible = info[9] or false
	else
		castBar.notInterruptible = info[8] or false
	end
end

local function HideCastBar(unit)
	local castBar = castBarsByUnit[unit]
	if not castBar then
		return
	end

	castBar.state = CASTBAR_STATE.HIDDEN
	castBar:SetAlpha(1)
	castBar:SetValue(0)
	castBar:Hide()
	castBar.text:SetText("")
	castBar.time:SetText("")
	castBar.icon:SetTexture(nil)
	castBar.notInterruptible = false
end

local function RefreshCastBar(unit)
	if UnitCastingInfo(unit) then
		BeginCast(unit, false)
	elseif UnitChannelInfo(unit) then
		BeginCast(unit, true)
	else
		HideCastBar(unit)
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
	frame:SetFrameStrata("LOW")
	frame:SetFrameLevel(10)
	frame:SetScale(1.15)

	frame.healthBar = CreateStatusBar(frame, { width = 108, height = 24 }, {
		point = "TOPLEFT",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = 27,
		y = -20,
	})

	frame.powerBar = CreateStatusBar(frame, { width = 108, height = 9 }, {
		point = "TOPLEFT",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = 27,
		y = -46,
	})

	frame.texture = AttachFrameTexture(frame, FRAME_TEXTURES.default)

	frame.portrait = CreatePortrait(frame, {
		point = "CENTER",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = 164,
		y = -38,
	})

	frame.portraitMask = AttachFrameTexture(frame, FRAME_TEXTURES.default, { subLevel = 5 })
	frame.portraitMask:SetBlendMode("BLEND")

	frame.eliteTexture = AttachFrameTexture(frame, FRAME_TEXTURES.default, { layer = "OVERLAY" })
	frame.eliteTexture:Hide()

	frame.levelText = CreateFontString(frame, {
		point = "CENTER",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = 184,
		y = -56,
		size = 8,
		flags = "OUTLINE",
		color = { r = 1, g = 0.82, b = 0 },
		drawLayer = 0,
	})

	frame.nameText = CreateFontString(frame, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = 6,
		size = 7,
		flags = "OUTLINE",
		drawLayer = 7,
	})
	frame.nameText:SetText("")

	frame.healthText = CreateFontString(frame, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = -6,
		size = 8,
		flags = "OUTLINE",
		color = { r = 1, g = 1, b = 1 },
		drawLayer = 7,
	})
	frame.healthText:SetText("")

	frame.powerText = CreateFontString(frame, {
		point = "CENTER",
		relativeTo = frame.powerBar,
		relativePoint = "CENTER",
		x = 0,
		y = 1,
		size = 7,
		flags = "OUTLINE",
		color = { r = 1, g = 1, b = 1 },
		drawLayer = 7,
	})
	frame.powerText:SetText("")

	-- Dead text overlay
	frame.deadText = CreateFontString(frame, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = 0,
		size = 12,
		flags = "OUTLINE",
		color = { r = 0.5, g = 0.5, b = 0.5 },
		drawLayer = 7,
	})
	frame.deadText:SetText("")
	frame.deadText:Hide()

	frame.castBar = CreateCastBar(frame, "target")

	frame.buffs = CreateAuraRow(frame, {
		count = 5,
		size = 15,
		spacing = 2,
		anchor = {
			point = "TOPLEFT",
			relativeTo = frame,
			relativePoint = "BOTTOMLEFT",
			x = 28,
			y = 40,
		},
	})

	frame.debuffRowAnchors = {
		withBuffs = {
			point = "TOPLEFT",
			relativeTo = frame.buffs[1],
			relativePoint = "BOTTOMLEFT",
			x = 0,
			y = -1,
		},
		withoutBuffs = {
			point = "TOPLEFT",
			relativeTo = frame,
			relativePoint = "BOTTOMLEFT",
			x = 28,
			y = 41,
		},
		current = "withBuffs",
	}

	frame.debuffs = CreateAuraRow(frame, {
		count = 5,
		size = 20,
		spacing = 2,
		anchor = frame.debuffRowAnchors.withBuffs,
	})

	-- Enable mouse clicks and set up secure click handling
	frame:EnableMouse(true)
	frame:RegisterForClicks("AnyUp")

	local targetDropdown = CreateUnitInteractionDropdown("target", "UFI_TargetFrameDropDown", {
		fallbackTitle = TARGET or "Target",
	})

	local playerDropdown = UFI_PlayerFrameDropDown

	SecureUnitButton_OnLoad(frame, "target", function(self, unit, button)
		if UnitIsUnit("target", "player") then
			ToggleDropDownMenu(1, nil, playerDropdown, self, 110, 45)
		else
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
	frame:SetFrameStrata("LOW")
	frame:SetFrameLevel(1)
	frame:SetScale(1.15)

	frame.healthBar = CreateStatusBar(frame, { width = 108, height = 24 }, {
		point = "TOPLEFT",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = 27,
		y = -20,
	})

	frame.powerBar = CreateStatusBar(frame, { width = 108, height = 9 }, {
		point = "TOPLEFT",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = 27,
		y = -46,
	})

	frame.texture = AttachFrameTexture(frame, FRAME_TEXTURES.default)

	frame.portrait = CreatePortrait(frame, {
		point = "CENTER",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = 164,
		y = -38,
	})

	frame.portraitMask = AttachFrameTexture(frame, FRAME_TEXTURES.default, { subLevel = 5 })
	frame.portraitMask:SetBlendMode("BLEND")

	frame.eliteTexture = AttachFrameTexture(frame, FRAME_TEXTURES.default, { layer = "OVERLAY" })
	frame.eliteTexture:Hide()

	frame.levelText = CreateFontString(frame, {
		point = "CENTER",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = 184,
		y = -56,
		size = 8,
		flags = "OUTLINE",
		color = { r = 1, g = 0.82, b = 0 },
		drawLayer = 0,
	})

	frame.nameText = CreateFontString(frame, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = 6,
		size = 7,
		flags = "OUTLINE",
		drawLayer = 7,
	})
	frame.nameText:SetText("")

	frame.healthText = CreateFontString(frame, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = -6,
		size = 8,
		flags = "OUTLINE",
		color = { r = 1, g = 1, b = 1 },
		drawLayer = 7,
	})
	frame.healthText:SetText("")

	frame.powerText = CreateFontString(frame, {
		point = "CENTER",
		relativeTo = frame.powerBar,
		relativePoint = "CENTER",
		x = 0,
		y = 1,
		size = 7,
		flags = "OUTLINE",
		color = { r = 1, g = 1, b = 1 },
		drawLayer = 7,
	})
	frame.powerText:SetText("")

	-- Dead text overlay
	frame.deadText = CreateFontString(frame, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = 0,
		size = 12,
		flags = "OUTLINE",
		color = { r = 0.5, g = 0.5, b = 0.5 },
		drawLayer = 7,
	})
	frame.deadText:SetText("")
	frame.deadText:Hide()

	frame.castBar = CreateCastBar(frame, "focus")

	frame.buffs = CreateAuraRow(frame, {
		count = 5,
		size = 15,
		spacing = 2,
		anchor = {
			point = "TOPLEFT",
			relativeTo = frame,
			relativePoint = "BOTTOMLEFT",
			x = 28,
			y = 40,
		},
	})

	frame.debuffRowAnchors = {
		withBuffs = {
			point = "TOPLEFT",
			relativeTo = frame.buffs[1],
			relativePoint = "BOTTOMLEFT",
			x = 0,
			y = -2,
		},
		withoutBuffs = {
			point = "TOPLEFT",
			relativeTo = frame,
			relativePoint = "BOTTOMLEFT",
			x = 28,
			y = 40,
		},
		current = "withBuffs",
	}

	frame.debuffs = CreateAuraRow(frame, {
		count = 5,
		size = 20,
		spacing = 2,
		anchor = frame.debuffRowAnchors.withBuffs,
	})

	-- Enable mouse clicks
	frame:EnableMouse(true)
	frame:RegisterForClicks("AnyUp")

	local focusDropdown = CreateUnitInteractionDropdown("focus", "UFI_FocusFrameDropDown", {
		fallbackTitle = FOCUS or "Focus",
		extraLevel1Buttons = function(level, unitId, addButton)
			local clearLabel = CLEAR_FOCUS or "Clear Focus"
			addButton(level, function(info)
				info.text = clearLabel
				info.notCheckable = true
				info.func = function()
					ClearFocus()
					CloseDropDownMenus()
				end
				info.disabled = not UnitExists(unitId)
			end)
		end,
	})

	SecureUnitButton_OnLoad(frame, "focus", function(self, unit, button)
		ToggleDropDownMenu(1, nil, focusDropdown, self, 110, 45)
	end)

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
	frame:SetFrameStrata("LOW")
	local targetFrameLevel = UFI_TargetFrame:GetFrameLevel() or 1
	frame:SetFrameLevel(targetFrameLevel + 5)
	frame:SetScale(0.6) -- Scale to 50% (half size)

	local visual = CreateFrame("Frame", nil, frame)
	visual:SetAllPoints(frame)
	visual:SetFrameStrata("LOW")
	visual:SetFrameLevel(math.max(targetFrameLevel - 1, 0))
	frame.visualLayer = visual

	frame.healthBar = CreateStatusBar(visual, { width = 108, height = 24 }, {
		point = "TOPLEFT",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = 97,
		y = -20,
	})

	frame.powerBar = CreateStatusBar(visual, { width = 108, height = 9 }, {
		point = "TOPLEFT",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = 97,
		y = -46,
	})

	frame.texture = AttachFrameTexture(visual, FRAME_TEXTURES.default, { mirror = true })

	frame.portrait = CreatePortrait(visual, {
		point = "CENTER",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = 68,
		y = -38,
	})

	frame.nameText = CreateFontString(visual, {
		point = "CENTER",
		relativeTo = frame.healthBar,
		relativePoint = "CENTER",
		x = 0,
		y = 0,
		size = 9,
		flags = "OUTLINE",
		drawLayer = 7,
	})
	frame.nameText:SetText("")

	frame.levelText = CreateFontString(visual, {
		point = "CENTER",
		relativeTo = frame,
		relativePoint = "TOPLEFT",
		x = 48,
		y = -56,
		size = 8,
		flags = "OUTLINE",
		color = { r = 1, g = 0.82, b = 0 },
		drawLayer = 0,
	})

	-- Enable mouse clicks
	frame:EnableMouse(true)
	frame:RegisterForClicks("AnyUp")

	-- Set unit for secure click handling
	frame:SetAttribute("unit", "targettarget")
	frame:SetAttribute("type1", "target") -- Left click = target the unit

	-- Use RegisterStateDriver for secure show/hide based on targettarget existence
	RegisterStateDriver(frame, "visibility", "[target=targettarget,exists] show; hide")

	return frame
end

-------------------------------------------------------------------------------
-- PLAYER FRAME UPDATE FUNCTIONS
-------------------------------------------------------------------------------

-- Helper function to format health/power text based on interface options
local function FormatStatusText(current, max)
	-- Check if "Display Percentages" is checked in Interface Options > Status Text
	-- The CVar is "statusTextPercentage" and is "1" when checked, "0" when unchecked
	local statusTextPercentage = GetCVar("statusTextPercentage")

	-- Check if percentages are enabled
	if statusTextPercentage == "1" then
		-- Show percentage
		local percent = 0
		if max > 0 then
			percent = math.floor((current / max) * 100)
		end
		return percent .. "%"
	else
		-- Show numeric values
		return AbbreviateNumber(current) .. " / " .. AbbreviateNumber(max)
	end
end

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
	UFI_PlayerFrame.healthText:SetText(FormatStatusText(health, maxHealth))
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
	UFI_PlayerFrame.powerText:SetText(FormatStatusText(power, maxPower))
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
		UFI_TargetFrame.healthText:SetText(FormatStatusText(health, maxHealth))
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
	UFI_TargetFrame.powerText:SetText(FormatStatusText(power, maxPower))
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
		UFI_FocusFrame.healthText:SetText(FormatStatusText(health, maxHealth))
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
	UFI_FocusFrame.powerText:SetText(FormatStatusText(power, maxPower))
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

local function HideAuraRows(frame)
	if not frame then
		return
	end

	if frame.buffs then
		for i = 1, #frame.buffs do
			frame.buffs[i]:Hide()
		end
	end

	if frame.debuffs then
		for i = 1, #frame.debuffs do
			frame.debuffs[i]:Hide()
		end
	end
end

local function SortByRemainingTime(a, b)
	return a.remainingTime < b.remainingTime
end

local function UpdateUnitAuras(unit, frame)
	if not frame then
		return
	end

	if not UnitExists(unit) then
		HideAuraRows(frame)
		if frame.debuffRowAnchors and frame.debuffRowAnchors.current ~= "withBuffs" then
			SetAuraRowAnchor(frame.debuffs, frame.debuffRowAnchors.withBuffs)
			frame.debuffRowAnchors.current = "withBuffs"
		end
		return
	end

	local now = GetTime()

	local allBuffs = {}
	for i = 1, 40 do
		local name, _, icon, count, _, duration, expirationTime = UnitBuff(unit, i)
		if not name then
			break
		end

		local remainingTime = 999999
		if duration and duration > 0 and expirationTime then
			remainingTime = expirationTime - now
		end

		allBuffs[#allBuffs + 1] = {
			icon = icon,
			count = count,
			duration = duration,
			expirationTime = expirationTime,
			remainingTime = remainingTime,
		}
	end

	table.sort(allBuffs, SortByRemainingTime)

	local buffsShown = 0
	if frame.buffs then
		for i = 1, #frame.buffs do
			local buffFrame = frame.buffs[i]
			local data = allBuffs[i]
			if data then
				buffFrame.icon:SetTexture(data.icon)
				if data.duration and data.duration > 0 and data.expirationTime then
					buffFrame.cooldown:SetCooldown(data.expirationTime - data.duration, data.duration)
				end
				if data.count and data.count > 1 then
					buffFrame.count:SetText(data.count)
					buffFrame.count:Show()
				else
					buffFrame.count:Hide()
				end
				buffFrame:Show()
				buffsShown = buffsShown + 1
			else
				buffFrame:Hide()
			end
		end
	end

	local playerDebuffs = {}
	for i = 1, 40 do
		local name, _, icon, count, debuffType, duration, expirationTime, caster = UnitDebuff(unit, i)
		if not name then
			break
		end

		if caster == "player" or caster == "pet" or caster == "vehicle" then
			local remainingTime = 999999
			if duration and duration > 0 and expirationTime then
				remainingTime = expirationTime - now
			end

			playerDebuffs[#playerDebuffs + 1] = {
				icon = icon,
				count = count,
				debuffType = debuffType,
				duration = duration,
				expirationTime = expirationTime,
				remainingTime = remainingTime,
			}
		end
	end

	table.sort(playerDebuffs, SortByRemainingTime)

	if frame.debuffRowAnchors then
		local desired = buffsShown > 0 and "withBuffs" or "withoutBuffs"
		if frame.debuffRowAnchors.current ~= desired then
			SetAuraRowAnchor(frame.debuffs, frame.debuffRowAnchors[desired])
			frame.debuffRowAnchors.current = desired
		end
	end

	if frame.debuffs then
		for i = 1, #frame.debuffs do
			local debuffFrame = frame.debuffs[i]
			local data = playerDebuffs[i]
			if data then
				debuffFrame.icon:SetTexture(data.icon)
				local color = DebuffTypeColor[data.debuffType or "none"] or DebuffTypeColor["none"]
				debuffFrame.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
				debuffFrame.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
				debuffFrame.border:SetVertexColor(color[1], color[2], color[3])

				if data.duration and data.duration > 0 and data.expirationTime then
					debuffFrame.cooldown:SetCooldown(data.expirationTime - data.duration, data.duration)
				end
				if data.count and data.count > 1 then
					debuffFrame.count:SetText(data.count)
					debuffFrame.count:Show()
				else
					debuffFrame.count:Hide()
				end
				debuffFrame:Show()
			else
				debuffFrame:Hide()
			end
		end
	end
end

local function UpdateFocusAuras()
	UpdateUnitAuras("focus", UFI_FocusFrame)
end

local function UpdatePlayerAuras()
	if not UFI_PlayerFrame or not UFI_PlayerFrame.selfBuffs then
		return
	end

	local now = GetTime()
	local selfBuffs = {}

	for i = 1, 40 do
		local name, _, icon, count, _, duration, expirationTime, caster, _, _, spellId = UnitBuff("player", i)
		if not name then
			break
		end

		if
			(caster == "player" or caster == "pet" or caster == "vehicle")
			and not (spellId and SELF_BUFF_EXCLUSIONS[spellId])
		then
			local remainingTime = 999999
			if duration and duration > 0 and expirationTime then
				remainingTime = expirationTime - now
			end

			selfBuffs[#selfBuffs + 1] = {
				icon = icon,
				count = count,
				duration = duration,
				expirationTime = expirationTime,
				remainingTime = remainingTime,
			}
		end
	end

	table.sort(selfBuffs, SortByRemainingTime)

	for i = 1, #UFI_PlayerFrame.selfBuffs do
		local iconFrame = UFI_PlayerFrame.selfBuffs[i]
		local data = selfBuffs[i]

		if data then
			iconFrame.icon:SetTexture(data.icon)
			if data.duration and data.duration > 0 and data.expirationTime then
				iconFrame.cooldown:SetCooldown(data.expirationTime - data.duration, data.duration)
				iconFrame.cooldown:Show()
			else
				iconFrame.cooldown:Hide()
			end

			if data.count and data.count > 1 then
				iconFrame.count:SetText(data.count)
				iconFrame.count:Show()
			else
				iconFrame.count:Hide()
			end

			iconFrame.border:SetVertexColor(1, 1, 1)
			iconFrame:Show()
		else
			iconFrame.cooldown:Hide()
			iconFrame.count:Hide()
			iconFrame:Hide()
		end
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
	UpdateUnitAuras("target", UFI_TargetFrame)
end

-------------------------------------------------------------------------------
-- EVENT HANDLING
-------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
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
		-- Initialize database
		InitializeDatabase()

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

		-- Apply saved positions FIRST
		ApplyPosition("UFI_PlayerFrame")
		ApplyPosition("UFI_TargetFrame")
		ApplyPosition("UFI_FocusFrame")

		-- Create overlays for movable frames AFTER positioning
		CreateOverlay(UFI_PlayerFrame, "UFI_PlayerFrame")
		CreateOverlay(UFI_TargetFrame, "UFI_TargetFrame")
		CreateOverlay(UFI_FocusFrame, "UFI_FocusFrame")

		-- Hook into SetCVar to detect changes from Interface Options
		-- The Interface Options UI uses the old SetCVar() function which doesn't
		-- trigger CVAR_UPDATE events. Only C_CVar.SetCVar() triggers that event.
		-- This hook allows us to detect changes immediately without polling.
		hooksecurefunc("SetCVar", function(name, value)
			if name == "statusTextPercentage" then
				-- Update all visible frames when percentage display setting changes
				UpdatePlayerHealth()
				UpdatePlayerPower()
				if UnitExists("target") then
					UpdateTargetHealth()
					UpdateTargetPower()
				end
				if UnitExists("focus") then
					UpdateFocusHealth()
					UpdateFocusPower()
				end
			end
		end)

		-- Restore unlocked state if it was unlocked
		if UnitFramesImprovedDB.isUnlocked and not InCombatLockdown() then
			UnlockFrames()
		end

		-- Display welcome message
		Print("|cff00ff00UnitFramesImproved v1.0.0 loaded!|r Type |cffffcc00/ufi help|r for commands.")

		-- Initial updates
		UpdatePlayerHealth()
		UpdatePlayerPower()
		UpdatePlayerPortrait()
		UpdatePlayerName()
		UpdatePlayerLevel()
		UpdatePlayerAuras()

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
		RefreshCastBar("target")
	elseif event == "PLAYER_FOCUS_CHANGED" then
		UpdateFocusFrame()
		RefreshCastBar("focus")
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
		or event == "UNIT_MANA"
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

		if UnitIsUnit(unit, "targettarget") then
			UpdateTargetOfTargetPower()
		end
	elseif
		event == "UNIT_MAXPOWER"
		or event == "UNIT_MAXMANA"
		or event == "UNIT_MAXRAGE"
		or event == "UNIT_MAXENERGY"
		or event == "UNIT_MAXFOCUS"
		or event == "UNIT_MAXRUNIC_POWER"
	then
		local unit = ...
		if unit == "player" then
			UpdatePlayerPower()
		elseif unit == "target" then
			UpdateTargetPower()
		elseif unit == "focus" then
			UpdateFocusPower()
		end

		if UnitIsUnit(unit, "targettarget") then
			UpdateTargetOfTargetPower()
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
		if unit == "player" then
			UpdatePlayerAuras()
		elseif unit == "target" then
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
		BeginCast(unit, false)
	elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
		local unit = ...
		BeginCast(unit, true)
	elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		local unit = ...
		StopCast(unit)
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		local unit = ...
		FailCast(unit, event == "UNIT_SPELLCAST_INTERRUPTED")
	elseif event == "UNIT_SPELLCAST_DELAYED" then
		local unit = ...
		AdjustCastTiming(unit, false)
	elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
		local unit = ...
		AdjustCastTiming(unit, true)
	elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
		local unit = ...
		local castBar = castBarsByUnit[unit]
		if castBar then
			castBar.notInterruptible = false
		end
	elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
		local unit = ...
		local castBar = castBarsByUnit[unit]
		if castBar then
			castBar.notInterruptible = true
		end
	elseif event == "PLAYER_LOGOUT" then
		-- Save all frame positions before logout
		for frameName, _ in pairs(defaultPositions) do
			local frame = _G[frameName]
			if frame then
				local point, _, relativePoint, x, y = frame:GetPoint()
				if point then
					SavePosition(frameName, point, relativePoint, x, y)
				end
			end
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Combat started
		OnCombatStart()
	elseif event == "PLAYER_REGEN_ENABLED" then
		-- Combat ended
		OnCombatEnd()
	end
end)

-- OnUpdate for cast bar
eventFrame:SetScript("OnUpdate", function()
	for _, castBar in pairs(castBarsByUnit) do
		if castBar.state ~= CASTBAR_STATE.HIDDEN then
			UpdateCastBar(castBar)
		end
	end
end)
