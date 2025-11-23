--[[
	UnitFramesImproved - Positioning System
	Provides: Frame movement, overlays, drag/drop, position save/load, slash commands
]]

---@diagnostic disable: undefined-global

local UFI = UnitFramesImproved

-- Import dependencies
local Utils = UFI.Utils
local table_wipe = UFI.table_wipe
local Layout = UFI.Layout
local DEFAULT_FRAME_SCALES = Layout.DEFAULT_FRAME_SCALES

---@diagnostic disable-next-line: undefined-global
local MAX_BOSS_FRAMES = MAX_BOSS_FRAMES or 4

-- These will be set by the main file
local ADDON_VERSION
local DB_SCHEMA_VERSION
local BOSS_FRAME_STRIDE

-------------------------------------------------------------------------------
-- STATE VARIABLES
-------------------------------------------------------------------------------

local frameOverlays = {}
local isUnlocked = false
local pendingPositions = {}
local pendingFocusScale = false
local unsavedPositions = {}
local UpdateOverlayForFrame -- forward declaration

-------------------------------------------------------------------------------
-- DEFAULT POSITIONS
-------------------------------------------------------------------------------

local defaultPositions = {
	UFI_PlayerFrame = {
		point = "TOPLEFT",
		relativePoint = "TOPLEFT",
		x = 5,
		y = -30,
	},
	UFI_TargetFrame = {
		point = "TOPLEFT",
		relativePoint = "TOPLEFT",
		x = 500,
		y = -30,
	},
	UFI_TargetOfTargetFrame = {
		point = "CENTER",
		relativePoint = "CENTER",
		x = 0,
		y = 0,
	},
	UFI_FocusFrame = {
		point = "TOPLEFT",
		relativePoint = "TOPLEFT",
		x = 500,
		y = -400,
	},
	UFI_BossFrameAnchor = {
		point = "TOPRIGHT",
		relativePoint = "TOPRIGHT",
		x = 0,
		y = -200,
	},
}

-------------------------------------------------------------------------------
-- DATABASE FUNCTIONS
-------------------------------------------------------------------------------

-- Initialize saved variables
local function InitializeDatabase()
	UnitFramesImprovedDB = UnitFramesImprovedDB or {}
	local db = UnitFramesImprovedDB

	db.version = ADDON_VERSION
	db.schemaVersion = tonumber(db.schemaVersion) or 0
	if db.schemaVersion < DB_SCHEMA_VERSION then
		-- Placeholder for future migrations; bump schema once work completes.
		db.schemaVersion = DB_SCHEMA_VERSION
	end

	if type(db.isUnlocked) ~= "boolean" then
		db.isUnlocked = false
	end

	db.positions = db.positions or {}
	db.scales = db.scales or {}

	for frameName, defaultScale in pairs(DEFAULT_FRAME_SCALES) do
		local current = db.scales[frameName]
		if type(current) ~= "number" or current <= 0 then
			db.scales[frameName] = defaultScale
		end
	end
end

-- Sanity-check saved position tables so bad data does not taint frame anchors.
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

	return true
end

-- Fetch a saved position or fall back to the hard-coded defaults.
local function GetSavedPosition(frameName)
	UnitFramesImprovedDB = UnitFramesImprovedDB or {}
	UnitFramesImprovedDB.positions = UnitFramesImprovedDB.positions or {}

	local stored = UnitFramesImprovedDB.positions[frameName]
	if stored and ValidatePosition(stored) then
		return stored
	end

	return defaultPositions[frameName]
end

-- Ensure a frame lands on either its saved position or our layout default.
local function InitializeFramePosition(frameName, frame, pos)
	frame = frame or _G[frameName]
	if not frame then
		return nil
	end

	pos = pos or GetSavedPosition(frameName)
	if not pos then
		return nil
	end

	local relativeFrame = UIParent
	if pos.relativeTo then
		relativeFrame = _G[pos.relativeTo] or UIParent
	end

	Utils.ApplySavedScaleToFrame(frame)

	frame:ClearAllPoints()
	frame:SetPoint(pos.point, relativeFrame, pos.relativePoint, pos.x, pos.y)

	return pos
end

-- Repositioning is forbidden while secure frames are in combat lockdown.
local function CanRepositionFrames()
	return not InCombatLockdown()
end

