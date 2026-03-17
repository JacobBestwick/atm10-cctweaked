-- power_grid.lua
-- ATM10 Power Network Monitor & Controller
-- Device: Computer / Advanced Computer
-- Required: energyDetector (Advanced Peripherals Energy Detector)
-- Optional: redstoneIntegrator, chatBox, monitor
--
-- Reads FE transfer rates, logs history, and can auto-control generators
-- via redstone outputs when power drops below configurable thresholds.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local detect = require("detect")
local ui     = require("ui")
local config = require("config")

-- ─────────────────────────────────────────────
-- Constants
-- ─────────────────────────────────────────────
local CFG_FILE  = "power_grid.cfg"
local LOG_FILE  = "power_grid_log.txt"

local DEFAULTS = {
  sources           = {},
  lowThreshold      = 25,
  criticalThreshold = 10,
  logInterval       = 60,
  redstoneControl   = false,
  alertsEnabled     = true,
  controlRules      = {},
}

local SIDES = { "north", "south", "east", "west", "top", "bottom" }

-- ─────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────
local cfg        = {}
local running    = true
local flashState = false

-- Peripherals
local energyDet  = nil
local rsIntegr   = nil
local chatBox    = nil
local monitor    = nil

local function discoverPeripherals()
  energyDet, _ = detect.findPeripheral("energyDetector")
  rsIntegr,  _ = detect.findPeripheral("redstoneIntegrator")
  chatBox,   _ = detect.findPeripheral("chatBox")

  -- Find best monitor
  monitor = nil
  local bestArea = 0
  local ok, names = pcall(peripheral.getNames)
  if ok and names then
    for _, name in ipairs(names) do
      local ok2, pt = pcall(peripheral.getType, name)
      if ok2 and pt == "monitor" then
        local m = peripheral.wrap(name)
        if m then
          local ok3, mw, mh = pcall(m.getSize)
          if ok3 and mw * mh > bestArea then
            bestArea = mw * mh
            monitor  = m
          end
        end
      end
    end
  end
end

-- ─────────────────────────────────────────────
-- Energy reading
-- ─────────────────────────────────────────────
local function readEnergy()
  if not energyDet then return nil end
  local ok1, rate  = pcall(function() return energyDet.getTransferRate() end)
  local ok2, usage = pcall(function() return energyDet.getEnergyUsage()  end)
  return {
    rate  = (ok1 and tonumber(rate))  or 0,
    usage = (ok2 and tonumber(usage)) or 0,
  }
end

-- Estimate percentage from rate (10,000 FE/t = 100%)
local MAX_RATE = 10000
local function rateToPercent(rate)
  return math.min(100, math.max(0, math.abs(rate) / MAX_RATE * 100))
end

