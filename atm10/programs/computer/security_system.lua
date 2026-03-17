-- security_system.lua
-- ATM10 Base Security & Alert System
-- Device: Computer / Advanced Computer
-- Required: playerDetector (Advanced Peripherals Player Detector)
-- Optional: chatBox, redstoneIntegrator, environmentDetector
--
-- Monitors for non-whitelisted players and triggers alerts
-- via chat, redstone, and on-screen warnings. Perfect for
-- protecting your ATM10 base on multiplayer servers.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local detect = require("detect")
local ui     = require("ui")
local config = require("config")

-- ─────────────────────────────────────────────
-- Constants
-- ─────────────────────────────────────────────
local CFG_FILE = "security.cfg"
local LOG_FILE = "security_log.txt"

local DEFAULTS = {
  whitelist      = {},
  alertRadius    = 16,
  chatAlerts     = true,
  redstoneAlerts = false,
  redstoneSide   = "top",
  logAlerts      = true,
  scanInterval   = 3,
}

-- ─────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────
local cfg      = {}
local running  = true
local armed    = false
local flashState = false

-- Peripherals
local playerDet = nil
local chatBox   = nil
local rsIntegr  = nil
local envDet    = nil

local function discoverPeripherals()
  playerDet, _ = detect.findPeripheral("playerDetector")
  chatBox,    _ = detect.findPeripheral("chatBox")
  rsIntegr,   _ = detect.findPeripheral("redstoneIntegrator")
  envDet,     _ = detect.findPeripheral("environmentDetector")
end

-- ─────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────
local function isWhitelisted(playerName)
  for _, name in ipairs(cfg.whitelist) do
    if name:lower() == playerName:lower() then return true end
  end
  return false
end

local function getPlayers()
  if not playerDet then return {} end
  local ok, players = pcall(playerDet.getPlayersInRange, cfg.alertRadius)
  if not ok or type(players) ~= "table" then return {} end
  return players
end

local function getPlayerPos(name)
  if not playerDet then return nil end
  local ok, pos = pcall(playerDet.getPlayerPos, name)
  if ok and type(pos) == "table" then return pos end
  return nil
end

local function triggerAlert(player, pos)
  local posStr = "unknown position"
  if pos then
    posStr = string.format("%.0f, %.0f, %.0f", pos.x or 0, pos.y or 0, pos.z or 0)
  end

  -- Chat alert
  if cfg.chatAlerts and chatBox then
    local msg = "[ATM10 SECURITY] INTRUDER: " .. player .. " detected at " .. posStr
    pcall(chatBox.sendMessage, msg)
  end

  -- Redstone pulse alert
  if cfg.redstoneAlerts and rsIntegr then
    pcall(rsIntegr.setOutput, cfg.redstoneSide, true)
    -- Pulse: will reset next scan
  end

  -- Log
  if cfg.logAlerts then
    config.appendLog(LOG_FILE,
      "ALERT: " .. player .. " at " .. posStr)
  end
end

