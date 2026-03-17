-- base_monitor.lua
-- ATM10 Base Status Dashboard
-- Device: Computer / Advanced Computer
-- Required: None (runs in terminal)
-- Optional: monitor, energyDetector, meBridge/rsBridge, environmentDetector, playerDetector

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local detect = require("detect")
local ui     = require("ui")
local config = require("config")

-- ─────────────────────────────────────────
-- Constants
-- ─────────────────────────────────────────
local CFG_FILE    = "base_monitor.cfg"
local LOG_FILE    = "base_monitor_log.txt"
local ALL_PANELS  = { "power", "storage", "environment", "players", "clock", "log" }

local DEFAULTS = {
  refreshRate  = 5,
  panels       = { "power", "storage", "environment", "clock" },
  powerLow     = 20,
  storageFull  = 90,
}

-- ─────────────────────────────────────────
-- State
-- ─────────────────────────────────────────
local cfg           = {}
local timerId       = nil
local flashState    = false   -- for blinking effects
local running       = true

-- Peripheral handles (populated on each refresh)
local energyDet     = nil
local storageBridge = nil
local envDet        = nil
local playerDet     = nil

-- ─────────────────────────────────────────
-- Peripheral discovery
-- ─────────────────────────────────────────
local function discoverPeripherals()
  energyDet, _     = detect.findPeripheral("energyDetector")
  storageBridge, _  = detect.findPeripheral("meBridge")
  if not storageBridge then
    storageBridge, _ = detect.findPeripheral("rsBridge")
  end
  envDet, _        = detect.findPeripheral("environmentDetector")
  playerDet, _     = detect.findPeripheral("playerDetector")
end

-- ─────────────────────────────────────────
-- Monitor helpers
-- ─────────────────────────────────────────
local function findBestMonitor()
  local best     = nil
  local bestArea = 0
  local ok, names = pcall(peripheral.getNames)
  if not ok then return nil end
  for _, name in ipairs(names) do
    local ok2, ptype = pcall(peripheral.getType, name)
    if ok2 and ptype == "monitor" then
      local mon = peripheral.wrap(name)
      if mon then
        local ok3, w, h = pcall(mon.getSize)
        if ok3 then
          local area = w * h
          if area > bestArea then
            bestArea = area
            best     = mon
          end
        end
      end
    end
  end
  return best
end

-- ─────────────────────────────────────────
-- In-game time formatting helpers
-- ─────────────────────────────────────────
local function formatGameTime(ticks)
  -- Minecraft ticks: 0 = 6:00 AM, 6000 = 12:00, 12000 = 18:00, 18000 = midnight
  local adjusted = (ticks + 6000) % 24000
  local hours    = math.floor(adjusted / 1000)
  local mins     = math.floor((adjusted % 1000) / 1000 * 60)
  local ampm     = hours >= 12 and "PM" or "AM"
  local h12      = hours % 12
  if h12 == 0 then h12 = 12 end
  return string.format("%d:%02d %s", h12, mins, ampm)
end

local MOON_PHASES = {
  [0] = "Full Moon",  [1] = "Waning Gibbous", [2] = "Last Quarter",
  [3] = "Waning Crescent", [4] = "New Moon",  [5] = "Waxing Crescent",
  [6] = "First Quarter",   [7] = "Waxing Gibbous",
}

-- ─────────────────────────────────────────
-- Panel data collectors
-- ─────────────────────────────────────────
local function getPowerData()
  if not energyDet then
    return nil
  end
  local ok1, rate   = pcall(function() return energyDet.getTransferRate() end)
  local ok2, usage  = pcall(function() return energyDet.getEnergyUsage()  end)
  return {
    rate  = ok1 and tonumber(rate)  or 0,
    usage = ok2 and tonumber(usage) or 0,
  }
end

