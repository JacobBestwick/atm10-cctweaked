-- hub.lua
-- ATM10 Hub Suite — Main Launcher
-- Device: All CC:Tweaked devices
-- The central dashboard for the ATM10 automation suite.
-- Detects device type and available peripherals, then presents
-- a menu of relevant programs.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path

local detect  = require("detect")
local ui      = require("ui")
local config  = require("config")
local storage = require("storage")

-- ─────────────────────────────────────────────
-- Constants
-- ─────────────────────────────────────────────
local VERSION    = "1.0.0"
local CFG_FILE   = "hub_config.cfg"
local PROG_DIR   = basePath .. "/programs/"

local DEFAULTS = {
  channel   = 4200,
  theme     = "default",
  autoStart = true,
  version   = VERSION,
}

-- ─────────────────────────────────────────────
-- Program registry
-- Each entry: { label, file, desc, devices, requires, optional }
--   devices  = list of device type strings (or {"all"})
--   requires = list of peripheral types needed (empty = none)
--   optional = list of peripheral types that add features
-- ─────────────────────────────────────────────
local PROGRAMS = {
  -- ── Computer ──────────────────────────────────────────────────────
  {
    label    = "Base Monitor",
    file     = PROG_DIR .. "computer/base_monitor.lua",
    desc     = "Live power, storage & weather dashboard",
    devices  = { "computer", "advanced_computer" },
    requires = {},
    optional = { "energyDetector", "meBridge", "rsBridge", "environmentDetector", "playerDetector", "monitor" },
  },
  {
    label    = "Craft Manager",
    file     = PROG_DIR .. "computer/craft_manager.lua",
    desc     = "Auto-stock items via AE2/RS crafting",
    devices  = { "computer", "advanced_computer" },
    requires = { "meBridge", "rsBridge" },  -- needs at least one
    requiresAny = true,
    optional = { "monitor" },
  },
  {
    label    = "Power Grid",
    file     = PROG_DIR .. "computer/power_grid.lua",
    desc     = "Monitor & auto-control your power network",
    devices  = { "computer", "advanced_computer" },
    requires = { "energyDetector" },
    optional = { "redstoneIntegrator", "chatBox", "monitor" },
  },
  {
    label    = "Resource Tracker",
    file     = PROG_DIR .. "computer/resource_tracker.lua",
    desc     = "Track ATM10 progression goals & item needs",
    devices  = { "computer", "advanced_computer" },
    requires = {},
    optional = { "meBridge", "rsBridge" },
  },
  {
    label    = "Farm Controller",
    file     = PROG_DIR .. "computer/farm_controller.lua",
    desc     = "Automate farm on/off by storage levels",
    devices  = { "computer", "advanced_computer" },
    requires = { "redstoneIntegrator" },
    optional = { "inventoryManager" },
  },
  {
    label    = "Security System",
    file     = PROG_DIR .. "computer/security_system.lua",
    desc     = "Player detection alerts & base defense",
    devices  = { "computer", "advanced_computer" },
    requires = { "playerDetector" },
    optional = { "chatBox", "redstoneIntegrator", "environmentDetector" },
  },
  -- ── Turtle ────────────────────────────────────────────────────────
  {
    label    = "Smart Miner",
    file     = PROG_DIR .. "turtle/smart_miner.lua",
    desc     = "Configurable branch miner with ore detection",
    devices  = { "turtle", "advanced_turtle" },
    requires = {},
    optional = { "geoScanner", "inventoryManager" },
  },
  {
    label    = "Quarry",
    file     = PROG_DIR .. "turtle/quarry_turtle.lua",
    desc     = "Excavate a defined rectangular area",
    devices  = { "turtle", "advanced_turtle" },
    requires = {},
    optional = { "geoScanner" },
  },
  {
    label    = "Builder",
    file     = PROG_DIR .. "turtle/builder_turtle.lua",
    desc     = "Build structures from blueprint files",
    devices  = { "turtle", "advanced_turtle" },
    requires = {},
    optional = { "blockReader" },
  },
  {
    label    = "Tree Farmer",
    file     = PROG_DIR .. "turtle/tree_farmer.lua",
    desc     = "Automated tree farm with replanting",
    devices  = { "turtle", "advanced_turtle" },
    requires = {},
    optional = {},
  },
  {
    label    = "Mob Grinder",
    file     = PROG_DIR .. "turtle/mob_grinder.lua",
    desc     = "Patrol and loot a mob farm area",
    devices  = { "turtle", "advanced_turtle" },
    requires = {},
    optional = { "inventoryManager" },
  },
  {
    label    = "Tunnel Bore",
    file     = PROG_DIR .. "turtle/tunnel_bore.lua",
    desc     = "Drill a lit, rail-ready tunnel",
    devices  = { "turtle", "advanced_turtle" },
    requires = {},
    optional = {},
  },
  -- ── Pocket ────────────────────────────────────────────────────────
  {
    label    = "Remote Dash",
    file     = PROG_DIR .. "pocket/remote_dash.lua",
    desc     = "Base status over wireless rednet",
    devices  = { "pocket", "advanced_pocket" },
    requires = {},
    optional = {},
  },
  {
    label    = "GPS Navigator",
    file     = PROG_DIR .. "pocket/gps_nav.lua",
    desc     = "GPS coordinates & waypoint manager",
    devices  = { "pocket", "advanced_pocket" },
    requires = {},
    optional = {},
  },
  {
    label    = "Remote Craft",
    file     = PROG_DIR .. "pocket/remote_craft.lua",
    desc     = "Request AE2/RS crafting remotely",
    devices  = { "pocket", "advanced_pocket" },
    requires = {},
    optional = {},
  },
  {
    label    = "Ender Link",
    file     = PROG_DIR .. "pocket/ender_link.lua",
    desc     = "Ender chest frequency label manager",
    devices  = { "pocket", "advanced_pocket" },
    requires = {},
    optional = {},
  },
  {
    label    = "Portable Wiki",
    file     = PROG_DIR .. "pocket/portable_wiki.lua",
    desc     = "ATM10 quick reference & recipes",
    devices  = { "pocket", "advanced_pocket" },
    requires = {},
    optional = {},
  },
  {
    label    = "Player Scanner",
    file     = PROG_DIR .. "pocket/player_scanner.lua",
    desc     = "Detect nearby players",
    devices  = { "advanced_pocket" },
    requires = { "playerDetector" },
    optional = {},
  },
  -- ── Monitor (run from a computer) ─────────────────────────────────
  {
    label    = "Big Display",
    file     = PROG_DIR .. "monitor/big_display.lua",
    desc     = "Multi-monitor dashboard renderer",
    devices  = { "computer", "advanced_computer" },
    requires = { "monitor" },
    optional = { "energyDetector", "meBridge", "rsBridge", "environmentDetector", "playerDetector" },
  },
  {
    label    = "Scoreboard",
    file     = PROG_DIR .. "monitor/scoreboard.lua",
    desc     = "Multiplayer info board on a monitor",
    devices  = { "computer", "advanced_computer" },
    requires = { "monitor", "playerDetector" },
    requiresAll = true,
    optional = { "chatBox" },
  },
}

