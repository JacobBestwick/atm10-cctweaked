-- player_scanner.lua
-- ATM10 Player Scanner
-- Device: Advanced Pocket Computer ONLY
-- Required: playerDetector (Advanced Peripherals) on the pocket computer
--           OR a networked playerDetector accessible via wireless modem
-- Optional: Wireless modem for remote detector access
--
-- Scans for nearby players, shows their distance, direction,
-- dimension, and online status. Useful on large servers.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local ui     = require("ui")
local config = require("config")
local detect = require("detect")

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────
local CFG_FILE = "player_scanner.cfg"
local DEFAULTS = {
  scanRadius  = 64,
  refreshRate = 3,
  showCoords  = true,
  showDim     = true,
  warnRadius  = 16,  -- highlight if within this range
}

-- ─────────────────────────────────────────────
-- Peripheral discovery
-- ─────────────────────────────────────────────
local function findDetector()
  -- Check local sides first
  local sides = { "top", "bottom", "left", "right", "front", "back" }
  for _, side in ipairs(sides) do
    if peripheral.getType(side) == "playerDetector" then
      return peripheral.wrap(side), side
    end
  end

  -- Check wired/wireless network
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "playerDetector" then
      return peripheral.wrap(name), name
    end
  end

  return nil, nil
end

-- ─────────────────────────────────────────────
-- Direction helpers
-- ─────────────────────────────────────────────
local function calcBearing(dx, dz)
  local angle = math.atan2(dx, -dz) * 180 / math.pi
  if angle < 0 then angle = angle + 360 end
  local dirs = { "N", "NE", "E", "SE", "S", "SW", "W", "NW", "N" }
  local idx  = math.floor((angle + 22.5) / 45) + 1
  return dirs[idx] or "?"
end

local function dist3d(x1, y1, z1, x2, y2, z2)
  local dx = (x2 or 0) - (x1 or 0)
  local dy = (y2 or 0) - (y1 or 0)
  local dz = (z2 or 0) - (z1 or 0)
  return math.sqrt(dx*dx + dy*dy + dz*dz), dx, dy, dz
end