-- ─────────────────────────────────────────────
-- Armed monitoring loop
-- ─────────────────────────────────────────────
local function runArmed()
  local scanTimer    = os.startTimer(cfg.scanInterval)
  local armedRunning = true
  local knownPlayers = {}
  local intruderList = {}
  local alertCount   = 0

  -- Reset redstone
  if rsIntegr and cfg.redstoneAlerts then
    pcall(rsIntegr.setOutput, cfg.redstoneSide, false)
  end

  local function doScan()
    flashState = not flashState
    local players = getPlayers()
    intruderList  = {}

    for _, name in ipairs(players) do
      if not isWhitelisted(name) then
        local pos = getPlayerPos(name)
        table.insert(intruderList, { name = name, pos = pos })

        -- Only alert if newly detected (not in knownPlayers)
        if not knownPlayers[name] then
          triggerAlert(name, pos)
          alertCount = alertCount + 1
        end
        knownPlayers[name] = true
      else
        knownPlayers[name] = nil  -- reset tracking for whitelisted
      end
    end

    -- Reset redstone after a pulse
    if cfg.redstoneAlerts and rsIntegr and #intruderList == 0 then
      pcall(rsIntegr.setOutput, cfg.redstoneSide, false)
    end

    -- Redraw
    local w, h = term.getSize()
    ui.clear()

    -- ARMED header (flash red on intruder)
    local hasIntruder = #intruderList > 0
    local headerBg    = hasIntruder and (flashState and colors.red or colors.orange) or colors.blue
    local headerText  = hasIntruder and "! INTRUDER DETECTED !" or "ARMED - All Clear"

    ui.setColor(colors.white, headerBg)
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", w))
    ui.writeCentered(1, "ATM10 SECURITY | " .. headerText)
    ui.resetColor()

    local row = 3

    -- Player list
    if #players == 0 then
      ui.setColor(colors.gray, colors.black)
      ui.writeCentered(row, "No players in range (" .. cfg.alertRadius .. "m)")
      row = row + 2
    else
      ui.setColor(colors.white, colors.black)
      term.setCursorPos(1, row)
      term.write(string.format("%-16s %-8s %-16s", "Player", "Status", "Position"))
      row = row + 1

      for _, name in ipairs(players) do
        if row >= h - 4 then break end
        local wl  = isWhitelisted(name)
        local pos = getPlayerPos(name)
        local posStr = pos and string.format("%.0f,%.0f,%.0f", pos.x or 0, pos.y or 0, pos.z or 0) or "?"
        local statusStr   = wl and "OK" or "!"
        local nameColor   = wl and colors.lime or (flashState and colors.red or colors.orange)

        ui.setColor(nameColor, colors.black)
        term.setCursorPos(1, row)
        term.write(string.format("%-16s %-8s %-16s",
          name:sub(1, 15), statusStr, posStr:sub(1, 15)):sub(1, w))
        row = row + 1
      end
    end
    ui.resetColor()

    -- Weather warning
    if envDet then
      local ok, weather = pcall(envDet.getWeather)
      if ok and weather == "thunder" then
        row = row + 1
        ui.setColor(colors.yellow, colors.black)
        term.setCursorPos(1, row)
        term.write("WARNING: Thunderstorm — increased mob danger!")
        ui.resetColor()
        row = row + 1
      end
    end

    row = row + 1
    ui.setColor(colors.lightGray, colors.black)
    term.setCursorPos(1, row)
    term.write("Radius: " .. cfg.alertRadius .. "m  Alerts: " .. alertCount)
    ui.resetColor()

    ui.drawFooter("[Q] Disarm & exit")
  end

  doScan()

  while armedRunning do
    local evt, p1 = os.pullEvent()
    if evt == "timer" and p1 == scanTimer then
      doScan()
      scanTimer = os.startTimer(cfg.scanInterval)
    elseif evt == "key" then
      if p1 == keys.q or p1 == keys.backspace then
        armedRunning = false
      end
    elseif evt == "terminate" then
      armedRunning = false
    end
  end

  -- Disarm: reset redstone
  if rsIntegr and cfg.redstoneAlerts then
    pcall(rsIntegr.setOutput, cfg.redstoneSide, false)
  end

  armed = false
  config.appendLog(LOG_FILE, "System DISARMED. Total alerts: " .. alertCount)
  ui.alert("System disarmed.\nTotal alerts this session: " .. alertCount, "info")
end