local function getStorageData()
  if not storageBridge then
    return nil
  end
  local ok1, items  = pcall(function() return storageBridge.listItems() end)
  local totalItems  = 0
  local itemCount   = 0
  if ok1 and type(items) == "table" then
    itemCount = #items
    for _, item in ipairs(items) do
      totalItems = totalItems + (tonumber(item.count) or 0)
    end
  end
  -- ME/RS bridges don't expose used/total slots directly; approximate
  return {
    itemTypes  = itemCount,
    totalItems = totalItems,
  }
end

local function getEnvData()
  if not envDet then return nil end
  local ok1, time    = pcall(function() return envDet.getTime()      end)
  local ok2, day     = pcall(function() return envDet.getDayCount()  end)
  local ok3, weather = pcall(function() return envDet.getWeather()   end)
  local ok4, moon    = pcall(function() return envDet.getMoonPhase() end)
  local ok5, biome   = pcall(function() return envDet.getBiome()     end)
  local ok6, isDay   = pcall(function() return envDet.isDay()        end)
  return {
    time    = ok1 and tonumber(time)   or 6000,
    day     = ok2 and tonumber(day)    or 0,
    weather = ok3 and tostring(weather) or "clear",
    moon    = ok4 and tonumber(moon)   or 0,
    biome   = ok5 and tostring(biome)  or "unknown",
    isDay   = ok6 and isDay            or true,
  }
end

local function getPlayersData()
  if not playerDet then return nil end
  local ok, players = pcall(function()
    return playerDet.getPlayersInRange(64)
  end)
  if not ok or type(players) ~= "table" then return { players = {} } end
  return { players = players }
end

-- ─────────────────────────────────────────
-- Panel renderers
-- Each receives: target (term-like), x, y, w, h, data
-- ─────────────────────────────────────────
local function renderBorder(t, x, y, w, h, title, borderColor)
  if term.isColor() then
    t.setBackgroundColor(colors.black)
    t.setTextColor(borderColor or colors.gray)
  end
  -- Top border
  t.setCursorPos(x, y)
  t.write("+" .. string.rep("-", w - 2) .. "+")
  -- Bottom border
  t.setCursorPos(x, y + h - 1)
  t.write("+" .. string.rep("-", w - 2) .. "+")
  -- Side borders
  for row = y + 1, y + h - 2 do
    t.setCursorPos(x, row)
    t.write("|")
    t.setCursorPos(x + w - 1, row)
    t.write("|")
  end
  -- Title in top border
  if title then
    local titleStr = " " .. title:sub(1, w - 4) .. " "
    t.setCursorPos(x + 2, y)
    if term.isColor() then
      t.setTextColor(colors.yellow)
    end
    t.write(titleStr)
  end
  if term.isColor() then
    t.setTextColor(colors.white)
    t.setBackgroundColor(colors.black)
  end
end

local function writeAt(t, x, y, text, fg, bg)
  if term.isColor() then
    if bg then t.setBackgroundColor(bg) end
    if fg then t.setTextColor(fg) end
  end
  t.setCursorPos(x, y)
  t.write(text)
  if term.isColor() then
    t.setTextColor(colors.white)
    t.setBackgroundColor(colors.black)
  end
end

-- Draw a mini progress bar inline
local function miniBar(t, x, y, w, pct, fillColor, emptyColor)
  local filled = math.max(0, math.floor(w * pct / 100))
  local empty  = w - filled
  if term.isColor() then
    t.setBackgroundColor(fillColor or colors.lime)
    t.setTextColor(fillColor or colors.lime)
  end
  t.setCursorPos(x, y)
  t.write(string.rep(" ", filled))
  if term.isColor() then
    t.setBackgroundColor(emptyColor or colors.gray)
    t.setTextColor(emptyColor or colors.gray)
  end
  t.write(string.rep(" ", empty))
  if term.isColor() then
    t.setTextColor(colors.white)
    t.setBackgroundColor(colors.black)
  end
end

