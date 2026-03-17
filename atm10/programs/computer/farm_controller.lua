-- farm_controller.lua
-- ATM10 Multi-Farm Automation Controller
-- Device: Computer / Advanced Computer
-- Required: redstoneIntegrator (Advanced Peripherals)
-- Optional: inventoryManager (for storage level monitoring)
--
-- Automates farm on/off cycles based on output storage levels.
-- Works with Mystical Agriculture, Productive Bees, and any
-- redstone-controllable farm.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local detect = require("detect")
local ui     = require("ui")
local config = require("config")

-- ─────────────────────────────────────────────
-- Constants
-- ─────────────────────────────────────────────
local CFG_FILE = "farm_controller.cfg"
local LOG_FILE = "farm_controller_log.txt"

local DEFAULTS = {
  farms           = {},
  checkInterval   = 60,
  fullThreshold   = 90,
  resumeThreshold = 50,
}

local SIDES = { "north", "south", "east", "west", "top", "bottom" }

-- ─────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────
local cfg     = {}
local running = true
local rsIntegr  = nil
local invMgr    = nil

local function discoverPeripherals()
  rsIntegr, _ = detect.findPeripheral("redstoneIntegrator")
  invMgr,   _ = detect.findPeripheral("inventoryManager")
end

-- ─────────────────────────────────────────────
-- Inventory fill % helper
-- Uses the inventory manager to count used vs total slots
-- ─────────────────────────────────────────────
local function getInventoryFill(chestName)
  if not invMgr then return nil end
  local ok, items = pcall(function() return invMgr.getItems() end)
  if not ok or type(items) ~= "table" then return nil end

  local used  = 0
  local total = 54  -- default chest size
  for _, item in ipairs(items) do
    if item and item.name ~= "minecraft:air" then
      used = used + 1
    end
  end
  -- Approximation: use slot count heuristic
  return math.min(100, math.floor(used / total * 100))
end

-- ─────────────────────────────────────────────
-- Redstone control
-- ─────────────────────────────────────────────
local function setFarmRedstone(farm, state)
  if not rsIntegr then return false end
  local ok, err = pcall(rsIntegr.setOutput, farm.redstone_side or "north", state)
  if ok then
    farm.rsState = state
    return true
  end
  return false
end

local function getFarmRedstoneState(farm)
  if not rsIntegr then return nil end
  local ok, state = pcall(rsIntegr.getOutput, farm.redstone_side or "north")
  return ok and state or nil
end

-- ─────────────────────────────────────────────
-- Farm status display
-- ─────────────────────────────────────────────
local function drawFarmStatus()
  while true do
    discoverPeripherals()
    ui.clear()
    ui.drawHeader("Farm Controller", "Status")

    local w, h = term.getSize()
    local row  = 3

    if #cfg.farms == 0 then
      ui.setColor(colors.gray, colors.black)
      ui.writeCentered(5, "No farms configured.")
      ui.writeCentered(6, "Use 'Add Farm' to set one up.")
      ui.resetColor()
    else
      -- Header row
      ui.setColor(colors.gray, colors.black)
      term.setCursorPos(1, row)
      term.write(string.format("%-16s %-8s %5s %-10s", "Farm", "Status", "Fill%", "Side"))
      row = row + 1
      ui.resetColor()

      for _, farm in ipairs(cfg.farms) do
        if row >= h - 3 then break end

        local fill   = getInventoryFill(farm.monitor_chest)
        local rsState = getFarmRedstoneState(farm)

        local statusStr   = "Unknown"
        local statusColor = colors.gray
        if not farm.enabled then
          statusStr   = "Disabled"
          statusColor = colors.gray
        elseif fill then
          if fill >= cfg.fullThreshold then
            statusStr   = "FULL"
            statusColor = colors.orange
          elseif fill >= cfg.resumeThreshold then
            statusStr   = "Running"
            statusColor = colors.lime
          else
            statusStr   = "Resumed"
            statusColor = colors.cyan
          end
        elseif rsState ~= nil then
          statusStr   = rsState and "ON" or "OFF"
          statusColor = rsState and colors.lime or colors.gray
        end

        local fillStr = fill and (tostring(fill) .. "%") or "N/A"
        local name    = (farm.name or "Farm"):sub(1, 15)

        ui.setColor(statusColor, colors.black)
        term.setCursorPos(1, row)
        term.write(string.format("%-16s %-8s %5s %-10s",
          name, statusStr, fillStr, farm.redstone_side or "?"):sub(1, w))
        row = row + 1
        ui.resetColor()
      end
    end

    -- Last few log entries
    local logs = config.readLog(LOG_FILE, 5)
    if #logs > 0 then
      row = h - #logs - 2
      ui.hLine(row, "-", colors.gray)
      row = row + 1
      for _, line in ipairs(logs) do
        if row >= h - 1 then break end
        ui.setColor(colors.lightGray, colors.black)
        term.setCursorPos(1, row)
        term.write(line:sub(1, w))
        row = row + 1
        ui.resetColor()
      end
    end

    ui.drawFooter("[Q] Back  [R] Refresh")

    local _, key = os.pullEvent("key")
    if key == keys.q or key == keys.backspace then return end
    -- R or any other key = refresh
  end
