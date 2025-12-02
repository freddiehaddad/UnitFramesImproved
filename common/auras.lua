--[[
	Auras Module

	Manages buff and debuff display for target and focus frames.
	Player frame has separate self-buff logic in the main file.
]]

---@diagnostic disable: undefined-global

local UFI = UnitFramesImproved
local Auras = {}
UFI.Auras = Auras

-------------------------------------------------------------------------------
-- DEPENDENCIES (injected via Initialize)
-------------------------------------------------------------------------------

local Utils

-- Debuff type colors
local DebuffTypeColor = {
	["Magic"] = { 0.2, 0.6, 1.0 },
	["Curse"] = { 0.6, 0.0, 1.0 },
	["Disease"] = { 0.6, 0.4, 0 },
	["Poison"] = { 0.0, 0.6, 0 },
	["none"] = { 0.8, 0, 0 },
}

-------------------------------------------------------------------------------
-- HELPER FUNCTIONS
-------------------------------------------------------------------------------

local function HideAuraRows(frame)
	if not frame then
		return
	end

	if frame.buffs then
		for i = 1, #frame.buffs do
			local iconFrame = frame.buffs[i]
			if iconFrame.cooldown then
				iconFrame.cooldown:Hide()
			end
			if iconFrame.count then
				iconFrame.count:Hide()
			end
			iconFrame:Hide()
		end
	end

	if frame.debuffs then
		for i = 1, #frame.debuffs do
			local iconFrame = frame.debuffs[i]
			if iconFrame.cooldown then
				iconFrame.cooldown:Hide()
			end
			if iconFrame.count then
				iconFrame.count:Hide()
			end
			iconFrame:Hide()
		end
	end
end

-------------------------------------------------------------------------------
-- AURA UPDATE FUNCTION
-------------------------------------------------------------------------------

local function UpdateUnitAuras(unit, frame, filterDebuffs)
	if not frame then
		return
	end

	if not UnitExists(unit) then
		HideAuraRows(frame)
		Utils.PositionAuraRow(frame.debuffs, frame, frame.mirrored, "below", 1)
		return
	end

	local buffsShown = 0
	local buffFrames = frame.buffs
	if buffFrames and #buffFrames > 0 then
		local maxBuffs = #buffFrames
		for index = 1, maxBuffs do
			local iconFrame = buffFrames[index]
			if iconFrame.cooldown then
				iconFrame.cooldown:Hide()
			end
			if iconFrame.count then
				iconFrame.count:Hide()
			end
			iconFrame:Hide()
		end

		for auraIndex = 1, 40 do
			local name, _, icon, count, _, duration, expirationTime = UnitBuff(unit, auraIndex)
			if not name then
				break
			end

			buffsShown = buffsShown + 1
			if buffsShown > maxBuffs then
				buffsShown = maxBuffs
				break
			end

			local iconFrame = buffFrames[buffsShown]
			iconFrame.icon:SetTexture(icon)
			if duration and duration > 0 and expirationTime then
				iconFrame.cooldown:SetCooldown(expirationTime - duration, duration)
				iconFrame.cooldown:Show()
			else
				iconFrame.cooldown:Hide()
			end
			if count and count > 1 then
				iconFrame.count:SetText(count)
				iconFrame.count:Show()
			else
				iconFrame.count:Hide()
			end
			iconFrame:Show()
		end
	end

	local debuffFrames = frame.debuffs
	local debuffsShown = 0
	if debuffFrames and #debuffFrames > 0 then
		local maxDebuffs = #debuffFrames
		for index = 1, maxDebuffs do
			local iconFrame = debuffFrames[index]
			if iconFrame.cooldown then
				iconFrame.cooldown:Hide()
			end
			if iconFrame.count then
				iconFrame.count:Hide()
			end
			iconFrame:Hide()
		end

		for auraIndex = 1, 40 do
			local name, _, icon, count, debuffType, duration, expirationTime, caster = UnitDebuff(unit, auraIndex)
			if not name then
				break
			end

			if not filterDebuffs or (caster == "player" or caster == "pet" or caster == "vehicle") then
				debuffsShown = debuffsShown + 1
				if debuffsShown > maxDebuffs then
					debuffsShown = maxDebuffs
					break
				end

				local iconFrame = debuffFrames[debuffsShown]
				iconFrame.icon:SetTexture(icon)
				local color = DebuffTypeColor[debuffType or "none"] or DebuffTypeColor["none"]
				iconFrame.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
				iconFrame.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
				iconFrame.border:SetVertexColor(color[1], color[2], color[3])

				if duration and duration > 0 and expirationTime then
					iconFrame.cooldown:SetCooldown(expirationTime - duration, duration)
					iconFrame.cooldown:Show()
				else
					iconFrame.cooldown:Hide()
				end
				if count and count > 1 then
					iconFrame.count:SetText(count)
					iconFrame.count:Show()
				else
					iconFrame.count:Hide()
				end
				iconFrame:Show()
			end
		end

		for index = debuffsShown + 1, maxDebuffs do
			local iconFrame = debuffFrames[index]
			iconFrame.cooldown:Hide()
			iconFrame.count:Hide()
			iconFrame:Hide()
		end
	end

	local desiredOrder = buffsShown > 0 and 2 or 1
	if frame.debuffs and frame.debuffs.currentOrder ~= desiredOrder then
		Utils.PositionAuraRow(frame.debuffs, frame, frame.mirrored, "below", desiredOrder)
	end
end

-------------------------------------------------------------------------------
-- MODULE INITIALIZATION
-------------------------------------------------------------------------------

function Auras.Initialize(deps)
	-- Import dependencies
	Utils = deps.Utils
end

-------------------------------------------------------------------------------
-- MODULE EXPORTS
-------------------------------------------------------------------------------

Auras.UpdateUnitAuras = UpdateUnitAuras
Auras.HideAuraRows = HideAuraRows
