--[[
	UnitFramesImproved - Cast Bar System
	
	Manages cast bar state, rendering, and updates for all unit frames.
	Includes channeling, regular casts, interrupts, and failures.
]]

---@diagnostic disable: undefined-global

-------------------------------------------------------------------------------
-- MODULE SETUP
-------------------------------------------------------------------------------

local UFI = UnitFramesImproved

-- Module namespace
UFI.CastBar = UFI.CastBar or {}
local CastBar = UFI.CastBar

-- Dependencies (will be initialized)
local LayoutResolveRect
local UFI_LAYOUT
local STATUSBAR_TEXTURE
local FONT_DEFAULT

-------------------------------------------------------------------------------
-- CAST BAR STATE MACHINE
-------------------------------------------------------------------------------

local CASTBAR_STATE = {}
local castBarsByUnit = {}

-- Forward declaration
local OnUpdateCastBar

-------------------------------------------------------------------------------
-- CAST BAR CREATION
-------------------------------------------------------------------------------

local function CreateCastBar(parent, unit, mirrored)
	mirrored = not not mirrored
	local healthX, _, healthWidth = LayoutResolveRect(UFI_LAYOUT.Health, mirrored)
	local width = healthWidth
	local widthScale = width / UFI_LAYOUT.CastBar.DefaultWidth
	local height =
		math.max(UFI_LAYOUT.CastBar.DefaultHeight, math.floor(UFI_LAYOUT.CastBar.DefaultHeight * widthScale + 0.5))
	local offsetY = UFI_LAYOUT.CastBar.OffsetY
	local anchorPoint
	local anchorX

	if mirrored then
		anchorPoint = "TOPRIGHT"
		anchorX = healthX + width
	else
		anchorPoint = "TOPLEFT"
		anchorX = healthX
	end

	local castBar = CreateFrame("StatusBar", nil, parent)
	castBar:SetSize(width, height)
	castBar:SetPoint(anchorPoint, parent, "BOTTOMLEFT", anchorX, -offsetY)
	castBar:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
	castBar:SetStatusBarTexture(STATUSBAR_TEXTURE)
	local fill = castBar:GetStatusBarTexture()
	fill:SetHorizTile(false)
	fill:SetVertTile(false)
	local fillCoords = UFI_LAYOUT.CastBar.Fill
	local texSize = UFI_LAYOUT.CastBar.TextureSize
	local left = fillCoords.x / texSize.width
	local right = (fillCoords.x + fillCoords.width) / texSize.width
	local top = fillCoords.y / texSize.height
	local bottom = (fillCoords.y + fillCoords.height) / texSize.height
	fill:SetTexCoord(left, right, top, bottom)
	castBar:SetMinMaxValues(0, 1)
	castBar:SetValue(0)
	castBar:Hide()

	local bg = castBar:CreateTexture(nil, "BACKGROUND")
	bg:SetColorTexture(0, 0, 0, 0.65)
	bg:SetAllPoints(castBar)

	-- Restore decorative border with proportional scaling so it still hugs the bar
	local borderWidth = math.floor(width * (195 / 148) + 0.5)
	local borderHeight = math.floor(height * (50 / 12) + 0.5)
	local borderOffsetY = math.floor(height * (20 / 12) + 0.5)
	local border = castBar:CreateTexture(nil, "OVERLAY", nil, 1)
	border:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border-Small")
	border:SetSize(borderWidth, borderHeight)
	border:SetPoint("TOP", castBar, "TOP", 0, borderOffsetY)
	castBar.border = border

	local text = castBar:CreateFontString(nil, "OVERLAY")
	text:SetFont(FONT_DEFAULT, math.max(10, math.floor(height * 0.65)), "OUTLINE")
	text:SetTextColor(1, 1, 1)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("MIDDLE")
	text:SetWordWrap(false)
	text:ClearAllPoints()
	text:SetPoint("LEFT", castBar, "LEFT", 4, 2)
	text:SetPoint("TOP", castBar, "TOP", 0, 2)
	text:SetPoint("BOTTOM", castBar, "BOTTOM", 0, 2)
	castBar.text = text

	local time = castBar:CreateFontString(nil, "OVERLAY")
	time:SetFont(FONT_DEFAULT, math.max(10, math.floor(height * 0.65)), "OUTLINE")
	time:SetTextColor(1, 1, 1)
	time:SetJustifyH("RIGHT")
	time:SetJustifyV("MIDDLE")
	time:SetWordWrap(false)
	time:ClearAllPoints()
	time:SetPoint("RIGHT", castBar, "RIGHT", -4, 2)
	time:SetPoint("TOP", castBar, "TOP", 0, 2)
	time:SetPoint("BOTTOM", castBar, "BOTTOM", 0, 2)
	castBar.time = time

	text:SetPoint("RIGHT", time, "LEFT", -6, 0)

	local icon = castBar:CreateTexture(nil, "OVERLAY")
	local iconSize = 30
	icon:SetSize(iconSize, iconSize)
	if mirrored then
		icon:SetPoint("LEFT", castBar, "RIGHT", 4, 0)
	else
		icon:SetPoint("RIGHT", castBar, "LEFT", -4, 0)
	end
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	castBar.icon = icon

	local iconBorder = castBar:CreateTexture(nil, "OVERLAY", nil, 1)
	iconBorder:SetPoint("CENTER", icon, "CENTER", 0, 0)
	iconBorder:SetSize(34, 34)
	iconBorder:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
	iconBorder:SetTexCoord(39 / 128, (39 + 34) / 128, 0 / 64, 34 / 64)
	castBar.iconBorder = iconBorder
	iconBorder:Hide()

	castBar.unit = unit
	castBar.mirrored = mirrored
	castBar.state = CASTBAR_STATE.HIDDEN
	castBar.startTime = 0
	castBar.endTime = 0
	castBar.notInterruptible = false
	castBar.holdUntil = 0
	castBar.fadeStartTime = 0
	castBar.spellName = ""
	castBar.spellTexture = ""
	castBar.OnUpdate = OnUpdateCastBar

	castBarsByUnit[unit] = castBar
	return castBar