-- ─────────────────────────────────────────────
-- Live monitor
-- ─────────────────────────────────────────────
local function drawLiveMonitor(target, data)
  local w, h = target.getSize()
  local prev = term.redirect(target)

  ui.clear()
  ui.drawHeader("Power Grid", "Live Monitor")

  local row = 3

  if not data then
    ui.setColor(colors.red, colors.black)
    ui.writeCentered(row, "No energy detector found!")
    row = row + 1
    ui.setColor(colors.gray, colors.black)
    ui.writeCentered(row, "Attach an energyDetector peripheral")
    row = row + 1
    ui.writeCentered(row, "and connect it between two power cables.")
    ui.resetColor()
    term.redirect(prev)
    return
  end

  local rate    = data.rate  or 0
  local usage   = data.usage or 0
  local pct     = rateToPercent(rate)

  -- Color based on level
  local barColor = colors.lime
  if term.isColor() then
    if pct <= cfg.criticalThreshold then
      barColor = flashState and colors.red or colors.orange
    elseif pct <= cfg.lowThreshold then
      barColor = colors.yellow
    end
  end

  -- Big progress bar
  ui.setColor(colors.white, colors.black)
  term.setCursorPos(1, row)
  term.write("Transfer Rate:")
  row = row + 1

  ui.drawProgressBar(1, row, w, pct, barColor, colors.gray,
    ui.formatEnergy(math.abs(rate)) .. "/t  " .. math.floor(pct) .. "%")
  row = row + 2

  -- Stats row
  local direction = rate >= 0 and "IN " or "OUT"
  local rateColor = (rate >= 0) and colors.lime or colors.red
  ui.setColor(rateColor, colors.black)
  term.setCursorPos(2, row)
  term.write(direction .. " " .. ui.formatEnergy(math.abs(rate)) .. "/t")
  ui.resetColor()
  ui.setColor(colors.orange, colors.black)
  term.setCursorPos(math.floor(w / 2) + 2, row)
  term.write("Usage: " .. ui.formatEnergy(usage) .. "/t")
  ui.resetColor()
  row = row + 2

  -- Named sources from config
  if #cfg.sources > 0 then
    ui.setColor(colors.gray, colors.black)
    term.setCursorPos(1, row)
    term.write("Configured Sources:")
    row = row + 1
    for _, src in ipairs(cfg.sources) do
      ui.setColor(colors.cyan, colors.black)
      term.setCursorPos(3, row)
      term.write(("* " .. (src.label or "?")):sub(1, w - 2))
      row = row + 1
      if row >= h - 2 then break end
    end
  end

  -- Redstone states
  if rsIntegr and #cfg.controlRules > 0 then
    row = row + 1
    ui.setColor(colors.gray, colors.black)
    term.setCursorPos(1, row)
    term.write("Redstone Outputs:")
    row = row + 1
    for _, rule in ipairs(cfg.controlRules) do
      local ok, state = pcall(function()
        return rsIntegr.getOutput(rule.side)
      end)
      local stateStr = (ok and state) and "ON" or "off"
      local stateColor = (ok and state) and colors.lime or colors.gray
      ui.setColor(stateColor, colors.black)
      term.setCursorPos(3, row)
      term.write(string.format("%-8s %s  (<%s%% → %s)",
        rule.side, stateStr,
        tostring(rule.threshold),
        rule.state and "ON" or "OFF"):sub(1, w - 2))
      row = row + 1
      if row >= h - 2 then break end
    end
    ui.resetColor()
  end

  ui.drawFooter("[Q] Stop  [R] Refresh")
  term.redirect(prev)
end

local function runLiveMonitor()
  discoverPeripherals()

  if not energyDet then
    ui.alert(
      "No energy detector found!\n\n" ..
      "Craft an Energy Detector from Advanced\n" ..
      "Peripherals and place it in-line between\n" ..
      "two power cables to measure flow.\n\n" ..
      "Then connect it to this computer.",
      "error"
    )
    return
  end

  local monRunning = true
  local timerId    = os.startTimer(2)
  local logTimer   = os.startTimer(cfg.logInterval)
  local lastLog    = os.clock()

  local function doRedraw()
    flashState = not flashState
    local data = readEnergy()

    -- Apply redstone control rules
    if cfg.redstoneControl and rsIntegr and data then
      local pct = rateToPercent(data.rate)
      for _, rule in ipairs(cfg.controlRules) do
        if pct <= rule.threshold then
          pcall(rsIntegr.setOutput, rule.side, rule.state)
        else
          pcall(rsIntegr.setOutput, rule.side, not rule.state)
        end
      end
    end

    -- Draw to monitor if available
    if monitor then
      pcall(monitor.setTextScale, 0.5)
      drawLiveMonitor(monitor, data)
    end
    drawLiveMonitor(term, data)
  end

  doRedraw()

  while monRunning do
    local evt, p1 = os.pullEvent()

    if evt == "timer" then
      if p1 == timerId then
        doRedraw()
        timerId = os.startTimer(2)
      elseif p1 == logTimer then
        local data = readEnergy()
        if data then
          config.appendLog(LOG_FILE, string.format(
            "rate=%.1f/t  usage=%.1f/t", data.rate, data.usage))
        end
        logTimer = os.startTimer(cfg.logInterval)
      end

    elseif evt == "key" then
      if p1 == keys.q or p1 == keys.backspace then
        monRunning = false
      elseif p1 == keys.r then
        doRedraw()
      end

    elseif evt == "terminate" then
      monRunning = false
    end
  end
end