-- ─────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────
local deviceType = detect.getDeviceType()
local cfg        = {}

-- Check if all listed peripherals are present
local function allPresent(list)
  for _, pType in ipairs(list) do
    if not detect.hasPeripheral(pType) then return false, pType end
  end
  return true, nil
end

-- Check if at least one listed peripheral is present
local function anyPresent(list)
  for _, pType in ipairs(list) do
    if detect.hasPeripheral(pType) then return true end
  end
  return false
end

-- Check if a program is relevant to the current device
local function forThisDevice(prog)
  for _, d in ipairs(prog.devices) do
    if d == deviceType or d == "all" then return true end
  end
  return false
end

-- Check if required peripherals are met
local function meetsRequirements(prog)
  if #prog.requires == 0 then return true, nil end
  if prog.requiresAny then
    return anyPresent(prog.requires), nil
  end
  return allPresent(prog.requires)
end

-- Build the list of programs for this device, annotated with availability
local function buildProgramList()
  local list = {}
  for _, prog in ipairs(PROGRAMS) do
    if forThisDevice(prog) then
      local ok, missing = meetsRequirements(prog)
      table.insert(list, {
        prog    = prog,
        ready   = ok,
        missing = missing,
      })
    end
  end
  return list
end

-- ─────────────────────────────────────────────
-- Splash screen
-- ─────────────────────────────────────────────
local function drawSplash()
  ui.clear()
  local w, h = term.getSize()
  local isAdv = detect.isAdvanced()

  if isAdv then
    ui.setColor(colors.blue, colors.black)
    term.setCursorPos(1, 1)
    term.write(string.rep("=", w))

    ui.setColor(colors.yellow, colors.black)
    ui.writeCentered(3,  " ___  _____ __  __ _  ___  ")
    ui.writeCentered(4,  "/ _ \\|_   _|  \\/  / |/ _ \\ ")
    ui.writeCentered(5,  "\\__  / | | | |\\/| | | | | |")
    ui.writeCentered(6,  "  / /  | | | |  | | | |_| |")
    ui.writeCentered(7,  " /_/   |_| |_|  |_|_|\\___/ ")

    ui.setColor(colors.cyan, colors.black)
    ui.writeCentered(9,  "H U B   S U I T E  v" .. VERSION)

    ui.setColor(colors.white, colors.black)
    ui.writeCentered(11, "All The Mods 10  |  MC 1.20.1")

    ui.setColor(colors.blue, colors.black)
    term.setCursorPos(1, 13)
    term.write(string.rep("=", w))

    ui.setColor(colors.lightGray, colors.black)
    ui.writeCentered(15, "Device: " .. detect.getDeviceName())
    ui.writeCentered(16, "ID: " .. tostring(os.getComputerID()))
    local label = os.getComputerLabel()
    if label then
      ui.writeCentered(17, "Label: " .. label)
    end

    ui.setColor(colors.gray, colors.black)
    ui.writeCentered(h, "Loading...")
    ui.resetColor()
  else
    term.setCursorPos(1, 2)
    print(string.rep("=", w))
    print("     ATM10 HUB SUITE v" .. VERSION)
    print(string.rep("=", w))
    print()
    print("Device: " .. detect.getDeviceName())
    print("ID: " .. tostring(os.getComputerID()))
    print()
    print("Loading...")
  end

  sleep(1.5)