end

-- ─────────────────────────────────────────────
-- Add farm wizard
-- ─────────────────────────────────────────────
local function addFarm()
  -- Name
  local name = ui.inputText("Farm name (e.g. 'Mystical Inferium'): ")
  if not name or name == "" then return end

  -- Redstone side
  local sideItems = {}
  for _, s in ipairs(SIDES) do table.insert(sideItems, s) end
  table.insert(sideItems, "< Cancel")
  local sidx = ui.drawMenu(sideItems, "Redstone output side")
  if not sidx or sidx > #SIDES then return end
  local side = SIDES[sidx]

  -- Full threshold
  local rawFull = ui.inputText("Stop farm at fill % (default " .. cfg.fullThreshold .. "): ",
    tostring(cfg.fullThreshold))
  local fullT = tonumber(rawFull) or cfg.fullThreshold

  -- Resume threshold
  local rawResume = ui.inputText("Restart farm at fill % (default " .. cfg.resumeThreshold .. "): ",
    tostring(cfg.resumeThreshold))
  local resumeT = tonumber(rawResume) or cfg.resumeThreshold

  table.insert(cfg.farms, {
    name             = name,
    redstone_side    = side,
    monitor_chest    = nil,
    full_threshold   = fullT,
    resume_threshold = resumeT,
    enabled          = true,
    rsState          = false,
  })
  config.save(CFG_FILE, cfg)
  ui.alert("Farm '" .. name .. "' added!\nSide: " .. side, "success")
end

