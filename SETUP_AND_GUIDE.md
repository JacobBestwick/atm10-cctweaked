 # ATM10 CC:Tweaked Suite — Setup & Guide

**For:** All The Mods 10 (ATM10) · Minecraft 1.20.1 · NeoForge
**Requires:** CC:Tweaked + Advanced Peripherals
**Version:** 1.0

---

## Table of Contents

1. [Quick Start](#1-quick-start)
2. [File Structure](#2-file-structure)
3. [Installation](#3-installation)
4. [Shared Libraries](#4-shared-libraries)
5. [Computer Programs](#5-computer-programs)
6. [Turtle Programs](#6-turtle-programs)
7. [Pocket Programs](#7-pocket-programs)
8. [Monitor Programs](#8-monitor-programs)
9. [Blueprint System](#9-blueprint-system)
10. [Peripheral Reference](#10-peripheral-reference)
11. [Networking Guide](#11-networking-guide)
12. [Troubleshooting](#12-troubleshooting)
13. [Advanced Topics](#13-advanced-topics)

---

## 1. Quick Start

### Prerequisites

Install these mods (all available on CurseForge/Modrinth):
- **CC:Tweaked** — the core ComputerCraft fork for 1.20+
- **Advanced Peripherals** — adds meBridge, energyDetector, playerDetector, etc.

### One-Command Install

1. **Host the files** — push this repo to a public GitHub repository
2. **Edit `install.lua`** — set `BASE_URL` to your GitHub raw URL:
   ```lua
   local BASE_URL = "https://raw.githubusercontent.com/YOUR_NAME/YOUR_REPO/main/atm10"
   ```
3. **Upload `install.lua` to [pastebin.com](https://pastebin.com)** and note your code (e.g. `xxxxxxxx`)
4. **In-game** (on any CC:Tweaked Computer, Turtle, or Pocket Computer):
   ```
   pastebin get xxxxxxxx install
   install
   ```
5. The installer downloads all 30 files, creates directories, and optionally sets up auto-start
6. **Run the hub:**
   ```
   /atm10/hub
   ```

> **HTTP must be enabled** in your server/world config. See [Troubleshooting](#12-troubleshooting) if you get an HTTP error.

### Hosting on GitHub + Pastebin (Full Walkthrough)

This is the complete process from zero to working in-game installer.

#### Step 1 — Create a GitHub account (if you don't have one)

Go to [github.com](https://github.com) and sign up for a free account.

#### Step 2 — Create a new repository

1. Click the **+** button (top-right) → **New repository**
2. Fill in:
   - **Repository name:** e.g. `atm10-cctweaked` (anything you like)
   - **Description:** optional
   - **Visibility:** set to **Public** (the installer downloads raw files — private repos won't work without a token)
   - Leave everything else as default
3. Click **Create repository**

#### Step 3 — Push the files to GitHub

**Option A — Use the included bash script (easiest)**

A script is included that handles everything automatically: updating `install.lua`, committing, and pushing to `https://github.com/JacobBestwick/atm10-cctweaked`.

1. Open **Git Bash** in the project folder (right-click the folder → **Git Bash Here**)
2. Run: `bash push_to_github.sh`
3. Enter a commit message when prompted (or press Enter for the default)

> **First push?** GitHub will ask you to log in. Use a Personal Access Token instead of your password:
> github.com → Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new token
> Tick the **repo** scope. Paste the token as your password when prompted.

> Git Bash is included with the standard [Git for Windows](https://git-scm.com/download/win) installer.

**Option B — Git command line (manual)**

Open a terminal in the project folder (the one containing `atm10/`):

```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/JacobBestwick/atm10-cctweaked.git
git push -u origin main
```



**Option C — GitHub Desktop (no command line)**

1. Download [GitHub Desktop](https://desktop.github.com) and sign in
2. Click **File → Add Local Repository** and browse to this folder
3. If it says "not a git repository", click **create a repository here**
4. Write a summary like `Initial commit` and click **Commit to main**
5. Click **Publish repository** → choose your repo → **Publish**

#### Step 4 — Find your raw file URL

Your raw base URL is:
```
https://raw.githubusercontent.com/JacobBestwick/atm10-cctweaked/main/atm10
```

To verify it works after pushing, open this in a browser — it should show Lua code:
```
https://raw.githubusercontent.com/JacobBestwick/atm10-cctweaked/main/atm10/hub.lua
```

#### Step 5 — install.lua is already configured

`install.lua` already has the correct `BASE_URL` set:
```lua
local BASE_URL = "https://raw.githubusercontent.com/JacobBestwick/atm10-cctweaked/main/atm10"
```

No manual editing needed — the bash script keeps this up to date automatically.

#### Step 6 — Upload install.lua to Pastebin

1. Go to [pastebin.com](https://pastebin.com) (free account optional but recommended)
2. Open your local `atm10/install.lua` in any text editor
3. Select all (Ctrl+A), copy (Ctrl+C)
4. Paste into the Pastebin editor
5. Set:
   - **Syntax Highlighting:** Lua
   - **Paste Expiration:** Never (so it doesn't disappear)
   - **Paste Exposure:** Public or Unlisted
6. Click **Create New Paste**
7. Your pastebin code is the last part of the URL:
   `https://pastebin.com/`**`xxxxxxxx`** ← this 8-character code is what you need

#### Step 7 — In-game installation

On any CC:Tweaked Computer, Advanced Computer, Turtle, or Pocket Computer:

```
pastebin get xxxxxxxx install
install
```

That's it. The installer downloads everything from your GitHub repo automatically.

#### Updating files in the future

When you change any program file:
1. Save the file locally
2. Push to GitHub (GitHub Desktop or `git push`)
3. In-game, run `install` again — it re-downloads and overwrites everything
   (your config files in `/atm10/data/` are not touched)

---

## 2. File Structure

```
/atm10/
├── hub.lua                    ← Main launcher (run this)
├── startup.lua                ← Auto-start on boot (optional)
├── install.lua                ← First-time installer
│
├── lib/                       ← Shared libraries
│   ├── ui.lua                 ← UI framework
│   ├── detect.lua             ← Device & peripheral detection
│   ├── config.lua             ← Config persistence
│   ├── net.lua                ← Wireless networking
│   └── storage.lua            ← AE2/RS abstraction
│
├── programs/
│   ├── computer/              ← Computer programs
│   │   ├── base_monitor.lua
│   │   ├── craft_manager.lua
│   │   ├── power_grid.lua
│   │   ├── resource_tracker.lua
│   │   ├── farm_controller.lua
│   │   └── security_system.lua
│   │
│   ├── turtle/                ← Turtle programs
│   │   ├── smart_miner.lua
│   │   ├── quarry_turtle.lua
│   │   ├── builder_turtle.lua
│   │   ├── tree_farmer.lua
│   │   ├── mob_grinder.lua
│   │   └── tunnel_bore.lua
│   │
│   ├── pocket/                ← Pocket computer programs
│   │   ├── remote_dash.lua
│   │   ├── gps_nav.lua
│   │   ├── remote_craft.lua
│   │   ├── ender_link.lua
│   │   ├── portable_wiki.lua
│   │   └── player_scanner.lua
│   │
│   └── monitor/               ← Monitor programs
│       ├── big_display.lua
│       └── scoreboard.lua
│
├── blueprints/                ← Builder blueprints
│   ├── mob_farm.blueprint
│   └── mekanism_room.blueprint
│
└── data/                      ← Config & log files (auto-created)
    ├── default_config.lua
    └── *.cfg  *.log           ← Generated at runtime
```

---

## 3. Installation

### Standard Install (Pastebin)

```
pastebin get <YOUR_CODE> install
install
```

The installer will:
- Download all 30 program files from your GitHub repo
- Create the full directory tree under `/atm10/`
- Optionally write `/startup.lua` for auto-launch on boot
- Show a progress bar and report any failed downloads

### Re-installing / Updating

Just run `install` again. Files are overwritten, config in `/atm10/data/` is preserved.

### Manual Install (Floppy Disk)

If HTTP is not available:
1. Copy files to a floppy disk from outside the game
2. Insert floppy into the computer: `cp /disk/atm10 /atm10 -r`

### Verifying Installation

```lua
ls /atm10/lib/              -- should show 5 .lua files
ls /atm10/programs/computer -- should show 6 files
/atm10/hub                  -- should launch the hub menu
```

---

## 4. Shared Libraries

All programs require these libraries at `/atm10/lib/`. They are loaded with:

```lua
local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local ui = require("ui")
```

### `detect.lua` — Device Detection

```lua
local detect = require("detect")

detect.getDeviceType()
-- Returns: "computer" | "advanced_computer" | "turtle" |
--          "advanced_turtle" | "pocket" | "advanced_pocket"

detect.findPeripheral("meBridge")
-- Returns: peripheral, name (or nil, nil)
-- Scans local sides first, then wired/wireless network

detect.getPeripherals()
-- Returns categorized table:
-- { monitors={}, modems={}, storage={}, energy={},
--   advanced_peripherals={}, misc={} }
```

### `ui.lua` — User Interface

```lua
local ui = require("ui")

ui.drawHeader("Title", "Subtitle")     -- row 1 blue bar
ui.drawFooter("[Q] Quit  [Enter] OK") -- last row gray bar
ui.drawMenu(items, "Title")            -- scrollable menu, returns idx
-- items = { {label="...", description="..."}, ... }

ui.alert("Message", "success")  -- "success"|"info"|"warn"|"error"
ui.confirm("Delete this?")      -- returns true/false
ui.inputText("Prompt: ", "default")  -- returns string or nil
ui.pager(lines, "Title")        -- scrollable text viewer, [Q] to exit

ui.drawProgressBar(x, y, width, pct, fillColor, emptyColor, label)
ui.formatNumber(1234567)   -- "1.2M"
ui.formatEnergy(12345678)  -- "12.3 MFE"
ui.wordWrap(text, width)   -- returns table of lines
```

### `config.lua` — Configuration Persistence

All config is stored as serialized Lua tables in `/atm10/data/`.

```lua
local config = require("config")

local cfg = config.getOrDefault("myprogram.cfg", { key = "default" })
-- Loads existing file, fills in missing keys from defaults, saves & returns

config.save("myprogram.cfg", cfg)   -- serialize + write
config.load("myprogram.cfg")        -- returns table or nil

config.get("myprogram.cfg", "key", "fallback")
config.set("myprogram.cfg", "key", "value")

config.appendLog("mylog.log", "Something happened")
config.readLog("mylog.log", 50)  -- last 50 lines
```

### `net.lua` — Wireless Networking

Uses rednet over a wireless/ender modem. All messages use channel 4200-4299.

```lua
local net = require("net")

net.CHANNEL_BASE     = 4200
net.CHANNEL_TURTLE   = 4201
net.CHANNEL_POCKET   = 4202
net.CHANNEL_BROADCAST = 4299

net.hasModem()         -- true if any modem found
net.open(channel)      -- open a channel for listening
net.broadcast(channel, msgType, data)  -- fire and forget
net.requestResponse(channel, reqType, data, timeout)
-- Sends request with unique ID, waits for matching reply
-- Returns response.data table, or nil on timeout

net.serve(channel, handlers)
-- Blocking server loop. handlers = { ["msg_type"] = function(data, sender) }
-- Handles "terminate" cleanly via parallel.waitForAny
```

### `storage.lua` — AE2/RS Abstraction

```lua
local storage = require("storage")

storage.init()          -- finds meBridge or rsBridge
storage.getType()       -- "ae2" | "rs" | nil

storage.getItems()      -- {name, displayName, count, craftable}[]
storage.getItem(name)   -- first match (case-insensitive substring)
storage.searchItems(query)  -- filtered list

storage.craftItem(name, count)   -- {success, message}
storage.getCraftingJobs()        -- AE2 only; list of CPU job tables
```

---

## 5. Computer Programs

### `base_monitor.lua` — Live Base Dashboard

**Peripherals:** energyDetector, meBridge/rsBridge, environmentDetector, playerDetector (all optional)
**Monitor:** Optional external monitor for large display

Displays live panels: Power, Storage, Environment, Players, Clock, Log.

**Controls:**
- `[Q]` — Quit
- `[R]` — Force refresh
- `[C]` — Change refresh rate

**Setup:** Just run it. Place an Advanced Monitor adjacent for large display.

---

### `craft_manager.lua` — Autocrafting Manager

**Peripherals:** meBridge or rsBridge (required)

Monitors item counts and auto-crafts when stock falls below targets.

**Features:**
- 4 built-in profiles (Early Game, Mekanism Setup, AE2 Expansion, ATM Star Prep)
- Custom item targets
- Live status display
- Log file at `/atm10/data/craft_manager_log.log`

**Setup:**
1. Ensure meBridge or rsBridge is connected to the AE2/RS network
2. Run `craft_manager`
3. Select or create a profile
4. Start — it runs indefinitely

---

### `power_grid.lua` — Power Monitor

**Peripherals:** energyDetector (required), chatBox (optional for alerts)

Monitors your energy network with live percentage, flow rate, and history chart.

**Features:**
- Full-width progress bar with color coding
- Redstone output control rules (e.g., turn on generator at 20%)
- Chat alerts when power is critical
- ASCII history chart

**Setup:**
1. Place an Energy Detector adjacent to your main power conduit
2. Connect to computer with wired modem (or use adjacent side)
3. Run `power_grid`
4. Configure thresholds in Settings

---

### `resource_tracker.lua` — Progression Goal Tracker

**Peripherals:** meBridge or rsBridge (optional, for auto-checking counts)

Track your ATM10 progression goals. Mark items as obtained manually or auto-check from storage.

**Templates included:**
- Mekanism 5x Processing Setup
- AE2 Storage Network
- ATM Star Components
- Botania Terrasteel Tier
- Create Mechanical Crafting
- Powah Reactor Starter

---

### `farm_controller.lua` — Farm Automation

**Peripherals:** redstoneIntegrator or standard redstone sides, inventoryManager (optional)

Controls farms via redstone output. Turns farms on/off based on inventory fill levels.

**Setup:**
1. Connect redstoneIntegrator or use a standard side
2. Wire the computer's redstone output to your farm's power lever/gate
3. Configure fill thresholds in Settings
4. Enable auto-mode

---

### `security_system.lua` — Security Monitor

**Peripherals:** playerDetector (required), chatBox (optional), redstoneIntegrator (optional)

Monitors for non-whitelisted players. Triggers alerts and optional defenses.

**Setup:**
1. Place playerDetector in range of your base
2. Add your player name(s) to the whitelist
3. Configure alert radius and redstone response side
4. Arm the system

---

## 6. Turtle Programs

### General Turtle Tips

- **Fuel:** Always refuel before long operations. Coal = 80 moves, Lava bucket = 1000 moves.
- **Inventory:** Slot 1 is usually the "active" slot. Keep fuel in multiple slots.
- **Termination:** Press `Ctrl+T` in the turtle terminal to safely terminate a program.
- **Wired Modem:** Add a wired modem to enable the turtle to receive remote commands.

---

### `smart_miner.lua` — Branch Miner

Mines a main tunnel with branches left and right at configurable intervals.

**Config:**
| Option | Default | Description |
|--------|---------|-------------|
| `targetY` | -50 | Y level to mine at |
| `branchLength` | 16 | Length of each branch |
| `branchSpacing` | 4 | Blocks between branches |
| `numBranches` | 10 | Total branches per side |
| `torchInterval` | 8 | Place torch every N blocks |

**Required items:** Pickaxe tool, fuel, torches (optional), cobblestone (liquid sealing)

---

### `quarry_turtle.lua` — Area Quarry

Mines a rectangular area completely from top to configurable depth.

**Setup:**
1. Place turtle at the NW corner of desired area, facing East
2. Configure width, length, and depth in the menu
3. Turtle returns home when inventory is full — place a chest behind it

**Config:**
| Option | Default | Description |
|--------|---------|-------------|
| `width` | 16 | East-West size |
| `length` | 16 | North-South size |
| `depth` | 32 | How deep to dig |
| `selective` | false | Skip common stone |

---

### `builder_turtle.lua` — Blueprint Builder

Builds structures from `.blueprint` files.

**Usage:**
1. Load a blueprint file (from `/atm10/blueprints/`)
2. Check the material list
3. Stock the turtle's inventory with required blocks
4. Press Enter to start building

**Creating blueprints:** See Section 9.

---

### `tree_farmer.lua` — Automatic Tree Farm

Plants and harvests trees in a grid pattern.

**Setup:**
1. Clear a flat area, place turtle at SW corner
2. Dig a 1-block hole at each grid spot (or configure spacing)
3. Stock with saplings and bone meal
4. Place a chest behind the turtle for output

**Config:**
| Option | Default | Description |
|--------|---------|-------------|
| `gridWidth` | 5 | Trees per row |
| `gridLength` | 5 | Rows |
| `spacing` | 3 | Blocks between trees |
| `waitForGrowth` | 60 | Seconds to wait if no trees ready |

---

### `mob_grinder.lua` — Mob Patrol Grinder

Patrols an area attacking mobs, collects loot, returns to chest periodically.

**Setup:**
1. Build a dark room mob spawner (use the mob_farm blueprint)
2. Place turtle at center/front of spawn area
3. Place a chest directly behind the turtle
4. Run `mob_grinder`

---

### `tunnel_bore.lua` — Long Tunnel Builder

Bores a straight tunnel of configurable height and length.

**Features:**
- Liquid sealing (cobblestone fill)
- Gravel/sand ceiling support
- Torch and rail placement
- Floor fill for uneven terrain

**Usage:**
1. Face the turtle in the desired tunnel direction
2. Configure length and options
3. Press Enter to start

---

## 7. Pocket Programs

All pocket programs work on Basic Pocket Computers, but Advanced Pocket Computers provide color displays and the best experience.

**To attach a wireless modem:** Hold the modem in your hand and right-click the Pocket Computer in your inventory.

---

### `remote_dash.lua` — Remote Base Dashboard

Shows a compact version of your base status while away.

**Requirements:** Wireless modem on pocket + base running `base_monitor` or `hub` in server mode

**Setup:**
1. Configure your base computer's channel (default: 4200)
2. Open Remote Dash → Settings → Discover Base
3. Select your base computer
4. The dashboard auto-refreshes every 10 seconds

---

### `gps_nav.lua` — GPS Navigator

Shows your current coordinates and navigates to saved waypoints.

**Requirements:** GPS tower network (4+ towers at different X/Y/Z positions)

**GPS Tower Setup:**
```
On each tower computer run:
  gps host <x> <y> <z>
Where x,y,z are the tower's exact coordinates.
You need 4 towers in different positions for a 3D fix.
```

**Features:**
- Live position with 2s refresh
- Named waypoints (CRUD)
- Direction arrow + distance to target
- Share waypoints with other players via rednet

---

### `remote_craft.lua` — Remote Crafting Requester

Request crafting jobs from your AE2/RS network while away.

**Requirements:** Wireless modem on pocket + `craft_manager` running on base in server mode

**Features:**
- Search all items in storage
- Request crafting (craftable items only)
- Quick-craft presets (configurable)
- View active AE2 crafting queue

---

### `ender_link.lua` — Ender Chest Frequency Manager

Offline reference for your ender chest color frequencies.

**No peripheral required — works fully offline.**

Store and recall your ender chest color codes (e.g., `[W/O/M]` = White/Orange/Magenta).

**Color abbreviations:**
| Color | Abbr | Color | Abbr |
|-------|------|-------|------|
| White | W | Gray | Gy |
| Orange | O | Light Gray | LG |
| Magenta | M | Cyan | C |
| Light Blue | LB | Purple | Pu |
| Yellow | Y | Blue | B |
| Lime | L | Brown | Br |
| Pink | P | Green | G |
| — | — | Red | R |
| — | — | Black | Bk |

---

### `portable_wiki.lua` — ATM10 Quick Reference

Offline wiki covering all major mods.

**Sections:**
- Mekanism (overview, 5x processing, power, recipes)
- AE2 (crystals, storage, autocrafting)
- Botania (flowers, key recipes)
- Create (contraptions, machines)
- Powah (reactors, generators)
- Ore Processing (Y-level guide, ATM materials)
- Tips & Tricks

**User Notes:** Add your own notes within the wiki.
**Search:** Full-text search across all wiki content.

---

### `player_scanner.lua` — Player Scanner

Scans for nearby players with distance and position.

**Requirements:** `playerDetector` (Advanced Peripherals) attached to pocket computer or accessible via modem

**Features:**
- Live scan with configurable radius (up to 512 blocks)
- Auto-refresh every 3 seconds
- Color-coded distance (red = close, yellow = medium)
- Player detail view (health, armor, game mode if permitted)
- Warn radius highlight for close players

---

## 8. Monitor Programs

Monitor programs run on a **Computer** and drive an external **Advanced Monitor**.

**Monitor size recommendations:**
- `big_display.lua`: 3x2 or larger (minimum)
- `scoreboard.lua`: 4x3 or larger for split layout

**Connecting a monitor:** Place it adjacent to the computer, or use wired modems.

---

### `big_display.lua` — Big Monitor Display

Shows one of four display modes on a large external monitor.

**Modes:**
| Mode | Shows |
|------|-------|
| `clock` | Large time, day count, weather |
| `power` | Energy % bar, flow rate, warnings |
| `storage` | Item type count, byte usage |
| `welcome` | Server name, greeting, player count |

**Controls (keyboard):**
- `[N]` — Next mode
- `[P]` — Previous mode
- `[C]` — Toggle auto-cycle

**Touch input:** Tap left half of monitor = previous mode, right half = next mode.

**Auto-cycle:** Rotates through all configured modes every 15 seconds (configurable).

---

### `scoreboard.lua` — Multiplayer Scoreboard

Shows a live player list, shared task list, and scrolling message ticker.

**Features:**
- Real-time player list (requires playerDetector)
- Shared task list with completion tracking
- Pinned announcements
- Scrolling ticker bar with custom messages
- Split layout (players left, tasks right) on wide monitors

**Managing content:** Press `[T]` for tasks, `[M]` for messages, `[A]` for announcements while the scoreboard is running. Data is saved to `scoreboard_data.cfg` and can be shared between computers using the same file (via shared disk or copy).

---

## 9. Blueprint System

Blueprints are Lua files that return a table describing a structure.

### Blueprint Format

```lua
return {
  name        = "My Structure",
  description = "What it is",
  width       = 5,    -- X axis (left/right)
  height      = 3,    -- Y axis (up/down, layers)
  depth       = 5,    -- Z axis (forward/back)

  palette = {
    ["S"] = "minecraft:stone",
    ["W"] = "minecraft:oak_planks",
    [" "] = "air",
  },

  -- One table per Y layer, bottom first
  -- Each layer is a table of Z rows
  -- Each row is a string of X characters
  layers = {
    { "SSSSS", "S   S", "S   S", "S   S", "SSSSS" },
    { "SWWWS", "W   W", "W   W", "W   W", "SWWWS" },
    { "SSSSS", "SSSSS", "SSSSS", "SSSSS", "SSSSS" },
  },

  notes = { "Place turtle at SW corner.", "Face North." },
}
```

### Turtle Orientation

- Turtle starts at the **SW corner** (front-left of the structure)
- Turtle faces **North** (into the +Z direction)
- Layer 0 = floor (Y where turtle starts)
- Palette `" "` or `"air"` = skip (don't place anything)

### Included Blueprints

| File | Structure |
|------|-----------|
| `mob_farm.blueprint` | 9×9 dark room mob farm platform |
| `mekanism_room.blueprint` | 13×13 Mekanism machine room shell |

### Creating Custom Blueprints

1. Design your structure layer by layer on paper or in a text editor
2. Create a `.blueprint` file in `/atm10/blueprints/`
3. Load it in `builder_turtle.lua` → Browse Blueprints
4. Check the material list before starting

---

## 10. Peripheral Reference

### Advanced Peripherals — Quick Reference

| Peripheral | Type Name | What It Does |
|-----------|-----------|--------------|
| ME Bridge | `meBridge` | AE2 storage + crafting access |
| RS Bridge | `rsBridge` | Refined Storage access |
| Energy Detector | `energyDetector` | FE/t flow rate + stored energy |
| Environment Detector | `environmentDetector` | Weather, time, moon, biome |
| Player Detector | `playerDetector` | Nearby players, positions |
| Inventory Manager | `inventoryManager` | Chest/inventory contents |
| Redstone Integrator | `redstoneIntegrator` | Redstone I/O control |
| Block Reader | `blockReader` | Read block states/NBT |
| Geo Scanner | `geoScanner` | Underground ore scanning |
| Chat Box | `chatBox` | Send/receive chat messages |
| NBT Storage | `nbtStorage` | Persistent NBT data |

### Connecting Peripherals to Computers

**Direct connection:** Place peripheral adjacent to computer (any side).

**Wired network:**
1. Place a Wired Modem on each device
2. Connect with Networking Cable
3. Right-click each modem to enable it (turns red when active)
4. Peripheral is now accessible by name: `peripheral.wrap("meBridge_0")` etc.

**Wireless:**
1. Place Ender Modem on computer
2. Place Ender Modem on peripheral carrier computer
3. Both must be on same server — range is unlimited

### Finding Connected Peripherals

```lua
-- List all peripherals
for _, name in ipairs(peripheral.getNames()) do
  print(name, peripheral.getType(name))
end
```

---

## 11. Networking Guide

### Default Channels

| Channel | Purpose |
|---------|---------|
| 4200 | Base computer (status requests, crafting) |
| 4201 | Turtle coordination |
| 4202 | Pocket computer communications |
| 4299 | Broadcast (discovery, announcements) |

### Message Format

All messages use this envelope:
```lua
{
  type   = "atm10_message_type",
  data   = { ... },     -- payload
  sender = computerID,
  time   = os.clock(),
  requestId = "abc123"  -- for request/response pairs
}
```

### Setting Up Remote Crafting

1. On your base computer, run `craft_manager` and enable "Server Mode"
2. On your pocket computer, open `remote_craft` → Settings
3. Set the channel to match (default 4200)
4. Use "Discover Base" or enter the base computer's ID manually
5. You can now search storage and request crafting from anywhere on the server

### Setting Up Remote Dashboard

1. On your base computer, run `hub` and ensure "Network Server" is enabled
   OR run `base_monitor` which broadcasts status automatically
2. On pocket, open `remote_dash` → Settings → Discover Base
3. Select your base and start the dashboard

---

## 12. Troubleshooting

### "No modem found"
- Ensure a wireless modem is attached to your computer/pocket computer
- For turtles: attach a wireless modem with `turtle.equipLeft()` or place in slot
- Check `peripheral.getNames()` to list all connected peripherals

### "No meBridge/rsBridge found"
- Place the ME Bridge adjacent to your computer OR
- Use wired modem network: connect ME Bridge + computer with cables
- Right-click both modems to enable them (they should glow red)
- The peripheral name will be something like `meBridge_0`

### GPS returns nil
- You need 4+ GPS host computers at different X/Y/Z positions
- Each must run: `gps host <x> <y> <z>` (use exact coordinates!)
- Computers must have wireless modems attached
- You must be within ~256 blocks of at least 4 towers
- Test: `gps locate` in terminal — should return 3 numbers

### Programs crash with "attempt to index nil"
- A required peripheral is not connected
- The program gracefully handles most missing peripherals
- Check the hub's "Peripheral Status" screen for what's missing

### Config files corrupted
- Delete the `.cfg` file from `/atm10/data/`
- The program will regenerate defaults on next run
- `rm /atm10/data/myprogram.cfg`

### Turtle gets stuck
- Press `Ctrl+T` to terminate the running program
- The turtle's position tracking is saved in its config file
- Some programs support resuming from where they left off

### Colors not working
- Colors require an **Advanced** Computer/Monitor/Pocket Computer
- Basic variants are grayscale only
- The suite automatically detects and adapts with `term.isColor()`

### Hub shows wrong programs for my device
- The hub filters programs by device type automatically
- Turtle programs only show on turtles, pocket programs on pocket computers
- If running on wrong device, some programs may be hidden

---

## 13. Advanced Topics

### Running Multiple Programs

CC:Tweaked supports multitasking via `parallel` API:

```lua
parallel.waitForAny(
  function() shell.run("/atm10/programs/computer/base_monitor") end,
  function() shell.run("/atm10/programs/computer/craft_manager") end
)
```

Add this to your `/startup.lua` to run multiple programs at boot.

### Custom Rednet Protocols

To extend the suite with your own programs, follow the message format:

```lua
local net = require("net")
net.open(4200)

-- Send a request
local response = net.requestResponse(4200, "my_custom_request", {
  key = "value"
}, 5)

-- Or serve requests
net.serve(4200, {
  ["my_custom_request"] = function(data, sender)
    return { result = "ok", value = data.key .. "_processed" }
  end,
})
```

### Extending Craft Manager Profiles

Add your own profiles to `craft_manager.lua` in the `BUILTIN_PROFILES` table, or use the in-game "Add Custom Item" feature.

### Custom Wiki Sections

Edit `portable_wiki.lua` and add entries to the `WIKI` table:

```lua
WIKI["My Section"] = {
  {
    title = "My Page",
    lines = { "Line one", "Line two", ... },
  },
}
```

Then add your section name to `SECTION_NAMES`.

### Backup and Restore

Config files are plain Lua tables. Back them up:
```lua
cp /atm10/data/ /disk/backup/ -r
```

Restore:
```lua
cp /disk/backup/ /atm10/data/ -r
```

### Performance Tips

- Set `refreshRate` higher (10-30s) on base_monitor if using many peripherals
- The suite never busy-loops — all timers use `os.startTimer()` + events
- On large AE2 networks, `storage.getItems()` can be slow — cache results
- Use `craft_manager`'s `checkInterval` to reduce AE2 polling frequency

---

## Credits

Built for **All The Mods 10** (ATM10) on Minecraft 1.20.1 NeoForge.

- **CC:Tweaked** by SquidDev — [github.com/cc-tweaked/CC-Tweaked](https://github.com/cc-tweaked/CC-Tweaked)
- **Advanced Peripherals** by sirttas/MrHua — [advancedperipherals.mrmimeaut.com](https://advancedperipherals.mrmimeaut.com)
- **ATM10** modpack by AllTheMods team

---

*This suite is provided as-is for personal/server use in ATM10. Modify freely.*
