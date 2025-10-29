# Unit Frames Improved

![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)
![WoW](https://img.shields.io/badge/WoW-3.3.5a-orange.svg)
![Server](https://img.shields.io/badge/server-Ascension%20WR-purple.svg)

A complete unit frame replacement addon for **Ascension's Warcraft Reborn** private server, featuring custom-designed frames with enhanced functionality, cast bars, debuff tracking, right-click menus, and **fully movable frames**.

## ✨ Features

### 🎯 Complete Frame Suite

- **Player Frame** - Enhanced health/power display with resting indicator, custom right-click menu, and an 8-slot self-buff tracker (sorted by remaining time with curated exclusions)
- **Target Frame** - Elite/rare detection, target buffs, your debuffs, and a comprehensive interaction menu
- **Focus Frame** - Dedicated focus target tracking with target buffs, your debuffs, and right-click to clear focus
- **Target of Target** - See what your target is targeting at a glance

### 🎨 Visual Enhancements

- **Custom Textures** - Professional-looking frame borders and elite dragon overlays
- **Circular Portraits** - Clean 2D portraits with circular masking
- **Color-Coded Power Bars** - Mana, rage, energy, focus, and runic power with proper colors
- **Elite/Rare Indicators** - Gold elite, silver rare, and rare-elite dragon borders
- **Level Indicators** - Color-coded level text (grey, yellow, orange, red) based on difficulty
- **Status Text Integration** - Seamlessly integrates with WoW's Interface Options "Display Percentages" setting
  - Shows percentages (e.g., "75%") or numeric values (e.g., "15.2k / 20.3k")
  - Updates instantly when toggled in Interface Options → Status Text
  - No reload required - changes apply immediately

### ⚔️ Combat Features

- **Cast Bars** - Full casting and channeling tracking for target and focus
  - Interrupt-able indicators (shield icon when not interruptible)
  - Spell names and cast times
  - Smooth progress animations
- **Debuff Tracking** - Slim, player-focused aura rows
  - Target and focus frames show buffs plus only your (player/pet/vehicle) debuffs
  - Debuff row slides up when no buffs are active to avoid awkward gaps
  - Color-coded borders by debuff type with stack counts and OmniCC-friendly cooldown spirals

### 🖱️ Right-Click Menus

- **Player Frame Menu**
  - Dungeon Difficulty (Normal, Heroic, Mythic) with checkmarks
  - Raid Difficulty (10-25 Normal, Heroic, Mythic, Ascended) with checkmarks
  - Reset Instances with confirmation dialog
  - Raid Target Icons with colored text and icon previews
  - Cancel option
  
- **Target Frame Menu**
  - Whisper, Inspect, Invite
  - Compare Achievements
  - Trade, Follow, Duel
  - Raid Target Icons (same as player menu)
  - Smart disabling (greyed out when not applicable)
  - Auto-switches to player menu when targeting yourself

### 🎯 Focus Frame Features

- **Right-click to clear focus** - Quick and easy focus management
- **Secure implementation** - No taint issues with focus clearing
- All standard features (cast bar, debuffs, portrait, etc.)

### 📍 Movable Frames

- **Drag-to-Move** - Unlock frames to reposition them anywhere on screen
- **Instant Response** - Smooth, lag-free dragging with pixel-perfect precision
- **Visual Feedback** - Color-coded overlays (green=unlocked, yellow=dragging)
- **Position Persistence** - Frame locations saved per character
- **Combat Protection** - Frames auto-lock during combat to prevent taint
- **Reset Options** - Restore default positions individually or all at once
- **Slash Commands**:
  - `/ufi unlock` - Enable frame repositioning
  - `/ufi lock` - Lock frames and save positions
  - `/ufi reset [frame]` - Reset to defaults (player/target/focus/all)
  - `/ufi help` - Display all commands

## 📦 Installation

1. **Download** the addon files
2. **Extract** the `UnitFramesImproved` folder to your WoW directory:

   ```text
   World of Warcraft/Interface/AddOns/UnitFramesImproved/
   ```

3. **Restart** World of Warcraft or use `/reload` if already in-game
4. The addon loads automatically - **no configuration needed!**

## 📁 File Structure

```text
UnitFramesImproved/
├── UnitFramesImproved.lua    # Main addon code
├── UnitFramesImproved.toc    # Addon metadata
├── README.md                 # This file
└── Textures/
    ├── UI-FocusTargetingFrame.blp
    ├── UI-Player-Status.blp
    ├── UI-TargetingFrame.blp
    ├── UI-TargetingFrame-Elite.blp
    ├── UI-TargetingFrame-Rare.blp
    ├── UI-TargetingFrame-Rare-Elite.blp
    └── UI-UnitFrame-Boss.blp
```

## 🎮 Usage

### Basic Functionality

- Frames appear automatically and update in real-time
- **Player frame** is always visible
- **Target frame** shows when you have a target
- **Focus frame** appears when you set a focus target
- **Target of Target** displays when your target has a target

### Slash Commands

Type `/ufi help` in-game to see all available commands:

- **`/ufi unlock`** - Unlock frames for repositioning
  - Green overlays appear on player, target, and focus frames
  - Click and drag any frame to move it
  - Frames turn yellow while dragging for visual feedback
  
- **`/ufi lock`** - Lock frames and save positions
  - Saves current positions permanently
  - Overlays disappear and frames are locked in place
  
- **`/ufi reset [frame]`** - Reset frame positions to defaults
  - `/ufi reset player` - Reset only the player frame
  - `/ufi reset target` - Reset only the target frame
  - `/ufi reset focus` - Reset only the focus frame
  - `/ufi reset` - Reset all frames to defaults
  
- **`/ufi help`** - Display command help

### Frame Positioning

1. Type `/ufi unlock` to enable repositioning mode
2. Green overlays appear on movable frames
3. Click and drag any frame to your desired position
4. Frames turn yellow while dragging for visual feedback
5. Release to place the frame
6. Type `/ufi lock` to save positions and disable repositioning
7. Positions are automatically saved per character

**Note**: Frames automatically lock during combat to prevent taint issues.

### Focus Management

- **Set Focus**: Use the standard `/focus` command or Focus Target keybind
- **Clear Focus**: Right-click the focus frame for instant clearing

### Menu Interactions

- **Right-click Player Frame**: Access difficulty settings, raid icons, and instance reset
- **Right-click Target Frame**: Full interaction menu (whisper, trade, invite, etc.)
- **Raid Target Icons**: Color-coded with icon previews, checkmarks show current selection

### Status Text Display

The addon respects WoW's native "Display Percentages" setting:

1. Open Interface Options (Esc → Interface)
2. Navigate to **Status Text** panel
3. Check or uncheck **"Display Percentages"**
4. Your unit frames update instantly:
   - **Checked**: Shows percentages (e.g., "75%" health/power)
   - **Unchecked**: Shows numeric values (e.g., "15.2k / 20.3k")
5. No `/reload` required - changes apply immediately to all frames

### Difficulty Changes

1. Right-click your player frame
2. Select "Dungeon Difficulty" or "Raid Difficulty"
3. Choose your desired difficulty (checkmark shows current setting)
4. Difficulty changes apply immediately

## 🔧 Technical Details

### Taint-Free Design

- Uses **SecureUnitButtonTemplate** for all interactive frames
- Secure attributes for focus clearing (`*type2 = "clearfocus"`)
- No protected function taint issues
- Menu items filtered to avoid taint-causing operations
- Combat detection prevents frame repositioning during encounters
- **Secure hook integration** - Uses `hooksecurefunc` to detect CVar changes from Interface Options without polling

### Saved Variables

- **Per-character positions** - Each character has their own frame layout
- **Position validation** - Out-of-bounds positions automatically reset to defaults
- **Lock state persistence** - Remembers if frames were unlocked (restores on login if not in combat)

### Performance

- Efficient event handling with targeted updates
- Default Blizzard frames completely disabled (unregistered events)
- Optimized debuff sorting and display
- Smooth animations without frame rate impact
- Instant drag response with custom mouse tracking

### Compatibility

- **Target Server**: Ascension's Warcraft Reborn (3.3.5a)
- **OmniCC Support**: Cooldown numbers work automatically if installed
- Replaces default Blizzard unit frames completely

## Known Issues

- Reset Instances menu option shows confirmation but reset behavior depends on server implementation
- Some Blizzard global strings may not be localized in all languages

## 📝 Credits

**Addon Design & Development**: Custom unit frame implementation for Ascension WR

**Textures**: Based on Blizzard's default UI textures with custom modifications

**Inspired By**: Classic WoW unit frame design philosophy

## 📄 License

This addon is provided as-is for use on Ascension's Warcraft Reborn private server.

---

**Enjoy your enhanced unit frames! May your crits be plentiful and your interrupts on point!** ⚔️✨
