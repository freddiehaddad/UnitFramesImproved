--[[
	UnitFramesImproved - Core Initialization
	Provides: Namespace, utilities, constants, global frame references
]]

---@diagnostic disable: undefined-global

-- Create addon namespace
UnitFramesImproved = UnitFramesImproved or {}
local UFI = UnitFramesImproved

-------------------------------------------------------------------------------
-- VERSION & CONSTANTS
-------------------------------------------------------------------------------

UFI.VERSION = "2.0.0"
UFI.DB_SCHEMA_VERSION = 1

-------------------------------------------------------------------------------
-- COMPATIBILITY UTILITIES
-------------------------------------------------------------------------------

-- Provide a predictable table wipe helper that survives sandboxed Lua environments.
UFI.table_wipe = rawget(table, "wipe") or function(tbl)
	for key in pairs(tbl) do
		tbl[key] = nil
	end
end

-- Lua 5.1 compatibility
---@diagnostic disable-next-line: deprecated
UFI.unpack = unpack or table.unpack

-------------------------------------------------------------------------------
-- NUMBER FORMATTING
-------------------------------------------------------------------------------

-- Format large numbers with abbreviations (k/M/G).
function UFI.AbbreviateNumber(value)
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
-- TEXT COLOR CONSTANTS
-------------------------------------------------------------------------------

UFI.NAME_TEXT_COLOR_R = 1
UFI.NAME_TEXT_COLOR_G = 0.82
UFI.NAME_TEXT_COLOR_B = 0

-------------------------------------------------------------------------------
-- CHAT OUTPUT
-------------------------------------------------------------------------------

-- Emit addon-prefixed messages in the default chat frame.
function UFI.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[UFI]|r " .. tostring(msg))
end

-------------------------------------------------------------------------------
-- GLOBAL FRAME REFERENCES
-------------------------------------------------------------------------------

-- Frame references are kept global so the in-game `/dump` command can inspect them.
UFI_PlayerFrame = nil
UFI_TargetFrame = nil
UFI_FocusFrame = nil
UFI_TargetOfTargetFrame = nil
UFI_BossFrameAnchor = nil
