--[[
	UnitFramesImproved - Dropdown/Menu System
	Direct copy of oUF's dropdown implementation for private server compatibility
]]

---@diagnostic disable: undefined-global

local UFI = UnitFramesImproved

-------------------------------------------------------------------------------
-- REMOVE TAINT-CAUSING MENU ITEMS
-------------------------------------------------------------------------------

-- Remove taint-causing and unwanted menu items
-- Iterate backwards to avoid index shifting issues when removing items
for k in pairs(UnitPopupMenus) do
	for x = #UnitPopupMenus[k], 1, -1 do
		local y = UnitPopupMenus[k][x]
		if
			y == "SET_FOCUS"
			or y == "CLEAR_FOCUS"
			or y == "LOCK_FOCUS_FRAME"
			or y == "UNLOCK_FOCUS_FRAME"
			or y == "TOGGLE_DRAGON"
			or y == "PVP_FLAG"
		then
			table.remove(UnitPopupMenus[k], x)
		end
	end
end

-------------------------------------------------------------------------------
-- OUF DROPDOWN MENU SYSTEM
-------------------------------------------------------------------------------

local secureDropdown

local function InitializeSecureMenu(self)
	local unit = self.unit
	if not unit then
		return
	end

	local unitType = string.match(unit, "^([a-z]+)[0-9]+$") or unit

	local menu
	if unitType == "party" then
		menu = "PARTY"
	elseif unitType == "boss" then
		menu = "BOSS"
	elseif unitType == "focus" then
		menu = "FOCUS"
	elseif unitType == "arenapet" or unitType == "arena" then
		menu = "ARENAENEMY"
	elseif UnitIsUnit(unit, "player") then
		menu = "SELF"
	elseif UnitIsUnit(unit, "vehicle") then
		menu = "VEHICLE"
	elseif UnitIsUnit(unit, "pet") then
		menu = "PET"
	elseif UnitIsPlayer(unit) then
		if UnitInRaid(unit) then
			menu = "RAID_PLAYER"
		elseif UnitInParty(unit) then
			menu = "PARTY"
		else
			menu = "PLAYER"
		end
	elseif UnitIsUnit(unit, "target") then
		menu = "TARGET"
	end

	if menu then
		UnitPopup_ShowMenu(self, menu, unit)
	end
end

local function ToggleMenu(self, unit)
	if not secureDropdown then
		secureDropdown = CreateFrame("Frame", "UFI_SecureDropdown", nil, "UIDropDownMenuTemplate")
		secureDropdown:SetID(1)

		table.insert(UnitPopupFrames, secureDropdown:GetName())
		UIDropDownMenu_Initialize(secureDropdown, InitializeSecureMenu, "MENU")
	end

	if secureDropdown.openedFor and secureDropdown.openedFor ~= self then
		CloseDropDownMenus()
	end

	secureDropdown.unit = string.lower(unit)
	secureDropdown.openedFor = self

	ToggleDropDownMenu(1, nil, secureDropdown, "cursor")
end

-------------------------------------------------------------------------------
-- EXPORT TO NAMESPACE
-------------------------------------------------------------------------------

UFI.Dropdown = {
	ToggleMenu = ToggleMenu,
}