-- ─────────────────────────────────────────────
-- Configure sources
-- ─────────────────────────────────────────────
local function configureSources()
  while true do
    local items = {}
    for i, src in ipairs(cfg.sources) do
      table.insert(items, { label = src.label or "Source " .. i, description = "side: " .. (src.side or "?") })
    end
    table.insert(items, { label = "+ Add Source" })
    table.insert(items, { label = "< Back" })

    local idx = ui.drawMenu(items, "Power Sources")
    if not idx or idx == #items then return end

    if idx == #items - 1 then
      -- Add source
      local label = ui.inputText("Source label (e.g. Mekanism Fusion): ")
      if label and label ~= "" then
        local sideItems = {}
        for _, s in ipairs(SIDES) do
          table.insert(sideItems, s)
        end
        table.insert(sideItems, "< Cancel")
        local sidx = ui.drawMenu(sideItems, "Which side is the detector on?")
        if sidx and sidx <= #SIDES then
          table.insert(cfg.sources, { label = label, side = SIDES[sidx] })
          config.save(CFG_FILE, cfg)
          ui.alert("Source '" .. label .. "' added.", "success")
        end
      end
    else
      -- Options for existing source
      local src = cfg.sources[idx]
      local opts = { "Rename", "Delete", "< Cancel" }
      local oidx = ui.drawMenu(opts, src.label or "Source")
      if oidx == 1 then
        local newLabel = ui.inputText("New label: ", src.label)
        if newLabel and newLabel ~= "" then
          cfg.sources[idx].label = newLabel
          config.save(CFG_FILE, cfg)
        end
      elseif oidx == 2 then
        if ui.confirm("Delete source '" .. (src.label or "?") .. "'?") then
          table.remove(cfg.sources, idx)
          config.save(CFG_FILE, cfg)
        end
      end
    end
  end
end

