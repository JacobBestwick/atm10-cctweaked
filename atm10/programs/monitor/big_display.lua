-- big_display.lua
-- ATM10 Big Monitor Display
-- Device: Computer / Advanced Computer
-- Required: Advanced Monitor (at least 3x2 or larger)
-- Optional: meBridge/rsBridge, energyDetector, environmentDetector,
--           playerDetector, chatBox (Advanced Peripherals)
--
-- Drives a large external monitor with multiple display modes:
--   Clock / Status / Power / Storage / Welcome / Auto-cycle
-- Supports touch input for mode switching on advanced monitors.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local ui     = require("ui")
local config = require("config")
local detect = require("detect")

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────
local CFG_FILE = "big_display.cfg"
local DEFAULTS = {
  monitorSide   = "auto",   -- "auto" or specific side/name
  textScale     = 1,        -- 0.5, 1, 1.5, 2, 3, 4, 5
  autoCycle     = true,
  cycleInterval = 15,       -- seconds per mode
  modes         = { "clock", "power", "storage", "welcome" },
  welcomeMsg    = "Welcome to ATM10!",
  welcomeSub    = "All The Mods 10",
  serverName    = "ATM10 Server",
  alertThresholds = {
    powerLow  = 15,   -- % below which to flash warning
    storageFull = 90, -- % above which to warn
  },
}

-- ─────────────────────────────────────────────
-- Find monitor
-- ─────────────────────────────────────────────
local function findMonitor(cfg)
  if cfg.monitorSide ~= "auto" then
    local m = peripheral.wrap(cfg.monitorSide)
    if m and peripheral.getType(cfg.monitorSide):find("monitor") then
      return m, cfg.monitorSide
    end
  end

  -- Auto-detect: prefer largest monitor
  local best, bestName, bestSize = nil, nil, 0
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name)
    if t and t:find("monitor") then
      local m = peripheral.wrap(name)
      if m then
        local w, h = m.getSize()
        local sz = (w or 0) * (h or 0)
        if sz > bestSize then
          best, bestName, bestSize = m, name, sz
        end
      end
    end
  end
  -- Also check direct sides
  local sides = { "top", "bottom", "left", "right", "front", "back" }
  for _, side in ipairs(sides) do
    local t = peripheral.getType(side)
    if t and t:find("monitor") then
      local m = peripheral.wrap(side)
      if m then
        local w, h = m.getSize()
        local sz = (w or 0) * (h or 0)
        if sz > bestSize then
          best, bestName, bestSize = m, side, sz
        end
      end
    end
  end
  return best, bestName
end

-- ─────────────────────────────────────────────
-- Peripheral helpers
-- ─────────────────────────────────────────────
local function wrapPeripheral(pType)
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == pType then
      return peripheral.wrap(name)
    end
  end
  local sides = { "top", "bottom", "left", "right", "front", "back" }
  for _, side in ipairs(sides) do
    if peripheral.getType(side) == pType then
      return peripheral.wrap(side)
    end
  end
  return nil
end

local function getPower(energyDet)
  if not energyDet then return nil end
  local ok, rate  = pcall(function() return energyDet.getTransferRate() end)
  local ok2, stored = pcall(function() return energyDet.getEnergy() end)
  local ok3, cap   = pcall(function() return energyDet.getMaxEnergy() end)
  local pct = 0
  if ok2 and ok3 and cap and cap > 0 then
    pct = math.floor((stored / cap) * 100)
  end
  return {
    pct  = pct,
    rate = ok and rate or 0,
    stored = ok2 and stored or 0,
    cap    = ok3 and cap or 0,
  }
end