end

-- ─────────────────────────────────────────────
-- Programs screen
-- ─────────────────────────────────────────────
local function runPrograms()
  local progList = buildProgramList()

  while true do
    -- Build menu items
    local items = {}
    for _, entry in ipairs(progList) do
      local label = entry.prog.label
      if not entry.ready then
        label = label .. " [MISSING PERIPH]"
      end
      table.insert(items, {
        label       = label,
        description = entry.prog.desc,
        enabled     = true,  -- always show, handle missing inside
      })
    end
    table.insert(items, { label = "< Back", description = "", enabled = true })

    local idx = ui.drawMenu(items, "Programs")
    if not idx or idx == #items then return end

    local entry = progList[idx]
    local prog  = entry.prog

    -- Check if file exists
    if not fs.exists(prog.file) then
      ui.alert(
        prog.label .. " program file not found.\n" ..
        "Expected: " .. prog.file .. "\n" ..
        "Try reinstalling the suite.",
        "error"
      )

    elseif not entry.ready then
      -- Build a helpful missing-peripheral message
      local missing = {}
      if prog.requiresAny then
        local opts = table.concat(prog.requires, " or ")
        table.insert(missing, opts)
      else
        for _, pType in ipairs(prog.requires) do
          if not detect.hasPeripheral(pType) then
            table.insert(missing, pType)
          end
        end
      end
      local msgParts = {
        prog.label .. " needs: " .. table.concat(missing, ", "),
        "",
        "Craft the peripheral from Advanced Peripherals",
        "and place it adjacent to this " .. detect.getDeviceName(),
        "or connect via a wired modem network.",
      }
      ui.alert(table.concat(msgParts, "\n"), "warn")

    else
      -- Launch the program
      ui.clear()
      local ok, err = pcall(shell.run, prog.file)
      if not ok then
        ui.alert("Program crashed:\n" .. tostring(err), "error")
      end
      -- Refresh program list in case peripherals changed
      progList = buildProgramList()
    end
  end
