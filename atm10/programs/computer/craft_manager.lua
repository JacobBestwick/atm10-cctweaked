-- craft_manager.lua
-- ATM10 Autocrafting Queue Manager
-- Device: Computer / Advanced Computer
-- Required: meBridge OR rsBridge (Advanced Peripherals)
-- Optional: monitor
--
-- Monitors your AE2/RS storage and auto-requests crafting when
-- items fall below target quantities. Supports profiles for different
-- ATM10 progression stages.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local detect  = require("detect")
local ui      = require("ui")
local config  = require("config")
local storage = require("storage")

-- ─────────────────────────────────────────────
-- Constants
-- ─────────────────────────────────────────────
local CFG_FILE = "craft_manager.cfg"
local LOG_FILE = "craft_manager_log.txt"

local DEFAULTS = {
  checkInterval = 30,
  rules         = {},
  activeProfile = "custom",
}

-- Built-in profiles
local BUILTIN_PROFILES = {
  {
    name  = "Early Game",
    key   = "earlyGame",
    rules = {
      { name = "minecraft:iron_ingot",   displayName = "Iron Ingot",   targetCount = 256 },
      { name = "minecraft:gold_ingot",   displayName = "Gold Ingot",   targetCount = 128 },
      { name = "minecraft:copper_ingot", displayName = "Copper Ingot", targetCount = 256 },
      { name = "minecraft:redstone",     displayName = "Redstone",     targetCount = 256 },
      { name = "minecraft:glass",        displayName = "Glass",        targetCount = 256 },
    },
  },
  {
    name  = "Mekanism Setup",
    key   = "mekaSetup",
    rules = {
      { name = "mekanism:steel_casing",          displayName = "Steel Casing",          targetCount = 64  },
      { name = "mekanism:basic_control_circuit", displayName = "Basic Control Circuit", targetCount = 32  },
      { name = "mekanism:osmium_ingot",          displayName = "Osmium Ingot",          targetCount = 256 },
      { name = "mekanism:steel_ingot",           displayName = "Steel Ingot",           targetCount = 256 },
    },
  },
  {
    name  = "AE2 Expansion",
    key   = "ae2Expansion",
    rules = {
      { name = "ae2:fluix_crystal",           displayName = "Fluix Crystal",      targetCount = 64  },
      { name = "ae2:certus_quartz_dust",      displayName = "Certus Quartz Dust", targetCount = 128 },
      { name = "ae2:item_storage_cell_1k",    displayName = "1k Cell",            targetCount = 8   },
      { name = "ae2:item_storage_cell_4k",    displayName = "4k Cell",            targetCount = 4   },
    },
  },
  {
    name  = "ATM Star Prep",
    key   = "atmStarPrep",
    rules = {
      { name = "allthemodium:allthemodium_ingot", displayName = "Allthemodium Ingot", targetCount = 64 },
      { name = "allthemodium:vibranium_ingot",    displayName = "Vibranium Ingot",    targetCount = 64 },
      { name = "allthemodium:unobtainium_ingot",  displayName = "Unobtainium Ingot",  targetCount = 32 },
    },
  },
}

-- ─────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────
local cfg     = {}
local running = true

-- ─────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────
local function checkStorage()
  if not storage.isAvailable() then
    local ok, _ = storage.init()
    if not ok then return false end
  end
  return storage.isAvailable()
end

-- Get current count of an item, returns 0 if unavailable
local function getCurrentCount(itemName)
  local item = storage.getItem(itemName)
  if item then return item.count end
  return 0
end

