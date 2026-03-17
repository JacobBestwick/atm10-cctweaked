-- resource_tracker.lua
-- ATM10 Mod Progression Resource Tracker
-- Device: Computer / Advanced Computer
-- Required: None
-- Optional: meBridge or rsBridge (for live item count queries)
--
-- Tracks what items you need for ATM10 progression goals.
-- Works fully offline with manual checkboxes, or queries
-- your AE2/RS storage automatically when connected.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local detect  = require("detect")
local ui      = require("ui")
local config  = require("config")
local storage = require("storage")

-- ─────────────────────────────────────────────
-- Constants
-- ─────────────────────────────────────────────
local CFG_FILE = "resource_tracker.cfg"

local DEFAULTS = {
  goals = {},
}

-- ─────────────────────────────────────────────
-- Built-in templates
-- ─────────────────────────────────────────────
local TEMPLATES = {
  {
    name  = "Mekanism 5x Ore Processing",
    items = {
      { name = "mekanism:chemical_dissolution_chamber", displayName = "Chemical Dissolution Chamber", target = 1 },
      { name = "mekanism:chemical_washer",             displayName = "Chemical Washer",              target = 1 },
      { name = "mekanism:chemical_crystallizer",       displayName = "Chemical Crystallizer",        target = 1 },
      { name = "mekanism:chemical_injection_chamber",  displayName = "Chemical Injection Chamber",   target = 1 },
      { name = "mekanism:purification_chamber",        displayName = "Purification Chamber",         target = 1 },
      { name = "mekanism:crusher",                     displayName = "Crusher",                      target = 1 },
      { name = "mekanism:enrichment_chamber",          displayName = "Enrichment Chamber",           target = 1 },
      { name = "mekanism:energized_smelter",           displayName = "Energized Smelter",            target = 1 },
      { name = "mekanism:osmium_compressor",           displayName = "Osmium Compressor",            target = 1 },
      { name = "mekanism:chemical_infuser",            displayName = "Chemical Infuser",             target = 1 },
      { name = "mekanism:steel_casing",                displayName = "Steel Casing",                 target = 32 },
      { name = "mekanism:basic_control_circuit",       displayName = "Basic Control Circuit",        target = 32 },
    },
  },
  {
    name  = "AE2 Network Setup",
    items = {
      { name = "ae2:me_controller",         displayName = "ME Controller",       target = 1   },
      { name = "ae2:energy_acceptor",       displayName = "Energy Acceptor",     target = 1   },
      { name = "ae2:drive",                 displayName = "ME Drive",            target = 2   },
      { name = "ae2:terminal",              displayName = "ME Terminal",         target = 1   },
      { name = "ae2:crafting_terminal",     displayName = "Crafting Terminal",   target = 1   },
      { name = "ae2:fluix_crystal",         displayName = "Fluix Crystal",       target = 64  },
      { name = "ae2:item_storage_cell_4k",  displayName = "4k Storage Cell",     target = 4   },
      { name = "ae2:item_storage_cell_16k", displayName = "16k Storage Cell",    target = 4   },
      { name = "ae2:molecular_assembler",   displayName = "Molecular Assembler", target = 4   },
      { name = "ae2:crafting_storage_1k",   displayName = "1k Crafting Storage", target = 1   },
    },
  },
  {
    name  = "ATM Star Components",
    items = {
      { name = "allthemodium:allthemodium_ingot",  displayName = "Allthemodium Ingot",  target = 64 },
      { name = "allthemodium:vibranium_ingot",     displayName = "Vibranium Ingot",     target = 64 },
      { name = "allthemodium:unobtainium_ingot",   displayName = "Unobtainium Ingot",   target = 32 },
      { name = "minecraft:nether_star",            displayName = "Nether Star",         target = 1  },
      { name = "minecraft:dragon_egg",             displayName = "Dragon Egg",          target = 1  },
      { name = "mekanism:hdpe_pellet",             displayName = "HDPE Pellet",         target = 64 },
      { name = "ae2:singularity",                  displayName = "Singularity",         target = 1  },
    },
  },
  {
    name  = "Botania Terrasteel",
    items = {
      { name = "botania:manasteel_ingot",  displayName = "Manasteel Ingot",  target = 9  },
      { name = "botania:mana_pearl",       displayName = "Mana Pearl",       target = 9  },
      { name = "botania:mana_diamond",     displayName = "Mana Diamond",     target = 9  },
      { name = "botania:livingwood_log",   displayName = "Livingwood Log",   target = 16 },
      { name = "botania:livingrock",       displayName = "Livingrock",       target = 16 },
      { name = "botania:mana_pool",        displayName = "Mana Pool",        target = 1  },
      { name = "botania:terrestrial_agglomeration_plate", displayName = "Terrestrial Agglomeration Plate", target = 1 },
    },
  },
  {
    name  = "Create Mechanical Crafting",
    items = {
      { name = "create:brass_casing",            displayName = "Brass Casing",           target = 8  },
      { name = "create:mechanical_bearing",      displayName = "Mechanical Bearing",     target = 4  },
      { name = "create:gearbox",                 displayName = "Gearbox",                target = 4  },
      { name = "create:large_cogwheel",          displayName = "Large Cogwheel",         target = 8  },
      { name = "create:cogwheel",                displayName = "Cogwheel",               target = 8  },
      { name = "create:mechanical_press",        displayName = "Mechanical Press",       target = 1  },
      { name = "create:mechanical_mixer",        displayName = "Mechanical Mixer",       target = 1  },
      { name = "create:basin",                   displayName = "Basin",                  target = 2  },
    },
  },
  {
    name  = "Powah Reactor (Starter)",
    items = {
      { name = "powah:reactor_part_starter",      displayName = "Reactor Part (Starter)", target = 8   },
      { name = "powah:reactor_controller_starter",displayName = "Reactor Controller",     target = 1   },
      { name = "powah:reactor_cell_starter",      displayName = "Reactor Cell",           target = 1   },
      { name = "powah:dielectric_cryotheum",      displayName = "Dielectric Cryotheum",   target = 4   },
      { name = "powah:dry_ice",                   displayName = "Dry Ice",                target = 4   },
      { name = "minecraft:uranium",               displayName = "Uranium",                target = 16  },
      { name = "powah:energizing_orb",            displayName = "Energizing Orb",        target = 1   },
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
local function goalProgress(goal)
  local total   = #goal.items
  local obtained = 0
  for _, item in ipairs(goal.items) do
    if item.obtained then obtained = obtained + 1 end
  end
  return obtained, total
end

local function saveGoals()
  config.save(CFG_FILE, cfg)
end

-- ─────────────────────────────────────────────
-- View a single goal
-- ─────────────────────────────────────────────
local function viewGoal(goalIdx)
  local goal       = cfg.goals[goalIdx]
  local hasStorage = storage.isAvailable()

  while true do
    -- Query storage for current counts
    local counts = {}
    if hasStorage then
      for _, item in ipairs(goal.items) do
        local found = storage.getItem(item.name)
        counts[item.name] = found and found.count or 0
      end
    end

    local obtained, total = goalProgress(goal)
    local pct = total > 0 and math.floor(obtained / total * 100) or 0

    ui.clear()
    ui.drawHeader("Resource Tracker", goal.name)

    local w, h = term.getSize()
    local row = 3

    -- Progress bar
    ui.drawProgressBar(1, row, w, pct, colors.lime, colors.gray,
      obtained .. "/" .. total .. " items ready  " .. pct .. "%")
    row = row + 2

    -- Items list (scrollable via menu)
    local items = {}
    for i, item in ipairs(goal.items) do
      local current = counts[item.name]
      local status  = item.obtained and "[DONE]" or "[    ]"

      if current and current >= item.target then
        status = "[DONE]"
        -- Auto-mark obtained if in storage
        if not item.obtained then
          goal.items[i].obtained = true
          saveGoals()
        end
      end

      local label = status .. " " .. (item.displayName or item.name):sub(1, 22)
      local desc  = current ~= nil
        and (current .. "/" .. item.target)
        or ("0/" .. item.target)

      table.insert(items, {
        label       = label,
        description = desc,
        enabled     = true,
      })
    end
    table.insert(items, { label = "Query Storage",    description = hasStorage and "refresh" or "no bridge" })
    table.insert(items, { label = "Delete This Goal", description = "" })
    table.insert(items, { label = "< Back",           description = "" })

    local idx = ui.drawMenu(items, goal.name .. " (" .. pct .. "%)")
    if not idx or idx == #items then return end

    if idx == #items - 2 then
      -- Query storage
      if not hasStorage then
        local ok, _ = storage.init()
        hasStorage  = storage.isAvailable()
        if not hasStorage then
          ui.alert("No storage bridge connected.\nCounts unavailable.", "warn")
        end
      end
      -- loop continues and re-queries

    elseif idx == #items - 1 then
      -- Delete goal
      if ui.confirm("Delete goal '" .. goal.name .. "'?") then
        table.remove(cfg.goals, goalIdx)
        saveGoals()
        return
      end

    else
      -- Toggle obtained for this item
      goal.items[idx].obtained = not goal.items[idx].obtained
      saveGoals()
    end
  end
end

-- ─────────────────────────────────────────────
-- Goals list
-- ─────────────────────────────────────────────
local function viewGoals()
  while true do
    if #cfg.goals == 0 then
      ui.alert("No goals yet.\nUse 'New Goal' or load a template.", "info")
      return
    end

    local items = {}
    for _, goal in ipairs(cfg.goals) do
      local obt, total = goalProgress(goal)
      local pct = total > 0 and math.floor(obt / total * 100) or 0
      table.insert(items, {
        label       = goal.name,
        description = obt .. "/" .. total .. " (" .. pct .. "%)",
      })
    end
    table.insert(items, { label = "< Back" })

    local idx = ui.drawMenu(items, "Your Goals")
    if not idx or idx == #items then return end

    viewGoal(idx)
  end
end

-- ─────────────────────────────────────────────
-- New goal
-- ─────────────────────────────────────────────
local function newGoal()
  local name = ui.inputText("Goal name (e.g. 'Get Jetpack'): ")
  if not name or name == "" then return end

  local goal = { name = name, items = {} }
  table.insert(cfg.goals, goal)
  saveGoals()

  ui.alert("Goal '" .. name .. "' created!\nNow add items to it.", "success")

  -- Immediately let them add items
  local goalIdx = #cfg.goals
  while true do
    local raw = ui.inputText("Add item name (blank to finish): ")
    if not raw or raw == "" then break end

    local displayName = raw
    local targetCount = 1

    -- Try to find in storage
    if storage.isAvailable() then
      local found = storage.searchItems(raw)
      if #found > 0 then
        displayName = found[1].displayName
        raw         = found[1].name
      end
    end

    local rawCount = ui.inputText("Target count for " .. displayName .. ": ", "1")
    targetCount    = tonumber(rawCount) or 1

    table.insert(cfg.goals[goalIdx].items, {
      name        = raw,
      displayName = displayName,
      target      = math.max(1, math.floor(targetCount)),
      obtained    = false,
    })
    saveGoals()
  end
end

-- ─────────────────────────────────────────────
-- Templates
-- ─────────────────────────────────────────────
local function loadTemplate()
  local items = {}
  for _, t in ipairs(TEMPLATES) do
    table.insert(items, { label = t.name, description = #t.items .. " items" })
  end
  table.insert(items, { label = "< Cancel" })

  local idx = ui.drawMenu(items, "Load Template")
  if not idx or idx > #TEMPLATES then return end

  local tmpl = TEMPLATES[idx]

  -- Check if goal already exists
  for _, g in ipairs(cfg.goals) do
    if g.name == tmpl.name then
      ui.alert("Goal '" .. tmpl.name .. "' already exists.", "warn")
      return
    end
  end

  local goal = { name = tmpl.name, items = {} }
  for _, item in ipairs(tmpl.items) do
    table.insert(goal.items, {
      name        = item.name,
      displayName = item.displayName,
      target      = item.target,
      obtained    = false,
    })
  end
  table.insert(cfg.goals, goal)
  saveGoals()
  ui.alert("Template '" .. tmpl.name .. "' loaded!\n" .. #tmpl.items .. " items added.", "success")
end

-- ─────────────────────────────────────────────
-- Query storage for all goals
-- ─────────────────────────────────────────────
local function queryAll()
  local ok, _ = storage.init()
  if not storage.isAvailable() then
    ui.alert("No AE2/RS storage bridge connected.", "error")
    return
  end

  ui.clear()
  ui.drawHeader("Resource Tracker", "Querying Storage...")
  term.setCursorPos(1, 3)
  print("Fetching item counts from storage...")

  local updated = 0
  for gi, goal in ipairs(cfg.goals) do
    for ii, item in ipairs(goal.items) do
      local found = storage.getItem(item.name)
      if found and found.count >= item.target then
        cfg.goals[gi].items[ii].obtained = true
        updated = updated + 1
      end
    end
  end
  saveGoals()
  ui.alert("Storage queried!\n" .. updated .. " items auto-marked as obtained.", "success")
end

-- ─────────────────────────────────────────────
-- Export report
-- ─────────────────────────────────────────────
local function exportReport()
  local reportPath = "/atm10/data/progression_report.txt"
  local lines = {
    "ATM10 Progression Report",
    os.date and os.date("Generated: %Y-%m-%d") or "Generated",
    string.rep("=", 40),
    "",
  }

  for _, goal in ipairs(cfg.goals) do
    local obt, total = goalProgress(goal)
    local pct = total > 0 and math.floor(obt / total * 100) or 0
    table.insert(lines, goal.name .. "  (" .. obt .. "/" .. total .. " = " .. pct .. "%)")
    table.insert(lines, string.rep("-", 38))
    for _, item in ipairs(goal.items) do
      local check = item.obtained and "[x]" or "[ ]"
      table.insert(lines, string.format("  %s %-30s x%d", check, item.displayName or item.name, item.target))
    end
    table.insert(lines, "")
  end

  local f = fs.open(reportPath, "w")
  if f then
    for _, line in ipairs(lines) do f.writeLine(line) end
    f.close()
    ui.alert("Report written to:\n" .. reportPath, "success")
  else
    ui.alert("Could not write report file.", "error")
  end
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  cfg = config.getOrDefault(CFG_FILE, DEFAULTS)
  storage.init()

  while running do
    local storStatus = storage.isAvailable() and ("[" .. storage.getType():upper() .. "]") or "[no storage]"
    local items = {
      { label = "View Goals",       description = #cfg.goals .. " goals" },
      { label = "New Goal",         description = "Create custom goal" },
      { label = "Load Template",    description = "ATM10 pre-built goals" },
      { label = "Query Storage",    description = storStatus },
      { label = "Export Report",    description = "Write .txt file" },
      { label = "< Back to Hub",    description = "" },
    }

    local idx = ui.drawMenu(items, "Resource Tracker")
    if not idx or idx == 6 then running = false; break end

    if idx == 1 then viewGoals()
    elseif idx == 2 then newGoal()
    elseif idx == 3 then loadTemplate()
    elseif idx == 4 then queryAll()
    elseif idx == 5 then exportReport()
    end
  end
end

main()