end

-------------------------------------------------------------------------------
-- CAST BAR UPDATE
-------------------------------------------------------------------------------

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
			castBar.border:SetVertexColor(0.7, 0, 0) -- Red border for uninterruptible
			if castBar.iconBorder then
				castBar.iconBorder:SetVertexColor(0.7, 0, 0) -- Red icon border
			end
		else
			castBar:SetStatusBarColor(1, 0.7, 0)
			castBar.border:SetVertexColor(0, 1, 0) -- Green border for interruptible
			if castBar.iconBorder then
				castBar.iconBorder:SetVertexColor(0, 1, 0) -- Green icon border
			end
		end
	end
end

-------------------------------------------------------------------------------
-- CAST BAR ON UPDATE SCRIPT
-------------------------------------------------------------------------------

OnUpdateCastBar = function(self, elapsed)
	UpdateCastBar(self)

	-- Auto-disable OnUpdate when cast bar becomes hidden
	if self.state == CASTBAR_STATE.HIDDEN then
		self:SetScript("OnUpdate", nil)
	end
end

-------------------------------------------------------------------------------
-- CAST BAR STATE MANAGEMENT
-------------------------------------------------------------------------------

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
	if castBar.iconBorder then
		castBar.iconBorder:Show()
	end
	-- Color is set by UpdateCastBar based on interruptibility
	castBar:Show()
	UpdateCastBar(castBar)
	castBar:SetScript("OnUpdate", castBar.OnUpdate)
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
			castBar.border:SetVertexColor(1, 0, 0) -- Red border for interrupted
			if castBar.iconBorder then
				castBar.iconBorder:SetVertexColor(1, 0, 0) -- Red icon border
			end
		else
			castBar:SetStatusBarColor(0.5, 0.5, 0.5)
			castBar.text:SetText("Failed")
			castBar.border:SetVertexColor(0.5, 0.5, 0.5) -- Gray border for failed
			if castBar.iconBorder then
				castBar.iconBorder:SetVertexColor(0.5, 0.5, 0.5) -- Gray icon border
			end
		end
		castBar:SetValue(1)
		castBar:SetAlpha(1)
		castBar:Show()
		castBar.state = CASTBAR_STATE.FINISHED
		castBar.holdUntil = GetTime() + 0.5
		castBar:SetScript("OnUpdate", castBar.OnUpdate)
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
	castBar.border:SetVertexColor(1, 1, 1) -- Reset border to white
	if castBar.iconBorder then
		castBar.iconBorder:Hide()
		castBar.iconBorder:SetVertexColor(1, 1, 1) -- Reset icon border to white
	end
	castBar.notInterruptible = false
	castBar:SetScript("OnUpdate", nil)
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
-- MODULE INITIALIZATION
-------------------------------------------------------------------------------