-- ─────────────────────────────────────────────
-- Whitelist manager
-- ─────────────────────────────────────────────
local function manageWhitelist()
  while true do
    local items = {}
    for _, name in ipairs(cfg.whitelist) do
      table.insert(items, { label = name, description = "Remove?" })
    end
    table.insert(items, { label = "+ Add Player" })
    table.insert(items, { label = "< Back" })

    if #cfg.whitelist == 0 then
      -- Add warning line at top
      ui.alert(
        "Whitelist is EMPTY!\n\n" ..
        "With an empty whitelist the system will\n" ..
        "alert on EVERY detected player.\n\n" ..
        "Add your name and your friends' names.",
        "warn"
      )
    end

    local idx = ui.drawMenu(items, "Whitelist Manager")
    if not idx or idx == #items then return end

    if idx == #items - 1 then
      -- Add player
      local name = ui.inputText("Player name to whitelist: ")
      if name and name ~= "" then
        -- Check for duplicate
        local exists = false
        for _, n in ipairs(cfg.whitelist) do
          if n:lower() == name:lower() then exists = true; break end
        end
        if exists then
          ui.alert(name .. " is already whitelisted.", "info")
        else
          table.insert(cfg.whitelist, name)
          config.save(CFG_FILE, cfg)
          ui.alert(name .. " added to whitelist.", "success")
        end
      end

    else
      -- Remove player
      local name = cfg.whitelist[idx]
      if ui.confirm("Remove " .. name .. " from whitelist?") then
        table.remove(cfg.whitelist, idx)
        config.save(CFG_FILE, cfg)
      end
    end
  end
end

-- ─────────────────────────────────────────────
-- Alert config
-- ─────────────────────────────────────────────
local function configureAlerts()
  local RADII = { 8, 16, 32, 64 }

  while true do
    local items = {
      { label = "Chat Alerts: " .. (cfg.chatAlerts and "ON" or "OFF"),
        description = chatBox and "chatBox found" or "no chatBox" },
      { label = "Redstone Alerts: " .. (cfg.redstoneAlerts and "ON" or "OFF"),
        description = rsIntegr and "integrator found" or "no integrator" },
      { label = "Redstone Side: " .. cfg.redstoneSide },
      { label = "Alert Radius: " .. cfg.alertRadius .. "m" },
      { label = "Log Alerts: " .. (cfg.logAlerts and "ON" or "OFF") },
      { label = "Scan Interval: " .. cfg.scanInterval .. "s" },
      { label = "< Back" },
    }

    local idx = ui.drawMenu(items, "Alert Config")
    if not idx or idx == 7 then return end

    if idx == 1 then
      cfg.chatAlerts = not cfg.chatAlerts
      config.save(CFG_FILE, cfg)
    elseif idx == 2 then
      cfg.redstoneAlerts = not cfg.redstoneAlerts
      config.save(CFG_FILE, cfg)
    elseif idx == 3 then
      local sides = { "north", "south", "east", "west", "top", "bottom", "< Cancel" }
      local sidx  = ui.drawMenu(sides, "Redstone output side")
      if sidx and sidx <= 6 then
        cfg.redstoneSide = sides[sidx]
        config.save(CFG_FILE, cfg)
      end
    elseif idx == 4 then
      local radItems = {}
      for _, r in ipairs(RADII) do table.insert(radItems, r .. "m") end
      table.insert(radItems, "< Cancel")
      local ridx = ui.drawMenu(radItems, "Alert radius")
      if ridx and ridx <= #RADII then
        cfg.alertRadius = RADII[ridx]
        config.save(CFG_FILE, cfg)
      end
    elseif idx == 5 then
      cfg.logAlerts = not cfg.logAlerts
      config.save(CFG_FILE, cfg)
    elseif idx == 6 then
      local raw = ui.inputText("Scan interval (seconds, min 1): ", tostring(cfg.scanInterval))
      local v   = tonumber(raw)
      if v and v >= 1 then
        cfg.scanInterval = v
        config.save(CFG_FILE, cfg)
      end
    end
  end
end

-- ─────────────────────────────────────────────
-- Security log
-- ─────────────────────────────────────────────
local function showLog()
  local lines = config.readLog(LOG_FILE, 60)
  if #lines == 0 then
    ui.alert("No security log entries yet.", "info")
    return
  end
  -- Newest first
  local reversed = {}
  for i = #lines, 1, -1 do
    table.insert(reversed, lines[i])
  end
  ui.pager(reversed, "Security Log")
