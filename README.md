# Unit Frames Improved

![Version](https://img.shields.io/badge/version-1.3.3-blue.svg)
![WoW](https://img.shields.io/badge/WoW-3.3.5a-orange.svg)
![Server](https://img.shields.io/badge/server-Ascension%20WR-purple.svg)

A complete unit frame replacement addon for **Ascension's Warcraft Reborn** private server, featuring custom-designed frames with enhanced functionality, cast bars, debuff tracking, and right-click menus.

## ✨ Features

### 🎯 Complete Frame Suite

- **Player Frame** - Enhanced health/power display with resting indicator and custom right-click menu
- **Target Frame** - Elite/rare detection, classification visuals, and comprehensive interaction menu
- **Focus Frame** - Dedicated focus target tracking with right-click to clear focus
- **Target of Target** - See what your target is targeting at a glance

### 🎨 Visual Enhancements

- **Custom Textures** - Professional-looking frame borders and elite dragon overlays
- **Circular Portraits** - Clean 2D portraits with circular masking
- **Color-Coded Power Bars** - Mana, rage, energy, focus, and runic power with proper colors
- **Elite/Rare Indicators** - Gold elite, silver rare, and rare-elite dragon borders
- **Level Indicators** - Color-coded level text (grey, yellow, orange, red) based on difficulty

### ⚔️ Combat Features

- **Cast Bars** - Full casting and channeling tracking for target and focus
  - Interrupt-able indicators (shield icon when not interruptible)
  - Spell names and cast times
  - Smooth progress animations
- **Debuff Tracking** - Priority-based debuff display
  - Your debuffs shown first
  - Color-coded borders by debuff type (poison, disease, curse, magic)
  - Stack counts and cooldown spirals (OmniCC compatible)

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

### Focus Management

- **Set Focus**: Use the standard `/focus` command or Focus Target keybind
- **Clear Focus**: Right-click the focus frame for instant clearing

### Menu Interactions

- **Right-click Player Frame**: Access difficulty settings, raid icons, and instance reset
- **Right-click Target Frame**: Full interaction menu (whisper, trade, invite, etc.)
- **Raid Target Icons**: Color-coded with icon previews, checkmarks show current selection

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

### Performance

- Efficient event handling with targeted updates
- Default Blizzard frames completely disabled (unregistered events)
- Optimized debuff sorting and display
- Smooth animations without frame rate impact

### Compatibility

- **Target Server**: Ascension's Warcraft Reborn (3.3.5a)
- **OmniCC Support**: Cooldown numbers work automatically if installed
- Replaces default Blizzard unit frames completely

## 🚀 Upcoming Features

> **Future Version Roadmap**

### Frame Positioning

- **Drag-to-move functionality** - Reposition frames anywhere on screen
- **Saved positions** - Frame locations persist between sessions
- **Reset to defaults** - Restore original positions with one click

### Enhanced Focus Controls

- **Ctrl+Click to Set/Clear Focus** - Direct frame interaction for focus management
- **Quick focus swapping** - Easier focus target workflows for PvP and raids

Stay tuned for these exciting updates!

## 🐛 Known Issues

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