-- Persist the latest coordinates for a given frame.
local function SavePosition(frameName, point, relativePoint, x, y, relativeTo)
	if not UnitFramesImprovedDB.positions then
		UnitFramesImprovedDB.positions = {}
	end

	UnitFramesImprovedDB.positions[frameName] = {
		point = point,
		relativePoint = relativePoint,
		x = x,
		y = y,
		relativeTo = relativeTo,
	}
end

-- Attempt to move a frame immediately, or defer until after combat.
local function ApplyPosition(frameName)
	local frame = _G[frameName]
	if not frame then
		return
	end

	if CanRepositionFrames() then
		local pos = InitializeFramePosition(frameName, frame)
		if pos then
			pendingPositions[frameName] = nil
			local overlay = frameOverlays[frameName]
			if overlay then
				UpdateOverlayForFrame(frameName)
			end
		end
	else
		-- Save for later
		pendingPositions[frameName] = true
	end
end

-- Apply a supplied position blob, respecting combat lockdown rules.
local function ApplyFramePositionData(frameName, pos)
	local frame = _G[frameName]
	if not frame then
		return
	end

	if not CanRepositionFrames() then
		pendingPositions[frameName] = true
		return
	end

	local usedPos = InitializeFramePosition(frameName, frame, pos)
	if usedPos then
		pendingPositions[frameName] = nil
		UpdateOverlayForFrame(frameName)
	end
end

-- Flush any delayed position changes once combat restrictions clear.
local function ApplyPendingPositions()
	if not CanRepositionFrames() then
		return
	end

	for frameName, _ in pairs(pendingPositions) do
		local unsaved = unsavedPositions[frameName]
		if unsaved then
			ApplyFramePositionData(frameName, unsaved)
		else
			ApplyPosition(frameName)
		end
	end

	if next(pendingPositions) then
		UFI.Print("Frame positions applied!")
	end
end

-- Restore a frame (and associated scales) back to shipped defaults.
local function ResetFramePosition(frameName)
	local pos = defaultPositions[frameName]
	if not pos then
		UFI.Print("Unknown frame: " .. frameName)
		return
	end

	if UnitFramesImprovedDB and UnitFramesImprovedDB.positions then
		UnitFramesImprovedDB.positions[frameName] = nil
	end
	ApplyPosition(frameName)

	local defaultScale = DEFAULT_FRAME_SCALES[frameName]
	if defaultScale then
		Utils.SetFrameScale(frameName, defaultScale)
	end

	if frameName == "UFI_BossFrameAnchor" then
		for index = 1, MAX_BOSS_FRAMES do
			local childName = "UFI_BossFrame" .. index
			local childScale = DEFAULT_FRAME_SCALES[childName]
			if childScale then
				Utils.SetFrameScale(childName, childScale)
			end
		end
	end

	UFI.Print("Reset " .. frameName .. " to default position")
end

-------------------------------------------------------------------------------
-- OVERLAY RENDERING
-------------------------------------------------------------------------------

-- Paint the move overlay border and segments with the provided color.
local function ApplyOverlayColorTextures(overlay, r, g, b, a)
	if overlay.border then
		overlay.border:SetColorTexture(r, g, b, a)
	end

	if overlay.borderSegments then
		for _, segment in ipairs(overlay.borderSegments) do
			segment:SetColorTexture(r, g, b, a)
		end
	end

	if overlay.bossSegments then
		local segmentAlpha = math.min(1, (a or 0.5) * 0.6)
		for _, segment in ipairs(overlay.bossSegments) do
			segment:SetColorTexture(r, g, b, segmentAlpha)
		end
	end
end

-- Cache overlay color values so drags can temporarily tint them.
local function SetOverlayColor(overlay, r, g, b, a)
	if not overlay then
		return
	end

	overlay.overlayColor = overlay.overlayColor or {}
	overlay.overlayColor.r = r
	overlay.overlayColor.g = g
	overlay.overlayColor.b = b
	overlay.overlayColor.a = a

	ApplyOverlayColorTextures(overlay, r, g, b, a)
end