local function getStorageInfo(bridge)
  if not bridge then return nil end
  local ok, items = pcall(function()
    if bridge.listItems then return bridge.listItems()
    elseif bridge.getItems then return bridge.getItems()
    else return {} end
  end)
  if not ok then return nil end
  local ok2, types = pcall(function()
    if bridge.getTotalItemTypes then return bridge.getTotalItemTypes() end
    return #(items or {})
  end)
  local ok3, bytes = pcall(function()
    if bridge.getUsedItemTypes then
      local used = bridge.getUsedItemTypes()
      local cap  = bridge.getMaxItemTypes and bridge.getMaxItemTypes() or 0
      return used, cap
    end
    return nil, nil
  end)
  return {
    itemTypes = ok2 and types or (ok and #items or 0),
    usedBytes = (ok3 and bytes) or nil,
    maxBytes  = select(2, pcall(function()
      if bridge.getMaxItemStorage then return bridge.getMaxItemStorage() end
      return nil
    end)),
  }
end

local function getEnvironment(envDet)
  if not envDet then return nil end
  local ok1, weather = pcall(function() return envDet.getWeather() end)
  local ok2, day     = pcall(function() return envDet.getDay() end)
  local ok3, time    = pcall(function() return envDet.getTime() end)
  local ok4, moon    = pcall(function() return envDet.getMoonPhase() end)
  return {
    weather = ok1 and weather or "unknown",
    day     = ok2 and day or 0,
    time    = ok3 and time or 0,
    moon    = ok4 and moon or "?",
  }
end

-- ─────────────────────────────────────────────
-- Drawing helpers (all write to mon redirect)
-- ─────────────────────────────────────────────
local function centerWrite(mon, y, text)
  local w = select(1, mon.getSize())
  local x = math.max(1, math.floor((w - #text) / 2) + 1)
  mon.setCursorPos(x, y)
  mon.write(text)
end

local function fillRow(mon, y, char, color)
  local w = select(1, mon.getSize())
  if color then mon.setBackgroundColor(color) end
  mon.setCursorPos(1, y)
  mon.write(string.rep(char or " ", w))
end

local function drawBar(mon, x, y, width, pct, fillCol, emptyCol)
  local filled = math.floor(width * pct / 100)
  mon.setCursorPos(x, y)
  if emptyCol then mon.setBackgroundColor(emptyCol) end
  mon.write(string.rep(" ", width))
  if filled > 0 then
    if fillCol then mon.setBackgroundColor(fillCol) end
    mon.setCursorPos(x, y)
    mon.write(string.rep(" ", filled))
  end
end

-- ─────────────────────────────────────────────
-- DISPLAY MODES
-- ─────────────────────────────────────────────

-- MODE: Clock / Status
local function drawClock(mon, cfg, env)
  local w, h = mon.getSize()
  local isAdv = mon.isColor and mon.isColor() or false

  mon.setBackgroundColor(isAdv and colors.black or colors.black)
  mon.clear()

  if isAdv then
    mon.setTextColor(colors.cyan)
  end

  -- Big time display
  local timeStr = textutils.formatTime(os.time(), false)
  centerWrite(mon, math.floor(h / 2) - 1, timeStr)

  if isAdv then mon.setTextColor(colors.yellow) end

  -- Date / day
  local dayStr = "Day " .. (env and env.day or os.day())
  centerWrite(mon, math.floor(h / 2), dayStr)

  -- Server name
  if isAdv then mon.setTextColor(colors.white) end
  centerWrite(mon, math.floor(h / 2) + 1, cfg.serverName or "")

  -- Weather indicator
  if env then
    if isAdv then
      if env.weather == "rain" or env.weather == "thunder" then
        mon.setTextColor(colors.lightBlue)
      else
        mon.setTextColor(colors.lime)
      end
    end
    local wx = env.weather or "clear"
    local wxLine = "Weather: " .. wx:sub(1,1):upper() .. wx:sub(2)
    centerWrite(mon, h - 1, wxLine)
  end

  if isAdv then mon.setTextColor(colors.white) end
end

-- MODE: Power
local function drawPower(mon, cfg, power)
  local w, h = mon.getSize()
  local isAdv = mon.isColor and mon.isColor() or false

  mon.setBackgroundColor(colors.black)
  mon.clear()

  if not power then
    if isAdv then mon.setTextColor(colors.gray) end
    centerWrite(mon, math.floor(h/2), "No Energy Detector")
    if isAdv then mon.setTextColor(colors.white) end
    return
  end

  local pct = power.pct or 0

  -- Title
  if isAdv then
    fillRow(mon, 1, " ", colors.blue)
    mon.setBackgroundColor(colors.blue)
    mon.setTextColor(colors.white)
  end
  centerWrite(mon, 1, " POWER STATUS ")

  if isAdv then
    mon.setBackgroundColor(colors.black)
    -- Pick bar color
    local barColor = colors.lime
    if pct < 10 then barColor = colors.red
    elseif pct < 25 then barColor = colors.orange
    elseif pct < 50 then barColor = colors.yellow end

    mon.setTextColor(barColor)
  end

  -- Big percentage
  local pctStr = pct .. "%"
  centerWrite(mon, 3, pctStr)

  -- Progress bar
  local barY = 5
  local barW = w - 4
  local barX = 3
  if isAdv then
    local barColor = pct < 10 and colors.red or (pct < 25 and colors.orange or (pct < 50 and colors.yellow or colors.lime))
    drawBar(mon, barX, barY, barW, pct, barColor, colors.gray)
  else
    -- Basic monitor: text bar
    local filled = math.floor(barW * pct / 100)
    mon.setCursorPos(barX, barY)
    mon.write("[" .. string.rep("=", filled) .. string.rep("-", barW - filled) .. "]")
  end

  -- Rate
  if isAdv then
    mon.setBackgroundColor(colors.black)
    local rate = power.rate or 0
    local rateSign = rate >= 0 and "+" or ""
    mon.setTextColor(rate >= 0 and colors.lime or colors.red)
  end

  local rateStr = ui.formatEnergy(math.abs(power.rate or 0)) .. "/t"
  if (power.rate or 0) < 0 then rateStr = "-" .. rateStr else rateStr = "+" .. rateStr end
  centerWrite(mon, barY + 2, rateStr)

  -- Stored
  if isAdv then mon.setTextColor(colors.gray) end
  local storedStr = ui.formatEnergy(power.stored or 0) .. " / " .. ui.formatEnergy(power.cap or 0)
  centerWrite(mon, barY + 3, storedStr)

  -- Warning
  if pct < cfg.alertThresholds.powerLow then
    if isAdv then
      mon.setTextColor(colors.red)
      -- Flash: alternate every second
      if math.floor(os.time() * 2) % 2 == 0 then
        centerWrite(mon, h - 1, "!! POWER LOW !!")
      end
    else
      mon.setCursorPos(1, h)
      mon.write("!! LOW !!")
    end
  end

  if isAdv then mon.setTextColor(colors.white) end
end

-- MODE: Storage
local function drawStorage(mon, cfg, storage)
  local w, h = mon.getSize()
  local isAdv = mon.isColor and mon.isColor() or false

  mon.setBackgroundColor(colors.black)
  mon.clear()

  if not storage then
    if isAdv then mon.setTextColor(colors.gray) end
    centerWrite(mon, math.floor(h/2), "No ME/RS Bridge")
    if isAdv then mon.setTextColor(colors.white) end
    return
  end

  -- Title
  if isAdv then
    fillRow(mon, 1, " ", colors.purple)
    mon.setBackgroundColor(colors.purple)
    mon.setTextColor(colors.white)
  end
  centerWrite(mon, 1, " STORAGE STATUS ")

  if isAdv then
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.cyan)
  end

  -- Item types
  local typesStr = ui.formatNumber(storage.itemTypes or 0) .. " item types"
  centerWrite(mon, 3, typesStr)

  -- Byte usage if available
  if storage.usedBytes and storage.maxBytes and storage.maxBytes > 0 then
    local pct = math.floor(storage.usedBytes / storage.maxBytes * 100)
    if isAdv then
      local barCol = pct > 90 and colors.red or (pct > 75 and colors.yellow or colors.lime)
      drawBar(mon, 3, 5, w - 4, pct, barCol, colors.gray)
      mon.setBackgroundColor(colors.black)
      mon.setTextColor(pct > 90 and colors.red or colors.white)
    else
      local barW = w - 4
      local filled = math.floor(barW * pct / 100)
      mon.setCursorPos(3, 5)
      mon.write("[" .. string.rep("=", filled) .. string.rep("-", barW - filled) .. "]")
    end
    centerWrite(mon, 6, pct .. "% used")
    local byteLine = ui.formatNumber(storage.usedBytes) .. " / " .. ui.formatNumber(storage.maxBytes) .. " bytes"
    if isAdv then mon.setTextColor(colors.gray) end
    centerWrite(mon, 7, byteLine)
  end

  if isAdv then mon.setTextColor(colors.white) end
end

-- MODE: Welcome / Info board
local function drawWelcome(mon, cfg, env, playerCount)
  local w, h = mon.getSize()
  local isAdv = mon.isColor and mon.isColor() or false

  mon.setBackgroundColor(colors.black)
  mon.clear()

  -- Decorative top border
  if isAdv then
    fillRow(mon, 1, " ", colors.green)
    mon.setBackgroundColor(colors.green)
    mon.setTextColor(colors.white)
  end
  centerWrite(mon, 1, " " .. (cfg.serverName or "ATM10") .. " ")

  if isAdv then
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.yellow)
  end
  centerWrite(mon, 3, cfg.welcomeMsg or "Welcome!")

  if isAdv then mon.setTextColor(colors.white) end
  centerWrite(mon, 4, cfg.welcomeSub or "")

  -- Divider
  if isAdv then mon.setTextColor(colors.gray) end
  centerWrite(mon, 6, string.rep("-", math.min(w, 20)))

  -- Time
  local timeStr = textutils.formatTime(os.time(), false)
  if isAdv then mon.setTextColor(colors.cyan) end
  centerWrite(mon, 7, timeStr .. "  Day " .. (env and env.day or os.day()))

  -- Weather
  if env then
    if isAdv then
      if env.weather == "thunder" then mon.setTextColor(colors.yellow)
      elseif env.weather == "rain"  then mon.setTextColor(colors.lightBlue)
      else mon.setTextColor(colors.lime) end
    end
    local wx = env.weather or "clear"
    centerWrite(mon, 8, "Weather: " .. wx:sub(1,1):upper() .. wx:sub(2))
  end

  -- Players online
  if playerCount then
    if isAdv then mon.setTextColor(colors.lime) end
    centerWrite(mon, 10, "Players Online: " .. playerCount)
  end

  -- Bottom border
  if isAdv then
    fillRow(mon, h, " ", colors.green)
    mon.setBackgroundColor(colors.green)
    mon.setTextColor(colors.white)
    centerWrite(mon, h, " CC:Tweaked ATM10 Suite ")
  end

  if isAdv then
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
  end
end

-- ─────────────────────────────────────────────
-- Touch input handler
-- ─────────────────────────────────────────────
local function handleTouch(x, y, w, h, modes, currentMode)
  -- Touch left/right halves to go prev/next mode
  if x < w / 2 then
    -- Previous mode
    local idx = 1
    for i, m in ipairs(modes) do if m == currentMode then idx = i; break end end
    idx = idx - 1
    if idx < 1 then idx = #modes end
    return modes[idx]
  else
    -- Next mode
    local idx = 1
    for i, m in ipairs(modes) do if m == currentMode then idx = i; break end end
    idx = idx + 1
    if idx > #modes then idx = 1 end
    return modes[idx]
  end
end

-- ─────────────────────────────────────────────
-- Main display loop
-- ─────────────────────────────────────────────
local function runDisplay(mon, cfg)
  -- Wrap peripherals
  local energyDet  = wrapPeripheral("energyDetector")
  local meBridge   = wrapPeripheral("meBridge") or wrapPeripheral("rsBridge")
  local envDet     = wrapPeripheral("environmentDetector")
  local playerDet  = wrapPeripheral("playerDetector")

  -- Set monitor scale
  if mon.setTextScale then
    pcall(function() mon.setTextScale(cfg.textScale or 1) end)
  end

  local modes       = cfg.modes or { "clock", "power", "storage", "welcome" }
  local modeIdx     = 1
  local running     = true
  local cycleTimer  = cfg.autoCycle and os.startTimer(cfg.cycleInterval) or nil
  local refreshTimer = os.startTimer(1)

  -- Data cache
  local lastPower   = nil
  local lastStorage = nil
  local lastEnv     = nil
  local lastPlayers = 0

  local function fetchData()
    lastPower   = getPower(energyDet)
    lastStorage = getStorageInfo(meBridge)
    lastEnv     = getEnvironment(envDet)
    if playerDet then
      local ok, p = pcall(function()
        return playerDet.getOnlinePlayers and playerDet.getOnlinePlayers()
            or playerDet.getPlayersInRange and playerDet.getPlayersInRange(512)
            or {}
      end)
      lastPlayers = ok and type(p) == "table" and #p or 0
    end
  end

  local function drawMode()
    local mode = modes[modeIdx]
    -- Redirect to monitor
    local oldTerm = term.redirect(mon)
    pcall(function()
      if mode == "clock" then
        drawClock(mon, cfg, lastEnv)
      elseif mode == "power" then
        drawPower(mon, cfg, lastPower)
      elseif mode == "storage" then
        drawStorage(mon, cfg, lastStorage)
      elseif mode == "welcome" then
        drawWelcome(mon, cfg, lastEnv, lastPlayers)
      end
    end)
    term.redirect(oldTerm)
  end

  -- Initial fetch and draw
  fetchData()
  drawMode()

  -- Draw status on host terminal
  term.clear()
  term.setCursorPos(1, 1)
  ui.drawHeader("Big Display", "Running")
  term.setCursorPos(1, 3)
  print("Monitor: " .. (cfg.monitorSide or "auto"))
  print("Mode: " .. modes[modeIdx])
  print("Auto-cycle: " .. (cfg.autoCycle and (cfg.cycleInterval .. "s") or "off"))
  print("")
  print("Keys: [Q] quit  [N] next mode")
  print("      [P] prev  [C] toggle cycle")
  print("")
  print("Monitor supports touch input.")

  while running do
    local evt, p1, p2, p3 = os.pullEvent()

    if evt == "timer" then
      if p1 == refreshTimer then
        fetchData()
        drawMode()
        refreshTimer = os.startTimer(1)

      elseif cycleTimer and p1 == cycleTimer then
        modeIdx = modeIdx % #modes + 1
        drawMode()
        -- Update host terminal mode display
        term.setCursorPos(1, 4)
        term.write("Mode: " .. modes[modeIdx] .. "          ")
        cycleTimer = os.startTimer(cfg.cycleInterval)
      end

    elseif evt == "key" then
      if p1 == keys.q then
        running = false
      elseif p1 == keys.n then
        modeIdx = modeIdx % #modes + 1
        drawMode()
        term.setCursorPos(1, 4)
        term.write("Mode: " .. modes[modeIdx] .. "          ")
        if cycleTimer then cycleTimer = os.startTimer(cfg.cycleInterval) end
      elseif p1 == keys.p then
        modeIdx = modeIdx - 1
        if modeIdx < 1 then modeIdx = #modes end
        drawMode()
        term.setCursorPos(1, 4)
        term.write("Mode: " .. modes[modeIdx] .. "          ")
        if cycleTimer then cycleTimer = os.startTimer(cfg.cycleInterval) end
      elseif p1 == keys.c then
        cfg.autoCycle = not cfg.autoCycle
        if cfg.autoCycle then
          cycleTimer = os.startTimer(cfg.cycleInterval)
        else
          cycleTimer = nil
        end
        config.save(CFG_FILE, cfg)
        term.setCursorPos(1, 5)
        term.write("Auto-cycle: " .. (cfg.autoCycle and (cfg.cycleInterval .. "s") or "off ") .. "    ")
      end

    elseif evt == "monitor_touch" then
      -- p1 = monitor side, p2 = x, p3 = y
      local w, h = mon.getSize()
      local nextMode = handleTouch(p2, p3, w, h, modes, modes[modeIdx])
      for i, m in ipairs(modes) do
        if m == nextMode then modeIdx = i; break end
      end
      drawMode()
      if cycleTimer then cycleTimer = os.startTimer(cfg.cycleInterval) end

    elseif evt == "terminate" then
      running = false
    end
  end

  -- Clear monitor on exit
  local oldTerm = term.redirect(mon)
  pcall(function()
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1, 1)
  end)
  term.redirect(oldTerm)
end

-- ─────────────────────────────────────────────
-- Settings (terminal-side)
-- ─────────────────────────────────────────────
local function showSettings(cfg)
  while true do
    local items = {
      { label = "Text Scale: " .. cfg.textScale,           description = "0.5-5" },
      { label = "Auto-cycle: " .. (cfg.autoCycle and "on" or "off") },
      { label = "Cycle interval: " .. cfg.cycleInterval .. "s" },
      { label = "Monitor: " .. cfg.monitorSide },
      { label = "Welcome msg: " .. cfg.welcomeMsg:sub(1, 16) },
      { label = "Server name: " .. cfg.serverName:sub(1, 16) },
      { label = "Power warn at: " .. cfg.alertThresholds.powerLow .. "%" },
      { label = "< Back" },
    }
    local idx = ui.drawMenu(items, "Big Display Settings")
    if not idx or idx == 8 then return end

    if idx == 1 then
      local raw = ui.inputText("Text scale (0.5/1/1.5/2/3/4/5): ")
      local v = tonumber(raw)
      if v then cfg.textScale = v; config.save(CFG_FILE, cfg) end
    elseif idx == 2 then
      cfg.autoCycle = not cfg.autoCycle; config.save(CFG_FILE, cfg)
    elseif idx == 3 then
      local raw = ui.inputText("Cycle interval (s): ")
      local v = tonumber(raw)
      if v and v >= 1 then cfg.cycleInterval = v; config.save(CFG_FILE, cfg) end
    elseif idx == 4 then
      local raw = ui.inputText("Monitor side/name ('auto' for auto): ")
      if raw and raw ~= "" then cfg.monitorSide = raw; config.save(CFG_FILE, cfg) end
    elseif idx == 5 then
      local raw = ui.inputText("Welcome message: ", cfg.welcomeMsg)
      if raw and raw ~= "" then cfg.welcomeMsg = raw; config.save(CFG_FILE, cfg) end
    elseif idx == 6 then
      local raw = ui.inputText("Server name: ", cfg.serverName)
      if raw and raw ~= "" then cfg.serverName = raw; config.save(CFG_FILE, cfg) end
    elseif idx == 7 then
      local raw = ui.inputText("Power low warning % (0-100): ")
      local v = tonumber(raw)
      if v then cfg.alertThresholds.powerLow = v; config.save(CFG_FILE, cfg) end
    end
  end
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  local cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  local mon, monName = findMonitor(cfg)
  if not mon then
    ui.alert(
      "No monitor found!\n\n" ..
      "Attach an Advanced Monitor\n" ..
      "to this computer.\n\n" ..
      "Tip: Use Settings to configure\n" ..
      "the monitor side manually.",
      "error"
    )

    -- Offer to go to settings anyway
    if ui.confirm("Open settings anyway?") then
      showSettings(cfg)
    end
    return
  end

  cfg.monitorSide = monName

  local running = true
  while running do
    local w, h = mon.getSize()
    local items = {
      { label = "Start Display",  description = monName .. " (" .. w .. "x" .. h .. ")" },
      { label = "Settings",       description = "scale, modes, messages" },
      { label = "< Back to Hub",  description = "" },
    }

    local idx = ui.drawMenu(items, "Big Display")
    if not idx or idx == 3 then running = false; break end

    if idx == 1 then
      runDisplay(mon, cfg)
      -- Re-find monitor after returning (in case it changed)
      mon, monName = findMonitor(cfg)
      if not mon then
        ui.alert("Monitor disconnected!", "error")
        return
      end
    elseif idx == 2 then
      showSettings(cfg)
    end
  end
end

main()