-- ─────────────────────────────────────────────
-- Edit farm
-- ─────────────────────────────────────────────
local function editFarm()
  if #cfg.farms == 0 then
    ui.alert("No farms to edit.", "info")
    return
  end

  local farmItems = {}
  for _, f in ipairs(cfg.farms) do
    table.insert(farmItems, { label = f.name or "Farm", description = f.redstone_side })
  end
  table.insert(farmItems, { label = "< Cancel" })

  local idx = ui.drawMenu(farmItems, "Select Farm to Edit")
  if not idx or idx > #cfg.farms then return end

  local farm = cfg.farms[idx]

  local opts = {
    { label = "Rename",             description = farm.name },
    { label = "Change Side",        description = farm.redstone_side },
    { label = "Full threshold",     description = tostring(farm.full_threshold or cfg.fullThreshold) .. "%" },
    { label = "Resume threshold",   description = tostring(farm.resume_threshold or cfg.resumeThreshold) .. "%" },
    { label = "Toggle Enable",      description = farm.enabled and "ON" or "OFF" },
    { label = "Delete Farm",        description = "Remove this farm" },
    { label = "< Back" },
  }

  local oidx = ui.drawMenu(opts, "Edit: " .. (farm.name or "Farm"))
  if not oidx or oidx == 7 then return end

  if oidx == 1 then
    local n = ui.inputText("New name: ", farm.name)
    if n and n ~= "" then farm.name = n; config.save(CFG_FILE, cfg) end

  elseif oidx == 2 then
    local sideItems = {}
    for _, s in ipairs(SIDES) do table.insert(sideItems, s) end
    table.insert(sideItems, "< Cancel")
    local sidx = ui.drawMenu(sideItems, "New side")
    if sidx and sidx <= #SIDES then
      farm.redstone_side = SIDES[sidx]
      config.save(CFG_FILE, cfg)
    end

  elseif oidx == 3 then
    local raw = ui.inputText("Full threshold %: ", tostring(farm.full_threshold))
    local v   = tonumber(raw)
    if v then farm.full_threshold = v; config.save(CFG_FILE, cfg) end

  elseif oidx == 4 then
    local raw = ui.inputText("Resume threshold %: ", tostring(farm.resume_threshold))
    local v   = tonumber(raw)
    if v then farm.resume_threshold = v; config.save(CFG_FILE, cfg) end

  elseif oidx == 5 then
    farm.enabled = not farm.enabled
    config.save(CFG_FILE, cfg)

  elseif oidx == 6 then
    if ui.confirm("Delete farm '" .. (farm.name or "?") .. "'?") then
      table.remove(cfg.farms, idx)
      config.save(CFG_FILE, cfg)
    end
  end
end

-- ─────────────────────────────────────────────
-- Manual controls
-- ─────────────────────────────────────────────
local function manualControls()
  discoverPeripherals()
  if not rsIntegr then
    ui.alert("No redstoneIntegrator found!\nAttach one from Advanced Peripherals.", "error")
    return
  end

  if #cfg.farms == 0 then
    ui.alert("No farms configured.", "info")
    return
  end

  local farmItems = {}
  for _, f in ipairs(cfg.farms) do
    local state = getFarmRedstoneState(f)
    local stateStr = state == nil and "?" or (state and "ON" or "OFF")
    table.insert(farmItems, { label = f.name or "Farm", description = stateStr })
  end
  table.insert(farmItems, { label = "< Back" })

  local idx = ui.drawMenu(farmItems, "Manual Control")
  if not idx or idx > #cfg.farms then return end

  local farm = cfg.farms[idx]
  local actions = { "Turn ON", "Turn OFF", "< Cancel" }
  local aidx = ui.drawMenu(actions, farm.name or "Farm")
  if aidx == 1 then
    setFarmRedstone(farm, true)
    config.appendLog(LOG_FILE, "Manual ON: " .. (farm.name or "?"))
    ui.alert(farm.name .. " turned ON.", "success")
  elseif aidx == 2 then
    setFarmRedstone(farm, false)
    config.appendLog(LOG_FILE, "Manual OFF: " .. (farm.name or "?"))
    ui.alert(farm.name .. " turned OFF.", "success")
  end
end