-- Translate between frame anchors and overlay rectangles to keep drag handles aligned.
local function ComputeAnchorOffsets(point, frameWidth, frameHeight, overlayWidth, overlayHeight, leftInset, topInset)
	point = point or "TOPLEFT"

	local horizontal = "CENTER"
	if string.find(point, "LEFT") then
		horizontal = "LEFT"
	elseif string.find(point, "RIGHT") then
		horizontal = "RIGHT"
	end

	local vertical = "CENTER"
	if string.find(point, "TOP") then
		vertical = "TOP"
	elseif string.find(point, "BOTTOM") then
		vertical = "BOTTOM"
	end

	local frameTopLeftXOffset
	if horizontal == "LEFT" then
		frameTopLeftXOffset = 0
	elseif horizontal == "RIGHT" then
		frameTopLeftXOffset = -frameWidth
	else
		frameTopLeftXOffset = -frameWidth * 0.5
	end

	local frameTopLeftYOffset
	if vertical == "TOP" then
		frameTopLeftYOffset = 0
	elseif vertical == "BOTTOM" then
		frameTopLeftYOffset = frameHeight
	else
		frameTopLeftYOffset = frameHeight * 0.5
	end

	local overlayAnchorToTopLeftX
	if horizontal == "LEFT" then
		overlayAnchorToTopLeftX = 0
	elseif horizontal == "RIGHT" then
		overlayAnchorToTopLeftX = -overlayWidth
	else
		overlayAnchorToTopLeftX = -overlayWidth * 0.5
	end

	local overlayAnchorToTopLeftY
	if vertical == "TOP" then
		overlayAnchorToTopLeftY = 0
	elseif vertical == "BOTTOM" then
		overlayAnchorToTopLeftY = overlayHeight
	else
		overlayAnchorToTopLeftY = overlayHeight * 0.5
	end

	local anchorXOffset = frameTopLeftXOffset + leftInset - overlayAnchorToTopLeftX
	local anchorYOffset = frameTopLeftYOffset - topInset - overlayAnchorToTopLeftY

	return anchorXOffset, anchorYOffset
end

-- Keep overlay frames sized to the underlying secure frame's hit rect.
local function UpdateStandardOverlayGeometry(frame, overlay)
	if not frame or not overlay then
		return
	end

	local rect = frame.ufHitRect
	local left = rect and rect.left or 0
	local right = rect and rect.right or 0
	local top = rect and rect.top or 0
	local bottom = rect and rect.bottom or 0
	local frameWidth = frame:GetWidth()
	local frameHeight = frame:GetHeight()

	local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
	if not point then
		return
	end

	relativeTo = relativeTo or UIParent
	relativePoint = relativePoint or point

	local overlayWidth = math.max(1, frameWidth - left - right)
	local overlayHeight = math.max(1, frameHeight - top - bottom)
	local anchorXOffset, anchorYOffset =
		ComputeAnchorOffsets(point, frameWidth, frameHeight, overlayWidth, overlayHeight, left, top)

	overlay:ClearAllPoints()
	overlay:SetPoint(point, relativeTo, relativePoint, (x or 0) + anchorXOffset, (y or 0) + anchorYOffset)
	overlay:SetSize(overlayWidth, overlayHeight)
	overlay:SetScale(frame:GetScale())
	overlay.anchorAdjustX = anchorXOffset
	overlay.anchorAdjustY = anchorYOffset
	overlay.clickInsets = rect

	if overlay.overlayColor then
		ApplyOverlayColorTextures(
			overlay,
			overlay.overlayColor.r,
			overlay.overlayColor.g,
			overlay.overlayColor.b,
			overlay.overlayColor.a
		)
	else
		ApplyOverlayColorTextures(overlay, 0, 1, 0, 0.5)
	end
end

