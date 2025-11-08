# AGENTS.md - UnitFramesImproved

## Build/Test Commands
- **No build system**: WoW addon - copy to `World of Warcraft/Interface/AddOns/UnitFramesImproved/`
- **No automated tests**: Manual in-game testing required (`/reload` after changes)
- **Test commands**: `/ufi help`, `/ufi unlock`, `/ufi lock`, `/ufi reset [frame]`

## Code Style Guidelines

### Language & Environment
- **Lua 5.1** (WoW 3.3.5a) - no modern Lua features (goto, bitwise ops, etc.)
- Use `---@diagnostic disable-next-line` for expected WoW API globals
- Global frames (e.g., `UFI_PlayerFrame`) allowed for WoW integration

### Naming Conventions
- `PascalCase`: Frame names, global functions, constructors (e.g., `CreateUnitFrame`)
- `camelCase`: Local variables/functions (e.g., `healthBar`, `applyPosition`)
- `SCREAMING_SNAKE_CASE`: Constants/config (e.g., `FRAME_TEXTURES`, `MAX_BOSS_FRAMES`)
- Prefix addon frames with `UFI_` (e.g., `UFI_TargetFrame`)

### Tables & Immutability
- Use `FreezeTable(tbl, "label")` for config tables to prevent mutations
- Use `table_wipe()` instead of `table.wipe` for sandbox compatibility
- Forward declare with `local FunctionName` before definition

### WoW API & Taint Prevention
- Use `SecureUnitButtonTemplate` for clickable frames (prevents taint)
- Hook with `hooksecurefunc()`, never replace Blizzard functions
- Check `InCombatLockdown()` before modifying secure frames
- Defer position changes with `pendingPositions` table if in combat

### Error Handling
- Use `assert()` for required config params (e.g., `assert(config.name, "CreateUnitFrame requires a frame name")`)
- Validate saved data with explicit functions (e.g., `ValidatePosition()`)
- Provide fallbacks for missing data (e.g., `db.positions or {}`, `defaultPositions[frameName]`)

### Comments
- Block comments `--[[ ]]` for file/section headers
- Single-line `--` for inline explanations and forward declarations