function CastBar.Initialize(deps)
	-- Import dependencies
	LayoutResolveRect = deps.LayoutResolveRect
	UFI_LAYOUT = deps.UFI_LAYOUT
	STATUSBAR_TEXTURE = deps.STATUSBAR_TEXTURE
	FONT_DEFAULT = deps.FONT_DEFAULT

	-- Initialize state machine
	CASTBAR_STATE = {
		HIDDEN = "hidden",
		CASTING = "casting",
		CHANNELING = "channeling",
		FINISHED = "finished",
		FADING = "fading",
	}

	-- Export state constants
	CastBar.STATE = CASTBAR_STATE
end

-------------------------------------------------------------------------------
-- SPELLCAST EVENT HANDLERS
-------------------------------------------------------------------------------

local function HandleSpellcastStart(_, unit)
	BeginCast(unit, false)
end

local function HandleSpellcastChannelStart(_, unit)
	BeginCast(unit, true)
end

local function HandleSpellcastStop(_, unit)
	StopCast(unit)
end

local function HandleSpellcastFailed(_, unit)
	FailCast(unit, false)
end

local function HandleSpellcastInterrupted(_, unit)
	FailCast(unit, true)
end

local function HandleSpellcastDelayed(_, unit)
	AdjustCastTiming(unit, false)
end

local function HandleSpellcastChannelUpdate(_, unit)
	AdjustCastTiming(unit, true)
end

local function HandleSpellcastInterruptible(_, unit)
	local castBar = castBarsByUnit[unit]
	if castBar then
		castBar.notInterruptible = false
	end
end

local function HandleSpellcastNotInterruptible(_, unit)
	local castBar = castBarsByUnit[unit]
	if castBar then
		castBar.notInterruptible = true
	end
end

-------------------------------------------------------------------------------
-- MODULE EXPORTS
-------------------------------------------------------------------------------

CastBar.CreateCastBar = CreateCastBar
CastBar.UpdateCastBar = UpdateCastBar
CastBar.BeginCast = BeginCast
CastBar.StopCast = StopCast
CastBar.FailCast = FailCast
CastBar.AdjustCastTiming = AdjustCastTiming
CastBar.HideCastBar = HideCastBar
CastBar.RefreshCastBar = RefreshCastBar
CastBar.GetCastBarsByUnit = function()
	return castBarsByUnit
end

-- Spellcast event handlers
CastBar.HandleSpellcastStart = HandleSpellcastStart
CastBar.HandleSpellcastChannelStart = HandleSpellcastChannelStart
CastBar.HandleSpellcastStop = HandleSpellcastStop
CastBar.HandleSpellcastFailed = HandleSpellcastFailed
CastBar.HandleSpellcastInterrupted = HandleSpellcastInterrupted
CastBar.HandleSpellcastDelayed = HandleSpellcastDelayed
CastBar.HandleSpellcastChannelUpdate = HandleSpellcastChannelUpdate
CastBar.HandleSpellcastInterruptible = HandleSpellcastInterruptible
CastBar.HandleSpellcastNotInterruptible = HandleSpellcastNotInterruptible

-- Export event handlers to global scope for event system
_G.UFI_HandleSpellcastStart = HandleSpellcastStart
_G.UFI_HandleSpellcastChannelStart = HandleSpellcastChannelStart
_G.UFI_HandleSpellcastStop = HandleSpellcastStop
_G.UFI_HandleSpellcastFailed = HandleSpellcastFailed
_G.UFI_HandleSpellcastInterrupted = HandleSpellcastInterrupted
_G.UFI_HandleSpellcastDelayed = HandleSpellcastDelayed
_G.UFI_HandleSpellcastChannelUpdate = HandleSpellcastChannelUpdate
_G.UFI_HandleSpellcastInterruptible = HandleSpellcastInterruptible
_G.UFI_HandleSpellcastNotInterruptible = HandleSpellcastNotInterruptible