local function CalculateBossFallbackOverlayData(anchor)
	if not anchor or not anchor.frames then
		return nil
	end

	local baseFrame = anchor.frames[1]
	if not baseFrame then
		return nil
	end

	local activeSlots = 0
	for index, frame in ipairs(anchor.frames) do
		if frame:IsShown() or UnitExists(frame.unit or "") then
			activeSlots = math.max(activeSlots, index)
		end
	end

	if activeSlots == 0 then
		activeSlots = 1
	end

	local anchorWidth = anchor:GetWidth()
	local anchorHeight = anchor:GetHeight()
	local anchorScale = anchor:GetEffectiveScale()
	if not anchorScale or anchorScale == 0 then
		anchorScale = 1
	end

	local rect = baseFrame.ufHitRect
	local leftInset = rect and rect.left or 0
	local rightInset = rect and rect.right or 0
	local topInset = rect and rect.top or 0
	local bottomInset = rect and rect.bottom or 0

	local frameWidth = baseFrame:GetWidth() or 0
	local frameHeight = baseFrame:GetHeight() or 0
	local frameScale = baseFrame:GetEffectiveScale() or anchorScale
	local scaleRatio = frameScale / anchorScale

	local slotWidth = math.max(0, (frameWidth - leftInset - rightInset) * scaleRatio)
	local slotHeight = math.max(0, (frameHeight - topInset - bottomInset) * scaleRatio)
	local slotLeft = leftInset * scaleRatio
	local slotTop = topInset * scaleRatio
	local slotStride = BOSS_FRAME_STRIDE * scaleRatio

	local minLeft = slotLeft
	local minTop = slotTop
	local maxRight = slotLeft + slotWidth
	local maxBottom = slotTop + slotHeight + (activeSlots - 1) * slotStride

	local segments = {}
	for index = 1, activeSlots do
		segments[#segments + 1] = {
			slotIndex = index,
			left = slotLeft,
			top = slotTop + (index - 1) * slotStride,
			width = slotWidth,
			height = slotHeight,
		}
	end

	return {
		minLeft = minLeft,
		minTop = minTop,
		maxRight = maxRight,
		maxBottom = maxBottom,
		segments = segments,
	}
end

local function CalculateBossOverlayData(anchor)
	if not anchor or not anchor.frames then
		return nil
	end

	local anchorLeft = anchor:GetLeft()
	local anchorRight = anchor:GetRight()
	local anchorTop = anchor:GetTop()
	local anchorBottom = anchor:GetBottom()
	local anchorScale = anchor:GetEffectiveScale()
	if
		not anchorLeft
		or not anchorRight
		or not anchorTop
		or not anchorBottom
		or not anchorScale
		or anchorScale == 0
	then
		return CalculateBossFallbackOverlayData(anchor)
	end

	local anchorWidth = anchor:GetWidth()
	local anchorHeight = anchor:GetHeight()
	local minLeft = math.huge
	local minTop = math.huge
	local maxRight = 0
	local maxBottom = 0
	local segments = {}
	local hasLiveData = false

	for index, frame in ipairs(anchor.frames) do
		if frame:IsShown() then
			local left = frame:GetLeft()
			local right = frame:GetRight()
			local top = frame:GetTop()
			local bottom = frame:GetBottom()
			if left and right and top and bottom then
				hasLiveData = true
				local frameEffectiveScale = frame:GetEffectiveScale() or anchorScale
				if frameEffectiveScale == 0 then
					frameEffectiveScale = anchorScale
				end
				local rect = frame.ufHitRect
				if rect then
					local leftInset = rect.left or 0
					local rightInset = rect.right or 0
					local topInset = rect.top or 0
					local bottomInset = rect.bottom or 0
					left = left + leftInset * frameEffectiveScale
					right = right - rightInset * frameEffectiveScale
					top = top - topInset * frameEffectiveScale
					bottom = bottom + bottomInset * frameEffectiveScale
				end

				local localLeft = (left - anchorLeft) / anchorScale
				local localTop = (anchorTop - top) / anchorScale
				local localWidth = math.max(0, (right - left) / anchorScale)
				local localHeight = math.max(0, (top - bottom) / anchorScale)

				minLeft = math.min(minLeft, localLeft)
				minTop = math.min(minTop, localTop)
				maxRight = math.max(maxRight, localLeft + localWidth)
				maxBottom = math.max(maxBottom, localTop + localHeight)

				segments[#segments + 1] = {
					slotIndex = index,
					left = localLeft,
					top = localTop,
					width = localWidth,
					height = localHeight,
				}
			end
		end
	end

	if not hasLiveData or maxRight <= minLeft or maxBottom <= minTop then
		return CalculateBossFallbackOverlayData(anchor)
	end

	return {
		minLeft = minLeft,
		minTop = minTop,
		maxRight = maxRight,
		maxBottom = maxBottom,
		segments = segments,
	}
end

