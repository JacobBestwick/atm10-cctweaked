-- geo_scanner.lua
-- ATM10 Geo Scanner
-- Device: Pocket Computer / Advanced Pocket Computer
-- Required: geoScanner (Advanced Peripherals) attached to pocket computer
--           OR accessible via wireless modem on a nearby computer
--
-- Scans underground for ores and minerals.
-- Shows counts, directions, and lets you filter by ore type.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local ui     = require("ui")
local config = require("config")

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────
local CFG_FILE = "geo_scanner.cfg"
local DEFAULTS = {
  scanRadius   = 8,    -- 1-16; larger = more FE cost
  filterMode   = "ores",  -- "ores", "all", "custom"
  customFilter = {},
  sortBy       = "count",  -- "count", "name"
  showCoords   = false,
}

-- ─────────────────────────────────────────────
-- Known ore/valuable block identifiers
-- (substring matches against block name)
-- ─────────────────────────────────────────────
local ORE_PATTERNS = {
  "ore",          -- catches all *_ore blocks
  "quartz",       -- nether quartz
  "ancient_debris",
  "amethyst",
  "crystal",      -- certus quartz crystals, fluix
  "gem",
  "raw_",         -- raw ore blocks
  "deepslate",    -- deepslate ore variants
  "osmium",
  "tin",
  "lead",
  "uranium",
  "fluorite",
  "allthemodium",
  "vibranium",
  "unobtainium",
  "apatite",
  "cinnabar",
  "nikolite",
  "ruby",
  "sapphire",
  "peridot",
}

local function isOre(blockName)
  local lower = blockName:lower()
  for _, pat in ipairs(ORE_PATTERNS) do
    if lower:find(pat, 1, true) then return true end
  end
  return false
end

-- Strip mod ID prefix for display: "minecraft:iron_ore" → "iron_ore"
local function shortName(fullName)
  return fullName:match(":(.+)$") or fullName
end

-- ─────────────────────────────────────────────
-- Find geoScanner peripheral
-- ─────────────────────────────────────────────
local function findScanner()
  -- Check all peripheral names (sides + wired network)
  local ok, names = pcall(peripheral.getNames)
  if ok and names then
    for _, name in ipairs(names) do
      if peripheral.getType(name) == "geoScanner" then
        return peripheral.wrap(name), name
      end
    end
  end
  -- Explicit side scan
  for _, side in ipairs({ "top","bottom","left","right","front","back" }) do
    if peripheral.isPresent(side) and peripheral.getType(side) == "geoScanner" then
      return peripheral.wrap(side), side
    end
  end
  return nil, nil
end

-- ─────────────────────────────────────────────
-- Run a scan
-- Returns filtered, sorted block table or nil+err
-- ─────────────────────────────────────────────
local function runScan(scanner, cfg)
  -- Show scanning screen
  ui.clear()
  ui.drawHeader("Geo Scanner", "Scanning r=" .. cfg.scanRadius)
  if term.isColor() then term.setTextColor(colors.yellow) end
  ui.writeCentered(4, "Scanning " .. (cfg.scanRadius*2+1) .. "^3 area...")
  ui.writeCentered(5, "This uses FE from the scanner.")
  if term.isColor() then term.setTextColor(colors.white) end

  local ok, result = pcall(function()
    return scanner.scan(cfg.scanRadius)
  end)

  if not ok then
    return nil, tostring(result)
  end

  if type(result) ~= "table" then
    return nil, "unexpected response from geoScanner"
  end

  -- result is a list of { x, y, z, name } entries
  -- Aggregate by block name
  local counts = {}
  local samples = {}  -- store one x,y,z per block type

  for _, entry in ipairs(result) do
    local name = entry.name or "unknown"

    -- Apply filter
    if cfg.filterMode == "ores" then
      if not isOre(name) then goto continue end
    elseif cfg.filterMode == "custom" and #cfg.customFilter > 0 then
      local match = false
      for _, f in ipairs(cfg.customFilter) do
        if name:lower():find(f:lower(), 1, true) then match = true; break end
      end
      if not match then goto continue end
    end

    counts[name] = (counts[name] or 0) + 1
    if not samples[name] then
      samples[name] = { x = entry.x, y = entry.y, z = entry.z }
    end

    ::continue::
  end

  -- Build sorted list
  local list = {}
  for name, count in pairs(counts) do
    table.insert(list, {
      name    = name,
      short   = shortName(name),
      count   = count,
      sample  = samples[name],
    })
  end

  if cfg.sortBy == "count" then
    table.sort(list, function(a, b) return a.count > b.count end)
  else
    table.sort(list, function(a, b) return a.short < b.short end)
  end

  return list, nil
end

-- ─────────────────────────────────────────────
-- Display scan results
-- ─────────────────────────────────────────────
local function showResults(list, cfg, scannerName)
  if #list == 0 then
    local modeStr = cfg.filterMode == "ores" and "No ores found" or "No matching blocks"
    ui.alert(modeStr .. " in radius " .. cfg.scanRadius .. ".\n\nTry increasing the radius\nor switching filter to 'All'.", "info")
    return
  end

  while true do
    local w = select(1, term.getSize())
    local items = {}
    for _, entry in ipairs(list) do
      local label = entry.short:sub(1, w - 8)
      table.insert(items, {
        label       = label,
        description = "x" .. entry.count,
      })
    end
    table.insert(items, { label = "< Back" })

    local subtitle = #list .. " types | r=" .. cfg.scanRadius
    local idx = ui.drawMenu(items, "Scan Results")
    if not idx or idx > #list then return end

    -- Detail view for selected block
    local entry = list[idx]
    local lines = {
      entry.short,
      string.rep("-", 26),
      "Full name:",
      "  " .. entry.name,
      "",
      "Count in scan: " .. entry.count,
      "Scan radius:   " .. cfg.scanRadius,
    }
    if cfg.showCoords and entry.sample then
      table.insert(lines, "")
      table.insert(lines, "Nearest sample:")
      table.insert(lines, string.format("  X%+d Y%+d Z%+d",
        entry.sample.x, entry.sample.y, entry.sample.z))
      table.insert(lines, "(relative to scanner)")
    end
    table.insert(lines, "")
    table.insert(lines, "Press Q to return.")
    ui.pager(lines, entry.short)
  end