-- ─────────────────────────────────────────────
-- Scan and display
-- ─────────────────────────────────────────────
local function scanPlayers(det, cfg)
  local scanRunning = true
  local timerId     = os.startTimer(cfg.refreshRate)

  -- Try to get this pocket's own ID
  local myName = os.getComputerLabel() or ("PC#" .. os.getComputerID())

  local function draw()
    local w, h = term.getSize()
    ui.clear()
    ui.drawHeader("Player Scanner", "r=" .. cfg.scanRadius .. "m")

    -- Get players in range
    local players = {}
    local ok, result = pcall(function()
      return det.getPlayersInRange(cfg.scanRadius)
    end)

    if ok and type(result) == "table" then
      players = result
    elseif not ok then
      ui.setColor(colors.red, colors.black)
      ui.writeCentered(4, "Detector error!")
      ui.setColor(colors.gray, colors.black)
      ui.writeCentered(5, tostring(result):sub(1, w - 2))
      ui.resetColor()
      ui.drawFooter("[Q] Back")
      return
    end

    if #players == 0 then
      ui.setColor(colors.gray, colors.black)
      ui.writeCentered(4, "No players in range")
      ui.writeCentered(5, "(radius: " .. cfg.scanRadius .. " blocks)")
      ui.resetColor()
      ui.drawFooter("[Q] Back  [R] Refresh")
      return
    end

    -- Sort by distance if positions available
    table.sort(players, function(a, b)
      local da = a.distance or math.huge
      local db = b.distance or math.huge
      return da < db
    end)

    local row = 3
    local isAdv = term.isColor()

    for _, p in ipairs(players) do
      if row >= h - 1 then break end

      local name = p.player or p.name or "Unknown"
      local d    = p.distance or -1

      -- Color based on proximity
      if isAdv then
        if d >= 0 and d <= cfg.warnRadius then
          ui.setColor(colors.red, colors.black)
        elseif d >= 0 and d <= cfg.scanRadius / 2 then
          ui.setColor(colors.yellow, colors.black)
        else
          ui.setColor(colors.white, colors.black)
        end
      end

      term.setCursorPos(2, row)
      local distStr = d >= 0 and string.format("%.0fm", d) or "?m"
      local line    = name:sub(1, w - 8) .. string.rep(" ", math.max(1, w - 7 - #name)) .. distStr
      term.write(line:sub(1, w - 1))
      row = row + 1

      -- Second line: bearing + coords
      if cfg.showCoords and p.x then
        local bear = ""
        if p.x and p.z then
          -- We don't have self position easily — show absolute coords
          bear = string.format("(%d,%d,%d)", math.floor(p.x), math.floor(p.y or 0), math.floor(p.z))
        end
        if bear ~= "" and row < h - 1 then
          ui.setColor(colors.gray, colors.black)
          term.setCursorPos(4, row)
          term.write(bear:sub(1, w - 4))
          row = row + 1
        end
      elseif p.dim and cfg.showDim and row < h - 1 then
        ui.setColor(colors.gray, colors.black)
        term.setCursorPos(4, row)
        local dimShort = tostring(p.dim):gsub("minecraft:", ""):sub(1, w - 4)
        term.write(dimShort)
        row = row + 1
      end

      ui.resetColor()
    end

    -- Count summary
    if row < h - 1 then
      ui.setColor(colors.gray, colors.black)
      term.setCursorPos(1, h - 1)
      term.write(("Total: " .. #players .. " player(s)"):sub(1, w))
      ui.resetColor()
    end

    ui.drawFooter("[Q] Back  [R] Scan  [S] Set")
  end

  draw()

  while scanRunning do
    local evt, p1 = os.pullEvent()

    if evt == "timer" and p1 == timerId then
      draw()
      timerId = os.startTimer(cfg.refreshRate)

    elseif evt == "key" then
      if p1 == keys.q or p1 == keys.backspace then
        scanRunning = false
      elseif p1 == keys.r then
        draw()
        timerId = os.startTimer(cfg.refreshRate)
      elseif p1 == keys.s then
        -- Quick settings
        local raw = ui.inputText("Scan radius (current " .. cfg.scanRadius .. "): ")
        if tonumber(raw) then
          cfg.scanRadius = math.min(tonumber(raw), 512)
          config.save(CFG_FILE, cfg)
        end
        draw()
      end

    elseif evt == "terminate" then
      scanRunning = false
    end
  end
end

-- ─────────────────────────────────────────────
-- Player detail view
-- ─────────────────────────────────────────────
local function playerDetail(det, playerName, cfg)
  local ok, data = pcall(function()
    return det.getPlayer(playerName)
  end)

  if not ok or not data then
    -- Try getPlayerPos
    ok, data = pcall(function()
      return det.getPlayerPos(playerName)
    end)
  end

  local lines = {
    "Player: " .. playerName,
    string.rep("-", 26),
    "",
  }

  if ok and type(data) == "table" then
    if data.x then
      table.insert(lines, string.format("X: %.1f", data.x or 0))
      table.insert(lines, string.format("Y: %.1f", data.y or 0))
      table.insert(lines, string.format("Z: %.1f", data.z or 0))
    end
    if data.dimension then
      table.insert(lines, "Dim: " .. tostring(data.dimension))
    end
    if data.health then
      table.insert(lines, string.format("HP: %.1f/%.1f", data.health, data.maxHealth or 20))
    end
    if data.armor then
      table.insert(lines, "Armor: " .. tostring(data.armor))
    end
    if data.gamemode then
      table.insert(lines, "Mode: " .. tostring(data.gamemode))
    end
  else
    table.insert(lines, "No detailed data available.")
    table.insert(lines, "(playerDetector may need")
    table.insert(lines, " OP or config permission)")
  end

  table.insert(lines, "")
  table.insert(lines, "Press Q to return.")
  ui.pager(lines, playerName)
end

-- ─────────────────────────────────────────────
-- Player list view (browse + pick)
-- ─────────────────────────────────────────────
local function listPlayers(det, cfg)
  local ok, players = pcall(function()
    return det.getPlayersInRange(cfg.scanRadius)
  end)

  if not ok or type(players) ~= "table" then
    -- Try getOnlinePlayers
    ok, players = pcall(function()
      return det.getOnlinePlayers()
    end)
  end

  if not ok or type(players) ~= "table" or #players == 0 then
    ui.alert("No players found in range\nor detector API unavailable.", "warn")
    return
  end

  while true do
    local items = {}
    for _, p in ipairs(players) do
      local name = type(p) == "string" and p or (p.player or p.name or "Unknown")
      local dist = type(p) == "table" and p.distance
      local desc = dist and string.format("%.0fm", dist) or ""
      table.insert(items, { label = name, description = desc })
    end
    table.insert(items, { label = "< Back" })

    local idx = ui.drawMenu(items, "Players (" .. #players .. ")")
    if not idx or idx > #players then return end

    local p    = players[idx]
    local name = type(p) == "string" and p or (p.player or p.name or "Unknown")
    playerDetail(det, name, cfg)
  end
end

-- ─────────────────────────────────────────────
-- Settings
-- ─────────────────────────────────────────────
local function showSettings(cfg)
  while true do
    local items = {
      { label = "Scan Radius: " .. cfg.scanRadius .. "m",   description = "max 512" },
      { label = "Refresh: " .. cfg.refreshRate .. "s",       description = "scan interval" },
      { label = "Warn Radius: " .. cfg.warnRadius .. "m",    description = "highlight close" },
      { label = "Show Coords: " .. (cfg.showCoords and "yes" or "no") },
      { label = "Show Dimension: " .. (cfg.showDim and "yes" or "no") },
      { label = "< Back" },
    }
    local idx = ui.drawMenu(items, "Scanner Settings")
    if not idx or idx == 6 then return end

    if idx == 1 then
      local raw = ui.inputText("Scan radius (1-512): ", tostring(cfg.scanRadius))
      local v = tonumber(raw)
      if v and v >= 1 then cfg.scanRadius = math.min(v, 512); config.save(CFG_FILE, cfg) end
    elseif idx == 2 then
      local raw = ui.inputText("Refresh interval (s): ", tostring(cfg.refreshRate))
      local v = tonumber(raw)
      if v and v >= 1 then cfg.refreshRate = v; config.save(CFG_FILE, cfg) end
    elseif idx == 3 then
      local raw = ui.inputText("Warn radius: ", tostring(cfg.warnRadius))
      local v = tonumber(raw)
      if v and v >= 1 then cfg.warnRadius = v; config.save(CFG_FILE, cfg) end
    elseif idx == 4 then
      cfg.showCoords = not cfg.showCoords; config.save(CFG_FILE, cfg)
    elseif idx == 5 then
      cfg.showDim = not cfg.showDim; config.save(CFG_FILE, cfg)
    end
  end
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  -- Check for advanced pocket (color support for best experience)
  if not term.isColor() then
    ui.alert(
      "Advanced Pocket recommended!\n\n" ..
      "Basic Pocket works but colors\n" ..
      "improve readability. Continuing...",
      "warn"
    )
  end

  -- Find playerDetector
  local det, detName = findDetector()

  if not det then
    ui.alert(
      "No playerDetector found!\n\n" ..
      "This program requires the\n" ..
      "Advanced Peripherals mod with\n" ..
      "a playerDetector peripheral.\n\n" ..
      "Attach one to your pocket\n" ..
      "computer or connect via modem.",
      "error"
    )
    return
  end

  local cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  local running = true
  while running do
    local items = {
      { label = "Live Scanner",   description = "auto-refresh" },
      { label = "Player List",    description = "browse all in range" },
      { label = "Settings",       description = "radius, refresh" },
      { label = "< Back to Hub",  description = "" },
    }

    -- Show detector info in subtitle
    local ok, count = pcall(function()
      local p = det.getPlayersInRange(cfg.scanRadius)
      return #p
    end)
    local subtitle = detName .. " | " .. (ok and count .. " nearby" or "error")

    local idx = ui.drawMenu(items, "Player Scanner")
    if not idx or idx == 4 then running = false; break end

    if idx == 1 then
      scanPlayers(det, cfg)
    elseif idx == 2 then
      listPlayers(det, cfg)
    elseif idx == 3 then
      showSettings(cfg)
    end
  end
end

main()