local function UpdateBossOverlayGeometry(anchor, overlay)
	if not anchor or not overlay then
		return
	end

	local data = CalculateBossOverlayData(anchor)
	local point, relativeTo, relativePoint, x, y = anchor:GetPoint(1)
	if not point then
		point = "TOPLEFT"
		relativeTo = UIParent
		relativePoint = "TOPLEFT"
		x, y = 0, 0
	else
		relativeTo = relativeTo or UIParent
		relativePoint = relativePoint or point
	end

	overlay:ClearAllPoints()

	if not data then
		overlay:SetPoint(point, relativeTo, relativePoint, x or 0, y or 0)
		overlay:SetSize(anchor:GetWidth(), anchor:GetHeight())
		overlay:SetScale(anchor:GetScale())
		overlay.anchorAdjustX = 0
		overlay.anchorAdjustY = 0
		overlay.clickInsets = nil

		if overlay.bossSegments then
			for _, segment in ipairs(overlay.bossSegments) do
				segment:Hide()
			end
		end

		return
	end

	local anchorWidth = anchor:GetWidth()
	local anchorHeight = anchor:GetHeight()
	local overlayWidth = math.max(1, data.maxRight - data.minLeft)
	local overlayHeight = math.max(1, data.maxBottom - data.minTop)
	local anchorXOffset, anchorYOffset =
		ComputeAnchorOffsets(point, anchorWidth, anchorHeight, overlayWidth, overlayHeight, data.minLeft, data.minTop)

	overlay:SetPoint(point, relativeTo, relativePoint, (x or 0) + anchorXOffset, (y or 0) + anchorYOffset)
	overlay:SetSize(overlayWidth, overlayHeight)
	overlay:SetScale(anchor:GetScale())
	overlay.anchorAdjustX = anchorXOffset
	overlay.anchorAdjustY = anchorYOffset
	overlay.clickInsets = {
		left = data.minLeft,
		top = data.minTop,
		right = math.max(anchorWidth - data.maxRight, 0),
		bottom = math.max(anchorHeight - data.maxBottom, 0),
	}

	overlay.bossSegments = overlay.bossSegments or {}
	for index, segInfo in ipairs(data.segments) do
		local segment = overlay.bossSegments[index]
		if not segment then
			segment = overlay:CreateTexture(nil, "OVERLAY", nil, 2)
			overlay.bossSegments[index] = segment
		end

		segment:Show()
		segment:ClearAllPoints()
		segment:SetPoint("TOPLEFT", overlay, "TOPLEFT", segInfo.left - data.minLeft, -(segInfo.top - data.minTop))
		segment:SetSize(segInfo.width, segInfo.height)
	end

	if #overlay.bossSegments > #data.segments then
		for index = #data.segments + 1, #overlay.bossSegments do
			overlay.bossSegments[index]:Hide()
		end
	end

	local color = overlay.overlayColor
	if color then
		ApplyOverlayColorTextures(overlay, color.r, color.g, color.b, color.a)
	else
		ApplyOverlayColorTextures(overlay, 0, 1, 0, 0.5)
	end
end

-- Recalculate overlay placement unless a drag operation is in progress.
UpdateOverlayForFrame = function(frameName)
	local overlay = frameOverlays[frameName]
	if not overlay or overlay.isDragging then
		return
	end

	local frame = _G[frameName]
	if not frame then
		return
	end

	if frameName == "UFI_BossFrameAnchor" then
		UpdateBossOverlayGeometry(frame, overlay)
	else
		UpdateStandardOverlayGeometry(frame, overlay)
	end
end

-- Translate overlay drag coordinates back into frame offsets.
local function OverlayOffsetsToFrameOffsets(overlay, point, x, y)
	if not overlay then
		return x or 0, y or 0
	end

	local frame = overlay.secureFrame
	if not frame then
		return x or 0, y or 0
	end

	point = point or "TOPLEFT"

	local frameWidth = frame:GetWidth()
	local frameHeight = frame:GetHeight()
	if not frameWidth or not frameHeight or frameWidth == 0 or frameHeight == 0 then
		return x or 0, y or 0
	end

	local rect = overlay.clickInsets
	local leftInset = rect and rect.left or 0
	local topInset = rect and rect.top or 0

	local overlayWidth = overlay:GetWidth()
	local overlayHeight = overlay:GetHeight()
	local anchorXOffset, anchorYOffset =
		ComputeAnchorOffsets(point, frameWidth, frameHeight, overlayWidth, overlayHeight, leftInset, topInset)

	return (x or 0) - anchorXOffset, (y or 0) - anchorYOffset