end

-- ─────────────────────────────────────────────
-- Quick scan — scan and show immediately
-- ─────────────────────────────────────────────
local function quickScan(scanner, cfg)
  local list, err = runScan(scanner, cfg)
  if not list then
    ui.alert("Scan failed:\n" .. (err or "unknown error") ..
      "\n\nMake sure the scanner has\nenough FE power.", "error")
    return
  end
  showResults(list, cfg, "")
end

-- ─────────────────────────────────────────────
-- Compare two scans
-- ─────────────────────────────────────────────
local function compareScan(scanner, cfg)
  ui.alert("Move to a new location,\nthen press Enter to scan.", "info")

  local listA, err = runScan(scanner, cfg)
  if not listA then
    ui.alert("First scan failed:\n" .. (err or "?"), "error"); return
  end

  local raw = ui.inputText("Move to next spot. Enter to scan: ")

  local listB, err2 = runScan(scanner, cfg)
  if not listB then
    ui.alert("Second scan failed:\n" .. (err2 or "?"), "error"); return
  end

  -- Build count maps
  local mapA, mapB = {}, {}
  for _, e in ipairs(listA) do mapA[e.name] = e.count end
  for _, e in ipairs(listB) do mapB[e.name] = e.count end

  -- Merge keys
  local all = {}
  for k in pairs(mapA) do all[k] = true end
  for k in pairs(mapB) do all[k] = true end

  local lines = {
    "Scan Comparison",
    string.rep("-", 26),
    string.format("%-18s %4s %4s", "Block", "A", "B"),
    string.rep("-", 26),
  }
  for name in pairs(all) do
    local a = mapA[name] or 0
    local b = mapB[name] or 0
    local short = shortName(name):sub(1, 18)
    table.insert(lines, string.format("%-18s %4d %4d", short, a, b))
  end
  table.insert(lines, "")
  table.insert(lines, "Press Q to return.")
  ui.pager(lines, "Comparison")
end

-- ─────────────────────────────────────────────
-- Settings
-- ─────────────────────────────────────────────
local function showSettings(cfg)
  while true do
    local items = {
      { label = "Scan Radius: " .. cfg.scanRadius,    description = "1-16 (higher = more FE)" },
      { label = "Filter: " .. cfg.filterMode,          description = "ores / all / custom" },
      { label = "Sort by: " .. cfg.sortBy,             description = "count / name" },
      { label = "Show coords: " .. (cfg.showCoords and "yes" or "no") },
      { label = "< Back" },
    }
    local idx = ui.drawMenu(items, "Scanner Settings")
    if not idx or idx == 5 then return end

    if idx == 1 then
      local raw = ui.inputText("Radius (1-16): ", tostring(cfg.scanRadius))
      local v = tonumber(raw)
      if v and v >= 1 and v <= 16 then
        cfg.scanRadius = math.floor(v)
        config.save(CFG_FILE, cfg)
      else
        ui.alert("Enter a number 1-16.", "warn")
      end

    elseif idx == 2 then
      local modes = { { label = "ores  — only ore blocks" },
                      { label = "all   — everything scanned" },
                      { label = "custom — your keywords" },
                      { label = "< Cancel" } }
      local midx = ui.drawMenu(modes, "Filter Mode")
      if midx == 1 then cfg.filterMode = "ores"
      elseif midx == 2 then cfg.filterMode = "all"
      elseif midx == 3 then
        cfg.filterMode = "custom"
        local raw = ui.inputText("Keywords (comma separated): ")
        if raw and raw ~= "" then
          cfg.customFilter = {}
          for word in raw:gmatch("[^,]+") do
            local trimmed = word:match("^%s*(.-)%s*$")
            if trimmed ~= "" then table.insert(cfg.customFilter, trimmed) end
          end
        end
      end
      config.save(CFG_FILE, cfg)

    elseif idx == 3 then
      cfg.sortBy = cfg.sortBy == "count" and "name" or "count"
      config.save(CFG_FILE, cfg)

    elseif idx == 4 then
      cfg.showCoords = not cfg.showCoords
      config.save(CFG_FILE, cfg)
    end
  end
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  local scanner, scannerName = findScanner()

  if not scanner then
    ui.alert(
      "No Geo Scanner found!\n\n" ..
      "Attach a Geo Scanner from\n" ..
      "Advanced Peripherals to your\n" ..
      "pocket computer, or connect\n" ..
      "one via a wired modem.\n\n" ..
      "The scanner also needs FE\n" ..
      "power to operate.",
      "error"
    )
    return
  end

  local cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  local running = true
  while running do
    local items = {
      { label = "Quick Scan",      description = "r=" .. cfg.scanRadius .. " | " .. cfg.filterMode },
      { label = "Compare Scans",   description = "diff two positions" },
      { label = "Settings",        description = "radius, filter, sort" },
      { label = "< Back to Hub",   description = "" },
    }

    local idx = ui.drawMenu(items, "Geo Scanner")
    if not idx or idx == 4 then running = false; break end

    if idx == 1 then
      quickScan(scanner, cfg)
    elseif idx == 2 then
      compareScan(scanner, cfg)
    elseif idx == 3 then
      showSettings(cfg)
    end
  end
end

main()