end

-- ─────────────────────────────────────────────
-- Peripherals screen
-- ─────────────────────────────────────────────
local function showPeripherals()
  while true do
    local periph = detect.getPeripherals()
    local net    = detect.getNetworkedPeripherals()

    -- Build flat list: { name, type, source }
    local all = {}
    local function addGroup(group, source)
      for _, e in ipairs(group) do
        table.insert(all, { name = e.name, pType = e.type, source = source })
      end
    end
    addGroup(periph.monitors,             "local")
    addGroup(periph.modems,               "local")
    addGroup(periph.storage,              "local")
    addGroup(periph.energy,               "local")
    addGroup(periph.advanced_peripherals, "local")
    addGroup(periph.misc,                 "local")
    for _, e in ipairs(net) do
      table.insert(all, { name = e.name, pType = e.type, source = "net:" .. (e.via or "?") })
    end

    if #all == 0 then
      ui.alert("No peripherals detected.\n\nAttach peripherals to the sides\nof this device or via wired modem.", "info")
      return
    end

    -- Build pager lines
    local lines = {
      "Detected Peripherals  (" .. #all .. " total)",
      string.rep("-", 40),
      string.format("%-20s %-18s %s", "Name", "Type", "Source"),
      string.rep("-", 40),
    }
    for _, e in ipairs(all) do
      table.insert(lines, string.format("%-20s %-18s %s",
        e.name:sub(1, 19), e.pType:sub(1, 17), e.source))
    end
    table.insert(lines, "")
    table.insert(lines, "Networked peripherals shown with 'net:side'.")
    table.insert(lines, "Press Q to return.")

    ui.pager(lines, "Peripherals")
    return
  end
end

-- ─────────────────────────────────────────────
-- Settings screen
-- ─────────────────────────────────────────────
local function showSettings()
  while true do
    local items = {
      { label = "Set Computer Label",  description = "Name this device" },
      { label = "Rednet Channel",      description = "ch " .. tostring(cfg.channel) },
      { label = "Toggle Auto-Start",   description = cfg.autoStart and "ON" or "OFF" },
      { label = "Theme",               description = cfg.theme },
      { label = "< Back",              description = "" },
    }

    local idx = ui.drawMenu(items, "Settings")
    if not idx or idx == 5 then return end

    if idx == 1 then
      -- Set label
      local current = os.getComputerLabel() or ""
      local label = ui.inputText("New label (blank = clear): ", current)
      if label and label ~= "" then
        os.setComputerLabel(label)
        ui.alert("Label set to: " .. label, "success")
      elseif label == "" then
        os.setComputerLabel(nil)
        ui.alert("Label cleared.", "info")
      end

    elseif idx == 2 then
      -- Rednet channel
      local raw = ui.inputText("Channel number (1-65535): ", tostring(cfg.channel))
      local ch  = tonumber(raw)
      if ch and ch >= 1 and ch <= 65535 then
        cfg.channel = ch
        config.save(CFG_FILE, cfg)
        ui.alert("Channel set to " .. ch, "success")
      else
        ui.alert("Invalid channel. Must be 1-65535.", "warn")
      end

    elseif idx == 3 then
      -- Toggle auto-start
      cfg.autoStart = not cfg.autoStart
      config.save(CFG_FILE, cfg)

      if cfg.autoStart then
        -- Write startup.lua
        local f = fs.open("/startup.lua", "w")
        if f then
          f.write('local ok,e=pcall(function() if fs.exists("/atm10/hub.lua") then shell.run("/atm10/hub.lua") else printError("ATM10 Hub not found.") end end) if not ok then printError("Hub crashed: "..tostring(e)) end\n')
          f.close()
          ui.alert("Auto-start ENABLED.\n/startup.lua written.", "success")
        else
          ui.alert("Could not write /startup.lua.", "error")
        end
      else
        if fs.exists("/startup.lua") then
          fs.delete("/startup.lua")
        end
        ui.alert("Auto-start DISABLED.\n/startup.lua removed.", "info")
      end

    elseif idx == 4 then
      -- Theme
      local themes = { "default", "dark", "high_contrast" }
      local tidx = ui.drawMenu(
        { "Default", "Dark", "High Contrast", "< Back" },
        "Select Theme"
      )
      if tidx and tidx <= 3 then
        cfg.theme = themes[tidx]
        config.save(CFG_FILE, cfg)
        ui.alert("Theme set to: " .. cfg.theme .. "\n(Restart hub to apply fully.)", "success")
      end
    end
  end