end

-------------------------------------------------------------------------------
-- OVERLAY CREATION & DRAG HANDLERS
-------------------------------------------------------------------------------

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

	overlay.border = overlay:CreateTexture(nil, "OVERLAY")
	overlay.border:SetAllPoints()
	SetOverlayColor(overlay, 0, 1, 0, 0.5)

	overlay.label = overlay:CreateFontString(nil, "OVERLAY")
	overlay.label:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
	overlay.label:SetPoint("CENTER")
	local displayName = frameName:gsub("UFI_", "")
	if frameName == "UFI_BossFrameAnchor" then
		displayName = "BossFrames"
	end
	overlay.label:SetText(displayName)

	overlay.secureFrame = frame
	overlay.isDragging = false
	overlay.dragStartLeft = 0
	overlay.dragStartTop = 0

	frameOverlays[frameName] = overlay

	if frame and not frame.UFIOverlayHooks then
		frame.UFIOverlayHooks = true
		local nameRef = frameName
		hooksecurefunc(frame, "SetPoint", function()
			UpdateOverlayForFrame(nameRef)
		end)
		hooksecurefunc(frame, "SetSize", function()
			UpdateOverlayForFrame(nameRef)
		end)
		hooksecurefunc(frame, "SetWidth", function()
			UpdateOverlayForFrame(nameRef)
		end)
		hooksecurefunc(frame, "SetHeight", function()
			UpdateOverlayForFrame(nameRef)
		end)
		hooksecurefunc(frame, "SetScale", function()
			UpdateOverlayForFrame(nameRef)
		end)
	end
	UpdateOverlayForFrame(frameName)

	local function FinishOverlayDrag(self, attemptApply)
		self:SetFrameLevel(100)

		local point, relativeToFrame, relativePoint, x, y = self:GetPoint()
		point = point or "TOPLEFT"
		relativePoint = relativePoint or point

		local frameX, frameY = OverlayOffsetsToFrameOffsets(self, point, x, y)
		local relativeToName
		if relativeToFrame then
			relativeToName = relativeToFrame:GetName()
			if not relativeToName and relativeToFrame == UIParent then
				relativeToName = "UIParent"
			end
		else
			relativeToName = "UIParent"
		end

		unsavedPositions[frameName] = {
			point = point,
			relativePoint = relativePoint,
			x = frameX,
			y = frameY,
			relativeTo = relativeToName,
		}

		if not attemptApply then
			SetOverlayColor(self, 0, 1, 0, 0.5)
			UpdateOverlayForFrame(frameName)
			return
		end

		if CanRepositionFrames() then
			local frame = self.secureFrame
			if frame then
				frame:ClearAllPoints()
				local relativeFrame = relativeToFrame
				if not relativeFrame then
					if relativeToName and relativeToName ~= "UIParent" then
						relativeFrame = _G[relativeToName]
					else
						relativeFrame = UIParent
					end
				end
				relativeFrame = relativeFrame or UIParent
				frame:SetPoint(point, relativeFrame, relativePoint, frameX, frameY)
			end
			pendingPositions[frameName] = nil
			SetOverlayColor(self, 0, 1, 0, 0.5)
			UpdateOverlayForFrame(frameName)
		else
			pendingPositions[frameName] = true
			SetOverlayColor(self, 1, 0.5, 0, 0.5)
		end
	end

	local function CompleteOverlayDrag(self)
		self:StopMovingOrSizing()
		local endLeft = self:GetLeft() or 0
		local endTop = self:GetTop() or 0
		local moved = math.abs(endLeft - (self.dragStartLeft or endLeft)) >= 0.5
			or math.abs(endTop - (self.dragStartTop or endTop)) >= 0.5

		self.isDragging = false

		if not moved then
			self:SetFrameLevel(100)
			SetOverlayColor(self, 0, 1, 0, 0.5)
			UpdateOverlayForFrame(frameName)
			return
		end

		FinishOverlayDrag(self, true)
	end

	overlay:SetScript("OnMouseDown", function(self, button)
		if button == "LeftButton" and isUnlocked then
			self.isDragging = true
			self.dragStartLeft = self:GetLeft() or 0
			self.dragStartTop = self:GetTop() or 0
			self:SetFrameLevel(110)
			SetOverlayColor(self, 1, 1, 0, 0.7)
			self:StartMoving()
		end
	end)

	overlay:SetScript("OnMouseUp", function(self, button)
		if button == "LeftButton" and self.isDragging then
			CompleteOverlayDrag(self)
		end
	end)

	overlay:SetScript("OnDragStop", function(self)
		if self.isDragging then
			CompleteOverlayDrag(self)
		end
	end)

	overlay:SetScript("OnEnter", function(self)
		if isUnlocked and not self.isDragging then
			SetOverlayColor(self, 0.5, 1, 0.5, 0.7)
		end
	end)

	overlay:SetScript("OnLeave", function(self)
		if isUnlocked and not self.isDragging then
			SetOverlayColor(self, 0, 1, 0, 0.5)
		end
	end)

	return overlay