-- Power panel
local function renderPower(t, x, y, w, h, data, cfg)
  renderBorder(t, x, y, w, h, "POWER")
  local innerX = x + 1
  local innerW = w - 2

  if not data then
    writeAt(t, innerX, y + 1, ("No energy detector"):sub(1, innerW),
      term.isColor() and colors.gray or nil)
    writeAt(t, innerX, y + 2, ("Attach energyDetector"):sub(1, innerW),
      term.isColor() and colors.gray or nil)
    return
  end

  local rate  = data.rate  or 0
  local usage = data.usage or 0

  -- Transfer rate row
  local rateStr  = "Rate: " .. ui.formatEnergy(math.abs(rate)) .. "/t"
  local direction = rate >= 0 and " (+)" or " (-)"
  local fc = term.isColor() and (rate >= 0 and colors.lime or colors.red) or nil
  writeAt(t, innerX, y + 1, (rateStr .. direction):sub(1, innerW), fc)

  -- Usage row
  local usageStr = "Usage: " .. ui.formatEnergy(usage) .. "/t"
  local uc = term.isColor() and colors.orange or nil
  writeAt(t, innerX, y + 2, usageStr:sub(1, innerW), uc)

  -- Simple bar for rate (capped at ±10k FE/t for visualization)
  if h > 4 then
    local maxRate = 10000
    local pct     = math.min(100, math.abs(rate) / maxRate * 100)
    local barColor = colors.lime
    if term.isColor() then
      if pct < cfg.powerLow then
        barColor = flashState and colors.red or colors.orange
      elseif pct < 50 then
        barColor = colors.yellow
      end
    end
    miniBar(t, innerX, y + 3, innerW, pct, barColor, nil)
  end
end

-- Storage panel
local function renderStorage(t, x, y, w, h, data, cfg)
  renderBorder(t, x, y, w, h, "STORAGE")
  local innerX = x + 1
  local innerW = w - 2

  if not data then
    writeAt(t, innerX, y + 1, ("No ME/RS bridge"):sub(1, innerW),
      term.isColor() and colors.gray or nil)
    writeAt(t, innerX, y + 2, ("Attach meBridge/rsBridge"):sub(1, innerW),
      term.isColor() and colors.gray or nil)
    return
  end

  local typesStr = "Types: " .. ui.formatNumber(data.itemTypes)
  local countStr = "Items: " .. ui.formatNumber(data.totalItems)
  writeAt(t, innerX, y + 1, typesStr:sub(1, innerW),
    term.isColor() and colors.cyan or nil)
  writeAt(t, innerX, y + 2, countStr:sub(1, innerW),
    term.isColor() and colors.white or nil)
end

-- Environment panel
local function renderEnvironment(t, x, y, w, h, data)
  renderBorder(t, x, y, w, h, "ENVIRONMENT")
  local innerX = x + 1
  local innerW = w - 2

  if not data then
    writeAt(t, innerX, y + 1, ("No env detector"):sub(1, innerW),
      term.isColor() and colors.gray or nil)
    return
  end

  local timeStr    = "Time: " .. formatGameTime(data.time)
  local dayStr     = "Day: "  .. tostring(data.day or 0)
  local weatherStr = "Sky: "  .. (data.weather or "clear")
  local biomeStr   = "Biome: ".. (data.biome or "?"):sub(1, innerW - 7)
  local moonStr    = "Moon: " .. (MOON_PHASES[data.moon] or "?")

  local wCol = colors.white
  if term.isColor() then
    if data.weather == "thunder" then
      wCol = flashState and colors.red or colors.orange
    elseif data.weather == "rain" then
      wCol = colors.cyan
    else
      wCol = data.isDay and colors.yellow or colors.blue
    end
  end

  local row = y + 1
  writeAt(t, innerX, row,     timeStr:sub(1, innerW),    term.isColor() and colors.yellow or nil)
  writeAt(t, innerX, row + 1, dayStr:sub(1, innerW),     term.isColor() and colors.lightGray or nil)
  if h > 4 then
    writeAt(t, innerX, row + 2, weatherStr:sub(1, innerW), wCol)
  end
  if h > 5 then
    writeAt(t, innerX, row + 3, biomeStr:sub(1, innerW),   term.isColor() and colors.green or nil)
  end
  if h > 6 then
    writeAt(t, innerX, row + 4, moonStr:sub(1, innerW),    term.isColor() and colors.lightBlue or nil)
  end