end

-- ─────────────────────────────────────────────
-- About screen
-- ─────────────────────────────────────────────
local function showAbout()
  local periph = detect.getPeripherals()
  local storCount = #periph.storage
  local apCount   = #periph.advanced_peripherals

  storage.init()
  local storType = storage.getType()

  local lines = {
    "ATM10 Hub Suite  v" .. VERSION,
    string.rep("=", 36),
    "",
    "Compatible with All The Mods 10",
    "Minecraft 1.20.1  |  NeoForge",
    "",
    string.rep("-", 36),
    "This Device",
    string.rep("-", 36),
    "  Type:  " .. detect.getDeviceName(),
    "  ID:    " .. tostring(os.getComputerID()),
    "  Label: " .. (os.getComputerLabel() or "(none)"),
    "  Color: " .. (detect.isAdvanced() and "Yes" or "No"),
    "",
    string.rep("-", 36),
    "Detected Peripherals",
    string.rep("-", 36),
    "  Monitors:    " .. #periph.monitors,
    "  Modems:      " .. #periph.modems,
    "  Storage:     " .. storCount .. "  (" .. storType .. ")",
    "  Energy:      " .. #periph.energy,
    "  Adv. Periph: " .. apCount,
    "  Other:       " .. #periph.misc,
    "",
    string.rep("-", 36),
    "Credits",
    string.rep("-", 36),
    "  Built for ATM10 modpack players.",
    "  CC:Tweaked + Advanced Peripherals.",
    "",
    "  Press Q to return.",
  }
  ui.pager(lines, "About")
end

-- ─────────────────────────────────────────────
-- Main hub menu
-- ─────────────────────────────────────────────
local function hubMenu()
  cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  while true do
    -- Subtitle: device + label
    local subtitle = detect.getDeviceName()
    local lbl = os.getComputerLabel()
    if lbl then subtitle = lbl .. " (" .. subtitle .. ")" end

    -- Count available programs for badge
    local progList = buildProgramList()
    local readyCount = 0
    for _, e in ipairs(progList) do
      if e.ready then readyCount = readyCount + 1 end
    end

    local items = {
      { label = "Programs",    description = readyCount .. " available" },
      { label = "Peripherals", description = "View attached devices"    },
      { label = "Settings",    description = "Configure this device"    },
      { label = "About",       description = "v" .. VERSION             },
      { label = "Exit Hub",    description = "Return to CraftOS shell"  },
    }

    local idx = ui.drawMenu(items, subtitle)
    if not idx or idx == 5 then
      ui.clear()
      ui.resetColor()
      print("ATM10 Hub closed. Type '/atm10/hub.lua' to restart.")
      return
    end

    if idx == 1 then
      runPrograms()
    elseif idx == 2 then
      showPeripherals()
    elseif idx == 3 then
      showSettings()
    elseif idx == 4 then
      showAbout()
    end
  end
end

-- ─────────────────────────────────────────────
-- Entry point
-- ─────────────────────────────────────────────
local ok, err = pcall(function()
  drawSplash()
  hubMenu()
end)

if not ok then
  if term.isColor() then term.setTextColor(colors.red) end
  print("ATM10 Hub encountered a fatal error:")
  print(tostring(err))
  if term.isColor() then term.setTextColor(colors.white) end
  print("Press any key to exit.")
  os.pullEvent("key")
end