end

-------------------------------------------------------------------------------
-- FRAME LOCK/UNLOCK
-------------------------------------------------------------------------------

-- Unlock frames for movement
local function UnlockFrames()
	if InCombatLockdown() then
		UFI.Print("|cffff0000Cannot unlock frames during combat!|r")
		return
	end

	isUnlocked = true
	UnitFramesImprovedDB.isUnlocked = true

	for frameName, overlay in pairs(frameOverlays) do
		UpdateOverlayForFrame(frameName)
		overlay:Show()
		overlay:EnableMouse(true)
		SetOverlayColor(overlay, 0, 1, 0, 0.5) -- Green for unlocked
	end

	UFI.Print("Frames unlocked! Drag to reposition. Type /ufi lock to save.")
end

-- Lock frames and save positions
local function LockFrames()
	for frameName, pos in pairs(unsavedPositions) do
		SavePosition(frameName, pos.point, pos.relativePoint, pos.x, pos.y, pos.relativeTo)
	end
	if next(unsavedPositions) then
		UFI.Print("Stored frame positions. Unlock again to make further adjustments.")
	end
	table_wipe(unsavedPositions)

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
		UFI.Print("Frames locked and positions saved!")
	else
		UFI.Print("Frames locked! Positions will apply after combat.")
	end
end

-- Save all frame positions on logout
local function SaveAllPositions()
	-- Save any unsaved positions from unlocked frames
	for frameName, pos in pairs(unsavedPositions) do
		SavePosition(frameName, pos.point, pos.relativePoint, pos.x, pos.y, pos.relativeTo)
	end

	-- Save all default frame positions
	for frameName in pairs(defaultPositions) do
		local frame = _G[frameName]
		if frame then
			local point, relativeToFrame, relativePoint, x, y = frame:GetPoint()
			if point then
				local relativeToName
				if relativeToFrame then
					relativeToName = relativeToFrame:GetName()
					if not relativeToName and relativeToFrame == UIParent then
						relativeToName = "UIParent"
					end
				end
				SavePosition(frameName, point, relativePoint, x, y, relativeToName)
			end
		end
	end
end

-------------------------------------------------------------------------------
-- FOCUS FRAME SCALE
-------------------------------------------------------------------------------