-- ─────────────────────────────────────────────
-- View rules screen
-- ─────────────────────────────────────────────
local function viewRules()
  if #cfg.rules == 0 then
    ui.alert("No stock rules defined.\nUse 'Add Rule' to create some.", "info")
    return
  end

  while true do
    local hasStorage = checkStorage()
    local w, h = term.getSize()

    ui.clear()
    ui.drawHeader("Craft Manager", "Stock Rules")

    -- Draw table header
    local row = 3
    ui.setColor(colors.gray, colors.black)
    term.setCursorPos(1, row)
    local header = string.format("%-22s %7s %7s %-8s", "Item", "Target", "Current", "Status")
    term.write(header:sub(1, w))
    row = row + 1
    ui.resetColor()

    local scrollStart = 1
    local maxVisible  = h - row - 1

    for i = scrollStart, math.min(#cfg.rules, scrollStart + maxVisible - 1) do
      local rule    = cfg.rules[i]
      local current = hasStorage and getCurrentCount(rule.name) or -1
      local status  = "?"

      if current >= 0 then
        if current >= rule.targetCount then
          status = "OK"
          ui.setColor(colors.lime, colors.black)
        elseif current > 0 then
          status = "LOW"
          ui.setColor(colors.yellow, colors.black)
        else
          status = "EMPTY"
          ui.setColor(colors.red, colors.black)
        end
      else
        ui.setColor(colors.gray, colors.black)
        status = "N/A"
      end

      local name = (rule.displayName or rule.name):sub(1, 21)
      local line = string.format("%-22s %7d %7s %-8s",
        name,
        rule.targetCount,
        current >= 0 and tostring(current) or "?",
        status
      )
      term.setCursorPos(1, row)
      term.write(line:sub(1, w))
      row = row + 1
      ui.resetColor()
    end

    if not hasStorage then
      ui.setColor(colors.yellow, colors.black)
      term.setCursorPos(1, h - 2)
      term.write("No storage bridge — counts unavailable")
      ui.resetColor()
    end

    ui.drawFooter("[Q] Back  [R] Refresh")
    local _, key = os.pullEvent("key")
    if key == keys.q or key == keys.backspace then return end
    -- R = refresh (just loop again)
  end
end

-- ─────────────────────────────────────────────
-- Add rule
-- ─────────────────────────────────────────────
local function addRule()
  ui.clear()
  ui.drawHeader("Craft Manager", "Add Rule")

  -- Search storage for item
  local query = ui.inputText("Search item name (or full ID): ")
  if not query or query == "" then return end

  local found = nil
  if checkStorage() then
    local results = storage.searchItems(query)
    if #results == 0 then
      ui.alert("No items matching '" .. query .. "' found in storage.\nYou can still add it manually.", "warn")
    elseif #results == 1 then
      found = results[1]
    else
      -- Let user pick
      local items = {}
      for _, r in ipairs(results) do
        table.insert(items, { label = r.displayName, description = r.name })
      end
      table.insert(items, { label = "< Cancel" })
      local idx = ui.drawMenu(items, "Select Item")
      if not idx or idx > #results then return end
      found = results[idx]
    end
  end

  -- Get item name to use
  local itemName
  local displayName
  if found then
    itemName    = found.name
    displayName = found.displayName
  else
    itemName    = query
    displayName = query
  end

  -- Get target count
  local rawTarget = ui.inputText("Target count for " .. displayName .. ": ")
  local target    = tonumber(rawTarget)
  if not target or target < 1 then
    ui.alert("Invalid count. Must be a positive number.", "warn")
    return
  end

  -- Check for duplicate
  for _, r in ipairs(cfg.rules) do
    if r.name == itemName then
      ui.alert("Rule for " .. displayName .. " already exists.\nEdit or remove the existing rule.", "warn")
      return
    end
  end

  table.insert(cfg.rules, {
    name        = itemName,
    displayName = displayName,
    targetCount = math.floor(target),
    profile     = "custom",
  })
  config.save(CFG_FILE, cfg)
  ui.alert("Rule added: " .. displayName .. " x" .. math.floor(target), "success")
end

-- ─────────────────────────────────────────────
-- Remove rule
-- ─────────────────────────────────────────────
local function removeRule()
  if #cfg.rules == 0 then
    ui.alert("No rules to remove.", "info")
    return
  end

  local items = {}
  for _, r in ipairs(cfg.rules) do
    table.insert(items, { label = r.displayName or r.name, description = "target: " .. r.targetCount })
  end
  table.insert(items, { label = "< Cancel" })

  local idx = ui.drawMenu(items, "Remove Rule")
  if not idx or idx > #cfg.rules then return end

  local rule = cfg.rules[idx]
  if ui.confirm("Remove rule for " .. (rule.displayName or rule.name) .. "?") then
    table.remove(cfg.rules, idx)
    config.save(CFG_FILE, cfg)
    ui.alert("Rule removed.", "success")
  end
end

-- ─────────────────────────────────────────────
-- Live monitoring loop
-- ─────────────────────────────────────────────
local function startMonitoring()
  if not checkStorage() then
    ui.alert("No AE2 ME Bridge or RS Bridge found.\nAttach one to use auto-crafting.", "error")
    return
  end

  if #cfg.rules == 0 then
    ui.alert("No stock rules configured.\nAdd rules first.", "warn")
    return
  end

  local monRunning = true
  local timerId    = os.startTimer(1)  -- first check quickly
  local lastCheck  = 0
  local craftCount = 0

  local function doCheck()
    lastCheck = os.clock()
    local w, h = term.getSize()

    ui.clear()
    ui.drawHeader("Craft Manager", "Monitoring")

    local row = 3
    ui.setColor(colors.cyan, colors.black)
    term.setCursorPos(1, row)
    term.write("Auto-crafting monitor running...")
    row = row + 2
    ui.resetColor()

    -- Check each rule
    for _, rule in ipairs(cfg.rules) do
      if row >= h - 2 then break end

      local current = getCurrentCount(rule.name)
      local needed  = rule.targetCount - current

      local statusColor = colors.lime
      local statusStr   = "OK"

      if needed > 0 then
        statusColor = colors.yellow
        statusStr   = "LOW  craft +" .. needed

        -- Request crafting
        local item = storage.getItem(rule.name)
        if item and item.craftable then
          local ok, msg = storage.craftItem(rule.name, needed)
          if ok then
            statusColor = colors.cyan
            statusStr   = "CRAFTING +" .. needed
            config.appendLog(LOG_FILE, "Craft requested: " .. rule.name .. " x" .. needed)
            craftCount  = craftCount + 1
          else
            statusColor = colors.red
            statusStr   = "ERR:" .. (msg or "?"):sub(1, 12)
          end
        else
          statusColor = colors.orange
          statusStr   = "NOT CRAFTABLE"
        end
      end

      local name = (rule.displayName or rule.name):sub(1, 20)
      ui.setColor(statusColor, colors.black)
      term.setCursorPos(1, row)
      term.write(string.format("%-21s %6d/%-6d %s", name, current, rule.targetCount, statusStr):sub(1, w))
      row = row + 1
      ui.resetColor()
    end

    row = row + 1
    ui.setColor(colors.lightGray, colors.black)
    term.setCursorPos(1, row)
    term.write("Crafts requested this session: " .. craftCount)
    term.setCursorPos(1, row + 1)
    term.write("Next check in " .. cfg.checkInterval .. "s")
    ui.resetColor()

    ui.drawFooter("[Q] Stop monitoring")
  end

  doCheck()

  while monRunning do
    local evt, p1 = os.pullEvent()

    if evt == "timer" and p1 == timerId then
      doCheck()
      timerId = os.startTimer(cfg.checkInterval)

    elseif evt == "key" then
      if p1 == keys.q or p1 == keys.backspace then
        monRunning = false
      end

    elseif evt == "terminate" then
      monRunning = false
    end
  end
end

-- ─────────────────────────────────────────────
-- Profiles
-- ─────────────────────────────────────────────
local function showProfiles()
  local items = {}
  for _, p in ipairs(BUILTIN_PROFILES) do
    table.insert(items, { label = p.name, description = #p.rules .. " rules" })
  end
  table.insert(items, { label = "< Back" })

  local idx = ui.drawMenu(items, "Load Profile")
  if not idx or idx > #BUILTIN_PROFILES then return end

  local profile = BUILTIN_PROFILES[idx]
  if not ui.confirm("Add " .. #profile.rules .. " rules from '" .. profile.name .. "'?") then
    return
  end

  local added = 0
  for _, rule in ipairs(profile.rules) do
    local exists = false
    for _, r in ipairs(cfg.rules) do
      if r.name == rule.name then exists = true; break end
    end
    if not exists then
      table.insert(cfg.rules, {
        name        = rule.name,
        displayName = rule.displayName,
        targetCount = rule.targetCount,
        profile     = profile.key,
      })
      added = added + 1
    end
  end

  config.save(CFG_FILE, cfg)
  ui.alert("Added " .. added .. " rules from '" .. profile.name .. "'.", "success")
end

-- ─────────────────────────────────────────────
-- Crafting queue
-- ─────────────────────────────────────────────
local function showQueue()
  if not checkStorage() then
    ui.alert("No storage bridge connected.", "error")
    return
  end

  local jobs = storage.getCraftingJobs()
  if #jobs == 0 then
    ui.alert("No active crafting jobs.\n(ME Bridge only — RS Bridge does not\nexpose crafting queue info.)", "info")
    return
  end

  local lines = {
    "Active Crafting Jobs",
    string.rep("-", 30),
  }
  for i, job in ipairs(jobs) do
    table.insert(lines, string.format("CPU %d: busy=%s  storage=%d  coProc=%d",
      job.id, tostring(job.busy), job.storage or 0, job.coProcessors or 0))
  end
  table.insert(lines, "")
  table.insert(lines, "Press Q to return.")
  ui.pager(lines, "Crafting Queue")
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  -- Check for storage on startup
  local storOk, storType = storage.init()
  if not storOk then
    ui.clear()
    ui.drawHeader("Craft Manager", "No Storage")
    local w, h = term.getSize()
    local msg = {
      "No AE2 ME Bridge or RS Bridge found!",
      "",
      "This program needs an ME Bridge or RS Bridge",
      "from the Advanced Peripherals mod.",
      "",
      "To fix this:",
      " 1. Craft a ME Bridge or RS Bridge",
      " 2. Place it adjacent to this computer",
      "    OR connect via wired modem network",
      " 3. Re-open Craft Manager",
      "",
      "Press any key to continue anyway...",
    }
    for i, line in ipairs(msg) do
      ui.setColor(i == 1 and colors.red or (i > 4 and i < 10 and colors.white or colors.gray), colors.black)
      term.setCursorPos(2, i + 2)
      term.write(line:sub(1, w - 2))
    end
    ui.resetColor()
    os.pullEvent("key")
  end

  cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  while running do
    local storDesc = storOk and ("[" .. storType:upper() .. "]") or "[NO STORAGE]"
    local items = {
      { label = "View Stock Rules",   description = #cfg.rules .. " rules" },
      { label = "Add Rule",           description = "Track a new item" },
      { label = "Remove Rule",        description = "" },
      { label = "Start Monitoring",   description = "Auto-craft loop" },
      { label = "Load Profile",       description = "Pre-built rule sets" },
      { label = "Crafting Queue",     description = "Active AE2 jobs" },
      { label = "< Back to Hub",      description = "" },
    }

    local idx = ui.drawMenu(items, "Craft Manager " .. storDesc)

    if not idx or idx == 7 then
      running = false
    elseif idx == 1 then viewRules()
    elseif idx == 2 then addRule()
    elseif idx == 3 then removeRule()
    elseif idx == 4 then startMonitoring()
    elseif idx == 5 then showProfiles()
    elseif idx == 6 then showQueue()
    end

    -- Re-init storage in case it changed
    storOk, storType = storage.init()
  end
end

main()