-- ─────────────────────────────────────────────
-- Auto mode loop
-- ─────────────────────────────────────────────
local function startAutoMode()
  discoverPeripherals()
  if not rsIntegr then
    ui.alert("No redstoneIntegrator found!\nAuto mode needs one to control redstone.", "error")
    return
  end

  if #cfg.farms == 0 then
    ui.alert("No farms configured.", "info")
    return
  end

  local autoRunning = true
  local timerId     = os.startTimer(1)

  local function doCheck()
    ui.clear()
    ui.drawHeader("Farm Controller", "AUTO MODE")

    local w, h = term.getSize()
    local row  = 3

    ui.setColor(colors.lime, colors.black)
    term.setCursorPos(1, row)
    term.write("Automatic farm monitoring active...")
    row = row + 2
    ui.resetColor()

    for _, farm in ipairs(cfg.farms) do
      if row >= h - 2 then break end
      if not farm.enabled then
        ui.setColor(colors.gray, colors.black)
        term.setCursorPos(1, row)
        term.write(("  [SKIP] " .. (farm.name or "Farm")):sub(1, w))
        row = row + 1
        ui.resetColor()
      else
        local fullT   = farm.full_threshold   or cfg.fullThreshold
        local resumeT = farm.resume_threshold or cfg.resumeThreshold
        local fill    = getInventoryFill(farm.monitor_chest)
        local action  = nil

        if fill then
          if fill >= fullT then
            -- Stop farm
            setFarmRedstone(farm, false)
            action = string.format("PAUSED (fill %d%% >= %d%%)", fill, fullT)
            config.appendLog(LOG_FILE, "Auto PAUSE: " .. (farm.name or "?") .. " fill=" .. fill .. "%")
          elseif fill <= resumeT then
            -- Start farm
            setFarmRedstone(farm, true)
            action = string.format("RUNNING (fill %d%% <= %d%%)", fill, resumeT)
            config.appendLog(LOG_FILE, "Auto RESUME: " .. (farm.name or "?") .. " fill=" .. fill .. "%")
          else
            local state = getFarmRedstoneState(farm)
            action = string.format("%s (fill %d%%)", state and "ON" or "OFF", fill)
          end
        else
          local state = getFarmRedstoneState(farm)
          action = string.format("%s (no inv data)", state and "ON" or "OFF")
        end

        local name = (farm.name or "Farm"):sub(1, 16)
        ui.setColor(colors.cyan, colors.black)
        term.setCursorPos(1, row)
        term.write(string.format("  %-16s %s", name, action):sub(1, w))
        row = row + 1
        ui.resetColor()
      end
    end

    row = row + 1
    ui.setColor(colors.lightGray, colors.black)
    term.setCursorPos(1, row)
    term.write("Next check in " .. cfg.checkInterval .. "s  |  Press Q to stop")
    ui.resetColor()
    ui.drawFooter("[Q] Stop auto mode")
  end

  doCheck()

  while autoRunning do
    local evt, p1 = os.pullEvent()
    if evt == "timer" and p1 == timerId then
      doCheck()
      timerId = os.startTimer(cfg.checkInterval)
    elseif evt == "key" and (p1 == keys.q or p1 == keys.backspace) then
      autoRunning = false
    elseif evt == "terminate" then
      autoRunning = false
    end
  end
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  discoverPeripherals()
  cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  if not rsIntegr then
    ui.clear()
    ui.drawHeader("Farm Controller", "Setup Required")
    local w = select(1, term.getSize())
    local msg = {
      "No Redstone Integrator found!",
      "",
      "Craft a Redstone Integrator from",
      "Advanced Peripherals and place it",
      "adjacent to this computer.",
      "",
      "It lets this program control redstone",
      "outputs on its 6 sides independently,",
      "perfect for toggling farm power.",
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
      { label = "Farm Status",     description = #cfg.farms .. " farms" },
      { label = "Add Farm",        description = "New redstone-controlled farm" },
      { label = "Edit Farm",       description = "Modify farm settings" },
      { label = "Manual Controls", description = "Toggle farms manually" },
      { label = "Start Auto Mode", description = "Monitor & auto-control" },
      { label = "< Back to Hub",   description = "" },
    }

    local idx = ui.drawMenu(items, "Farm Controller")
    if not idx or idx == 6 then running = false; break end

    if idx == 1 then drawFarmStatus()
    elseif idx == 2 then addFarm()
    elseif idx == 3 then editFarm()
    elseif idx == 4 then manualControls()
    elseif idx == 5 then startAutoMode()
    end

    discoverPeripherals()
  end
end

main()