-- Apply focus frame scale based on interface option setting
local function ApplyFocusFrameScale()
	if not UFI_FocusFrame then
		return
	end

	-- Defer scale changes during combat
	if InCombatLockdown() then
		pendingFocusScale = true
		return
	end

	local fullSize = GetCVarBool("fullSizeFocusFrame")
	local desiredScale = fullSize and 0.55 or 0.45

	-- Only apply if user hasn't manually scaled the frame
	local currentScale = Utils.GetFrameScale("UFI_FocusFrame")
	local defaultLarge = 0.55
	local defaultSmall = 0.45

	-- Check if current scale matches either default (meaning user hasn't customized it)
	if currentScale == defaultLarge or currentScale == defaultSmall then
		Utils.SetFrameScale("UFI_FocusFrame", desiredScale)
	end

	pendingFocusScale = false
end

-------------------------------------------------------------------------------
-- COMBAT HANDLERS
-------------------------------------------------------------------------------

-- Handle combat start
local function OnCombatStart()
	if isUnlocked then
		-- Disable dragging during combat
		for _, overlay in pairs(frameOverlays) do
			overlay:EnableMouse(false)
			SetOverlayColor(overlay, 1, 0, 0, 0.5) -- Red for locked
			local labelText = overlay.label:GetText() or ""
			if not labelText:find(" %(COMBAT%)$") then
				overlay.label:SetText(labelText .. " (COMBAT)")
			end
		end
		UFI.Print("|cffff8800Frame movement disabled during combat!|r")
	end
end

-- Handle combat end
local function OnCombatEnd()
	-- Apply pending positions
	ApplyPendingPositions()

	-- Apply pending focus scale if needed
	if pendingFocusScale then
		ApplyFocusFrameScale()
	end

	-- Re-enable dragging if unlocked
	if isUnlocked then
		for _, overlay in pairs(frameOverlays) do
			overlay:EnableMouse(true)
			SetOverlayColor(overlay, 0, 1, 0, 0.5) -- Back to green
			overlay.label:SetText((overlay.label:GetText() or ""):gsub(" %(COMBAT%)$", ""))
		end
		UFI.Print("Frame movement re-enabled!")
	end
end

-------------------------------------------------------------------------------
-- SLASH COMMANDS
-------------------------------------------------------------------------------

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
			local normalized = arg:lower()
			local frameAliases = {
				player = "UFI_PlayerFrame",
				target = "UFI_TargetFrame",
				focus = "UFI_FocusFrame",
				tot = "UFI_TargetOfTargetFrame",
				targetoftarget = "UFI_TargetOfTargetFrame",
				boss = "UFI_BossFrameAnchor",
				bosses = "UFI_BossFrameAnchor",
				bossframe = "UFI_BossFrameAnchor",
				bossframes = "UFI_BossFrameAnchor",
				bossanchor = "UFI_BossFrameAnchor",
			}

			local frameName = frameAliases[normalized]
			if not frameName then
				frameName = "UFI_" .. normalized:sub(1, 1):upper() .. normalized:sub(2) .. "Frame"
			end

			ResetFramePosition(frameName)
		else
			-- Reset all frames
			for frameName, _ in pairs(defaultPositions) do
				ResetFramePosition(frameName)
			end
		end
	elseif cmd == "help" or cmd == "" then
		UFI.Print("|cff00ff00UnitFramesImproved v" .. ADDON_VERSION .. "|r")
		UFI.Print("Available commands:")
		UFI.Print("  |cffffcc00/ufi unlock|r - Unlock frames for repositioning")
		UFI.Print("  |cffffcc00/ufi lock|r - Lock frames and save positions")
		UFI.Print("  |cffffcc00/ufi reset [frame]|r - Reset frame(s) to default position")
		UFI.Print(
			"    Examples: |cff888888/ufi reset player|r, |cff888888/ufi reset boss|r, |cff888888/ufi reset|r (resets all)"
		)
		UFI.Print("  |cffffcc00/ufi help|r - Show this help message")
	else
		UFI.Print("Unknown command. Type |cffffcc00/ufi help|r for available commands.")
	end
end

-------------------------------------------------------------------------------
-- INITIALIZATION
-------------------------------------------------------------------------------

-- Set dependencies from main file
local function Initialize(config)
	ADDON_VERSION = config.ADDON_VERSION
	DB_SCHEMA_VERSION = config.DB_SCHEMA_VERSION
	BOSS_FRAME_STRIDE = config.BOSS_FRAME_STRIDE
end

-------------------------------------------------------------------------------
-- EXPORT TO NAMESPACE
-------------------------------------------------------------------------------

UFI.Positioning = {
	-- Initialization
	Initialize = Initialize,
	InitializeDatabase = InitializeDatabase,
	InitializeFramePosition = InitializeFramePosition,

	-- Position management
	ApplyPosition = ApplyPosition,
	ResetFramePosition = ResetFramePosition,
	SaveAllPositions = SaveAllPositions,

	-- Overlay management
	CreateOverlay = CreateOverlay,
	UpdateOverlayForFrame = UpdateOverlayForFrame,

	-- Focus scale
	ApplyFocusFrameScale = ApplyFocusFrameScale,

	-- Combat handlers
	OnCombatStart = OnCombatStart,
	OnCombatEnd = OnCombatEnd,

	-- Lock/Unlock
	UnlockFrames = UnlockFrames,
	LockFrames = LockFrames,
}