end

-- Players panel
local function renderPlayers(t, x, y, w, h, data)
  renderBorder(t, x, y, w, h, "PLAYERS")
  local innerX = x + 1
  local innerW = w - 2

  if not data then
    writeAt(t, innerX, y + 1, ("No player detector"):sub(1, innerW),
      term.isColor() and colors.gray or nil)
    return
  end

  local players = data.players or {}
  if #players == 0 then
    writeAt(t, innerX, y + 1, "No players nearby",
      term.isColor() and colors.gray or nil)
    return
  end

  local maxShow = h - 2
  for i, name in ipairs(players) do
    if i > maxShow then break end
    writeAt(t, innerX, y + i, ("* " .. tostring(name)):sub(1, innerW),
      term.isColor() and colors.lime or nil)
  end
  if #players > maxShow then
    writeAt(t, innerX, y + maxShow, ("+" .. (#players - maxShow + 1) .. " more"):sub(1, innerW),
      term.isColor() and colors.gray or nil)
  end
end

-- Clock panel
local function renderClock(t, x, y, w, h, data)
  renderBorder(t, x, y, w, h, "CLOCK")
  local innerX = x + 1
  local innerW = w - 2

  -- Real-world clock
  local rt = os.time()
  local rh = math.floor(rt)
  local rm = math.floor((rt - rh) * 60)
  local realStr = string.format("Real: %02d:%02d", rh % 24, rm)
  writeAt(t, innerX, y + 1, realStr:sub(1, innerW),
    term.isColor() and colors.lightGray or nil)

  if data then
    local igStr  = "Game: " .. formatGameTime(data.time)
    local dayStr = "Day #" .. tostring(data.day or 0)
    writeAt(t, innerX, y + 2, igStr:sub(1, innerW),
      term.isColor() and colors.yellow or nil)
    if h > 4 then
      writeAt(t, innerX, y + 3, dayStr:sub(1, innerW),
        term.isColor() and colors.orange or nil)
    end
  else
    writeAt(t, innerX, y + 2, "(no env detector)",
      term.isColor() and colors.gray or nil)
  end
end

-- Log panel
local function renderLog(t, x, y, w, h)
  renderBorder(t, x, y, w, h, "LOG")
  local innerX = x + 1
  local innerW = w - 2
  local lines  = config.readLog(LOG_FILE, 5)

  if #lines == 0 then
    writeAt(t, innerX, y + 1, "No log entries",
      term.isColor() and colors.gray or nil)
    return
  end

  local maxShow = h - 2
  for i, line in ipairs(lines) do
    if i > maxShow then break end
    writeAt(t, innerX, y + i, tostring(line):sub(1, innerW),
      term.isColor() and colors.lightGray or nil)
  end
end

-- Dispatcher
local function renderPanel(t, panelName, x, y, w, h, powerData, storageData, envData, playersData)
  -- Clear panel area
  if term.isColor() then
    t.setBackgroundColor(colors.black)
    t.setTextColor(colors.white)
  end
  for row = y, y + h - 1 do
    t.setCursorPos(x, row)
    t.write(string.rep(" ", w))
  end

  if panelName == "power" then
    renderPower(t, x, y, w, h, powerData, cfg)
  elseif panelName == "storage" then
    renderStorage(t, x, y, w, h, storageData, cfg)
  elseif panelName == "environment" then
    renderEnvironment(t, x, y, w, h, envData)
  elseif panelName == "players" then
    renderPlayers(t, x, y, w, h, playersData)
  elseif panelName == "clock" then
    renderClock(t, x, y, w, h, envData)
  elseif panelName == "log" then
    renderLog(t, x, y, w, h)
  else
    renderBorder(t, x, y, w, h, panelName)
    writeAt(t, x + 1, y + 1, ("Unknown panel: " .. panelName):sub(1, w - 2),
      term.isColor() and colors.red or nil)
  end
end

-- ─────────────────────────────────────────
-- Layout calculator
-- Returns list of {name, x, y, w, h}
-- ─────────────────────────────────────────
local function computeLayout(panels, scrW, scrH)
  local n       = #panels
  if n == 0 then return {} end

  -- Reserve row 1 for header, last row for footer
  local availY  = 2
  local availH  = scrH - 2  -- rows 2..h-1

  local cols, rows
  if n == 1 then
    cols, rows = 1, 1
  elseif n == 2 then
    cols, rows = 2, 1
  elseif n <= 4 then
    cols, rows = 2, 2
  elseif n <= 6 then
    cols, rows = 3, 2
  else
    cols = 3
    rows = math.ceil(n / cols)
  end

  local cellW = math.floor(scrW / cols)
  local cellH = math.floor(availH / rows)
  local layout = {}

  for i, name in ipairs(panels) do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local x   = col * cellW + 1
    local y   = availY + row * cellH
    -- Last column gets remainder width
    local w   = (col == cols - 1) and (scrW - col * cellW) or cellW
    -- Last row gets remainder height
    local h   = (row == rows - 1) and (scrH - 1 - row * cellH - 1) or cellH
    -- Minimum dimensions
    if w < 8 then w = 8 end
    if h < 3 then h = 3 end
    table.insert(layout, { name = name, x = x, y = y, w = w, h = h })
  end

  return layout
end

-- ─────────────────────────────────────────
-- Full dashboard draw
-- ─────────────────────────────────────────
local function drawDashboard(target)
  local w, h = target.getSize()
  -- Redirect term to target for ui functions to work on it
  local prev = term.redirect(target)

  ui.clear()
  local now = os.date and os.date("*t") or nil
  local timeStr = ""
  if now then
    timeStr = string.format("%02d:%02d", now.hour or 0, now.min or 0)
  end
  ui.drawHeader("Base Monitor", timeStr)
  ui.drawFooter("[Q] Quit  [R] Refresh  [C] Config")

  -- Collect data
  local powerData   = getPowerData()
  local storageData = getStorageData()
  local envData     = getEnvData()
  local playersData = getPlayersData()

  -- Compute layout
  local layout = computeLayout(cfg.panels, w, h)

  -- Render each panel (pass target so renderPanel can setCursorPos etc.)
  for _, panel in ipairs(layout) do
    renderPanel(target, panel.name, panel.x, panel.y, panel.w, panel.h,
      powerData, storageData, envData, playersData)
  end

  if #layout == 0 then
    ui.writeCentered(math.floor(h / 2), "No panels configured. Press C to configure.",
      term.isColor() and colors.gray or nil)
  end

  term.redirect(prev)
end

-- ─────────────────────────────────────────
-- Terminal compact status (when monitor is present)
-- ─────────────────────────────────────────
local function drawTerminalStatus()
  ui.clear()
  ui.drawHeader("Base Monitor", "")
  local w, h = term.getSize()

  -- Show short status summary
  local row = 3
  if term.isColor() then
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
  end

  term.setCursorPos(1, row)
  term.write("Dashboard running on monitor.")
  row = row + 1

  -- Power
  local pd = getPowerData()
  if pd then
    term.setCursorPos(1, row)
    term.write("Power rate: " .. ui.formatEnergy(pd.rate) .. "/t")
    row = row + 1
  end

  -- Storage
  local sd = getStorageData()
  if sd then
    term.setCursorPos(1, row)
    term.write("Storage types: " .. ui.formatNumber(sd.itemTypes))
    row = row + 1
  end

  -- Environment
  local ed = getEnvData()
  if ed then
    term.setCursorPos(1, row)
    term.write("Time: " .. formatGameTime(ed.time) .. "  Day: " .. ed.day)
    row = row + 1
    term.setCursorPos(1, row)
    term.write("Weather: " .. ed.weather)
    row = row + 1
  end

  row = row + 1
  term.setCursorPos(1, row)
  term.write("Refresh in " .. cfg.refreshRate .. "s")

  ui.drawFooter("[Q] Quit  [R] Refresh  [C] Config")
end

-- ─────────────────────────────────────────
-- Panel configuration screen
-- ─────────────────────────────────────────
local function configurepanels()
  while true do
    -- Build menu items showing which panels are enabled
    local items = {}
    for _, pname in ipairs(ALL_PANELS) do
      local enabled = false
      for _, ep in ipairs(cfg.panels) do
        if ep == pname then enabled = true; break end
      end
      local status = enabled and "[ON] " or "[off]"
      table.insert(items, status .. " " .. pname)
    end
    table.insert(items, "--- Save & Return ---")

    local idx = ui.drawMenu(items, "Configure Panels")
    if not idx then break end

    if idx == #items then
      -- Save
      config.save(CFG_FILE, cfg)
      break
    else
      local pname  = ALL_PANELS[idx]
      local found  = false
      local newList = {}
      for _, ep in ipairs(cfg.panels) do
        if ep == pname then
          found = true
        else
          table.insert(newList, ep)
        end
      end
      if found then
        cfg.panels = newList
      else
        table.insert(cfg.panels, pname)
      end
    end
  end
end

-- ─────────────────────────────────────────
-- Main loop
-- ─────────────────────────────────────────
local function main()
  cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  discoverPeripherals()

  local monitor = findBestMonitor()

  -- Start timer
  timerId = os.startTimer(cfg.refreshRate)

  -- Initial draw
  if monitor then
    pcall(monitor.setTextScale, 0.5)
    drawDashboard(monitor)
    drawTerminalStatus()
  else
    drawDashboard(term)
  end

  while running do
    local evt, p1, p2, p3 = os.pullEvent()

    if evt == "timer" and p1 == timerId then
      flashState = not flashState
      discoverPeripherals()
      monitor = findBestMonitor()

      if monitor then
        pcall(monitor.setTextScale, 0.5)
        drawDashboard(monitor)
        drawTerminalStatus()
      else
        drawDashboard(term)
      end

      -- Log summary
      local pd = getPowerData()
      local logLine = "Refresh"
      if pd then logLine = logLine .. " | Power rate: " .. ui.formatEnergy(pd.rate) .. "/t" end
      local sd = getStorageData()
      if sd then logLine = logLine .. " | Items: " .. ui.formatNumber(sd.totalItems) end
      config.appendLog(LOG_FILE, logLine)

      timerId = os.startTimer(cfg.refreshRate)

    elseif evt == "key" then
      local k = p1
      if k == keys.q then
        running = false

      elseif k == keys.r then
        -- Force refresh
        if timerId then os.cancelTimer(timerId) end
        flashState = not flashState
        discoverPeripherals()
        monitor = findBestMonitor()
        if monitor then
          pcall(monitor.setTextScale, 0.5)
          drawDashboard(monitor)
          drawTerminalStatus()
        else
          drawDashboard(term)
        end
        timerId = os.startTimer(cfg.refreshRate)

      elseif k == keys.c then
        if timerId then os.cancelTimer(timerId) end
        configurepanels()
        -- Redraw after config
        discoverPeripherals()
        monitor = findBestMonitor()
        if monitor then
          pcall(monitor.setTextScale, 0.5)
          drawDashboard(monitor)
          drawTerminalStatus()
        else
          drawDashboard(term)
        end
        timerId = os.startTimer(cfg.refreshRate)
      end

    elseif evt == "monitor_resize" then
      -- A monitor was resized; re-draw
      monitor = findBestMonitor()
      if monitor then
        pcall(monitor.setTextScale, 0.5)
        drawDashboard(monitor)
      end

    elseif evt == "peripheral" or evt == "peripheral_detach" then
      discoverPeripherals()
      monitor = findBestMonitor()
      if monitor then
        pcall(monitor.setTextScale, 0.5)
        drawDashboard(monitor)
        drawTerminalStatus()
      else
        drawDashboard(term)
      end

    elseif evt == "terminate" then
      running = false
    end
  end

  -- Clean up
  ui.clear()
  ui.resetColor()
  print("Base Monitor stopped.")
end

main()