end

-- ─────────────────────────────────────────────
-- Live scanner (all players, debug)
-- ─────────────────────────────────────────────
local function liveScanner()
  local scanRunning = true
  local scanTimer   = os.startTimer(2)

  local function doScan()
    local players = getPlayers()
    local w, h    = term.getSize()

    ui.clear()
    ui.drawHeader("Security", "Live Scanner")

    if #players == 0 then
      ui.setColor(colors.gray, colors.black)
      ui.writeCentered(4, "No players within " .. cfg.alertRadius .. "m")
      ui.resetColor()
    else
      local row = 3
      ui.setColor(colors.gray, colors.black)
      term.setCursorPos(1, row)
      term.write(string.format("%-16s %-8s %-18s", "Player", "WL?", "Position"))
      row = row + 1
      ui.resetColor()

      for _, name in ipairs(players) do
        if row >= h - 2 then break end
        local wl  = isWhitelisted(name)
        local pos = getPlayerPos(name)
        local posStr = pos
          and string.format("%.0f, %.0f, %.0f", pos.x or 0, pos.y or 0, pos.z or 0)
          or "unknown"

        ui.setColor(wl and colors.lime or colors.orange, colors.black)
        term.setCursorPos(1, row)
        term.write(string.format("%-16s %-8s %-18s",
          name:sub(1,15), wl and "YES" or "NO", posStr:sub(1,17)):sub(1, w))
        row = row + 1
        ui.resetColor()
      end
    end

    ui.drawFooter("[Q] Back  — auto-refreshes every 2s")
  end

  doScan()

  while scanRunning do
    local evt, p1 = os.pullEvent()
    if evt == "timer" and p1 == scanTimer then
      doScan()
      scanTimer = os.startTimer(2)
    elseif evt == "key" and (p1 == keys.q or p1 == keys.backspace) then
      scanRunning = false
    elseif evt == "terminate" then
      scanRunning = false
    end
  end
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  discoverPeripherals()
  cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  if not playerDet then
    ui.clear()
    ui.drawHeader("Security System", "Setup Required")
    local w = select(1, term.getSize())
    local msg = {
      "No Player Detector found!",
      "",
      "Craft a Player Detector from Advanced",
      "Peripherals and place it adjacent to",
      "this computer or on the wired network.",
      "",
      "The Player Detector detects players",
      "within a configurable radius.",
      "",
      "Press any key to continue...",
    }
    for i, line in ipairs(msg) do
      ui.setColor(i == 1 and colors.red or colors.white, colors.black)
      term.setCursorPos(2, i + 2)
      term.write(line:sub(1, w - 2))
    end
    ui.resetColor()
    os.pullEvent("key")
  end

  while running do
    local items = {
      { label = "Arm System",       description = armed and "ARMED" or "disarmed" },
      { label = "Whitelist",        description = #cfg.whitelist .. " players" },
      { label = "Alert Config",     description = "Radius: " .. cfg.alertRadius .. "m" },
      { label = "Security Log",     description = "View past events" },
      { label = "Live Scanner",     description = "See all players now" },
      { label = "< Back to Hub",    description = "" },
    }

    local idx = ui.drawMenu(items, "Security System")
    if not idx or idx == 6 then running = false; break end

    if idx == 1 then
      if not playerDet then
        ui.alert("Player Detector not found!\nCannot arm the system.", "error")
      else
        config.appendLog(LOG_FILE, "System ARMED. Whitelist: " .. #cfg.whitelist .. " players.")
        armed = true
        runArmed()
      end
    elseif idx == 2 then manageWhitelist()
    elseif idx == 3 then configureAlerts()
    elseif idx == 4 then showLog()
    elseif idx == 5 then liveScanner()
    end

    discoverPeripherals()
  end
end

main()