-- ─────────────────────────────────────────────
-- Power history (ASCII chart)
-- ─────────────────────────────────────────────
local function showHistory()
  local lines = config.readLog(LOG_FILE, 40)
  if #lines == 0 then
    ui.alert("No power history yet.\nRun Live Monitor to generate logs.", "info")
    return
  end

  -- Parse rates from log entries
  local rates = {}
  for _, line in ipairs(lines) do
    local r = line:match("rate=([-%.%d]+)")
    if r then table.insert(rates, tonumber(r) or 0) end
  end

  -- Build ASCII bar chart
  local w = 38
  local chartLines = {
    "Power History  (" .. #rates .. " samples)",
    string.rep("-", w),
  }

  local maxRate = 1
  for _, r in ipairs(rates) do
    if math.abs(r) > maxRate then maxRate = math.abs(r) end
  end

  for i = math.max(1, #rates - 20), #rates do
    local r   = rates[i]
    local pct = math.min(100, math.abs(r) / maxRate * 100)
    local bar = math.floor(pct / 100 * (w - 12))
    local dir = r >= 0 and "+" or "-"
    table.insert(chartLines, string.format("%s%6s/t |%s",
      dir, ui.formatEnergy(math.abs(r)), string.rep("#", bar)))
  end

  table.insert(chartLines, string.rep("-", w))
  -- Append raw log entries
  table.insert(chartLines, "")
  table.insert(chartLines, "Raw Log:")
  for _, line in ipairs(lines) do
    table.insert(chartLines, "  " .. line)
  end

  ui.pager(chartLines, "Power History")
end

-- ─────────────────────────────────────────────
-- Redstone control rules
-- ─────────────────────────────────────────────
local function configureRedstone()
  discoverPeripherals()
  if not rsIntegr then
    ui.alert("No redstoneIntegrator found.\nAttach one from Advanced Peripherals.", "error")
    return
  end

  while true do
    local items = {}
    for i, rule in ipairs(cfg.controlRules) do
      local desc = string.format("<%d%% → %s %s", rule.threshold, rule.side, rule.state and "ON" or "OFF")
      table.insert(items, { label = "Rule " .. i, description = desc })
    end
    table.insert(items, { label = "Toggle Auto-Control: " .. (cfg.redstoneControl and "ON" or "OFF") })
    table.insert(items, { label = "+ Add Rule" })
    table.insert(items, { label = "< Back" })

    local idx = ui.drawMenu(items, "Redstone Control")
    local back = #items

    if not idx or idx == back then return end

    if idx == back - 1 then
      -- Add rule
      local raw = ui.inputText("Power % threshold (e.g. 25): ")
      local thresh = tonumber(raw)
      if not thresh or thresh < 0 or thresh > 100 then
        ui.alert("Invalid threshold.", "warn")
      else
        local sideItems = {}
        for _, s in ipairs(SIDES) do table.insert(sideItems, s) end
        table.insert(sideItems, "< Cancel")
        local sidx = ui.drawMenu(sideItems, "Output side")
        if sidx and sidx <= #SIDES then
          local stateItems = { "Set to ON", "Set to OFF", "< Cancel" }
          local stidx = ui.drawMenu(stateItems, "When below threshold:")
          if stidx == 1 or stidx == 2 then
            table.insert(cfg.controlRules, {
              threshold = thresh,
              side      = SIDES[sidx],
              state     = stidx == 1,
            })
            config.save(CFG_FILE, cfg)
            ui.alert("Rule added.", "success")
          end
        end
      end

    elseif idx == back - 2 then
      -- Toggle auto-control
      cfg.redstoneControl = not cfg.redstoneControl
      config.save(CFG_FILE, cfg)

    else
      -- Delete existing rule
      if ui.confirm("Delete Rule " .. idx .. "?") then
        table.remove(cfg.controlRules, idx)
        config.save(CFG_FILE, cfg)
      end
    end
  end
end

-- ─────────────────────────────────────────────
-- Alerts config
-- ─────────────────────────────────────────────
local function configureAlerts()
  while true do
    local items = {
      { label = "Chat Alerts: " .. (cfg.alertsEnabled and "ON" or "OFF"),
        description = "via chatBox peripheral" },
      { label = "Low threshold: " .. cfg.lowThreshold .. "%",
        description = "warning level" },
      { label = "Critical threshold: " .. cfg.criticalThreshold .. "%",
        description = "danger level" },
      { label = "Log interval: " .. cfg.logInterval .. "s",
        description = "how often to log" },
      { label = "< Back" },
    }

    local idx = ui.drawMenu(items, "Alert Config")
    if not idx or idx == 5 then return end

    if idx == 1 then
      cfg.alertsEnabled = not cfg.alertsEnabled
      config.save(CFG_FILE, cfg)
    elseif idx == 2 then
      local raw = ui.inputText("Low threshold % (default 25): ", tostring(cfg.lowThreshold))
      local v   = tonumber(raw)
      if v and v >= 0 and v <= 100 then
        cfg.lowThreshold = v
        config.save(CFG_FILE, cfg)
      end
    elseif idx == 3 then
      local raw = ui.inputText("Critical threshold % (default 10): ", tostring(cfg.criticalThreshold))
      local v   = tonumber(raw)
      if v and v >= 0 and v <= 100 then
        cfg.criticalThreshold = v
        config.save(CFG_FILE, cfg)
      end
    elseif idx == 4 then
      local raw = ui.inputText("Log interval in seconds: ", tostring(cfg.logInterval))
      local v   = tonumber(raw)
      if v and v >= 5 then
        cfg.logInterval = v
        config.save(CFG_FILE, cfg)
      end
    end
  end
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  discoverPeripherals()
  cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  if not energyDet then
    ui.clear()
    ui.drawHeader("Power Grid", "Setup Required")
    local msg = {
      "No Energy Detector found!",
      "",
      "Craft an Energy Detector from Advanced",
      "Peripherals. Place it IN-LINE between two",
      "power cables — it measures the flow of FE",
      "through the cable it is placed on.",
      "",
      "Then connect it to this computer via:",
      "  - Direct placement (adjacent to computer)",
      "  - Wired Modem Network",
      "",
      "Press any key to open anyway...",
    }
    for i, line in ipairs(msg) do
      ui.setColor(i == 1 and colors.red or colors.white, colors.black)
      term.setCursorPos(2, i + 2)
      local w, _ = term.getSize()
      term.write(line:sub(1, w - 2))
    end
    ui.resetColor()
    os.pullEvent("key")
  end

  while running do
    local items = {
      { label = "Live Monitor",      description = "Real-time power display" },
      { label = "Configure Sources", description = #cfg.sources .. " sources" },
      { label = "Power History",     description = "Log & ASCII chart" },
      { label = "Redstone Control",  description = cfg.redstoneControl and "AUTO" or "manual" },
      { label = "Alert Config",      description = "Thresholds & chat" },
      { label = "< Back to Hub",     description = "" },
    }

    local idx = ui.drawMenu(items, "Power Grid")
    if not idx or idx == 6 then running = false; break end

    if idx == 1 then runLiveMonitor()
    elseif idx == 2 then configureSources()
    elseif idx == 3 then showHistory()
    elseif idx == 4 then configureRedstone()
    elseif idx == 5 then configureAlerts()
    end

    discoverPeripherals()
  end
end

main()
