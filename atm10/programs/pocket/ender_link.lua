-- ender_link.lua
-- ATM10 Ender Chest Frequency Manager
-- Device: Pocket Computer / Advanced Pocket Computer
-- Required: None (offline reference tool)
--
-- Manage and view your ender chest color-code frequencies.
-- Never forget what [Orange/White/Purple] goes to again.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local ui     = require("ui")
local config = require("config")

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────
local CFG_FILE = "ender_link.cfg"
local DEFAULTS = {
  frequencies = {},
}

-- ─────────────────────────────────────────────
-- Color data
-- ─────────────────────────────────────────────
local DYE_COLORS = {
  { name = "White",       abbr = "W",  code = colors and colors.white      or nil },
  { name = "Orange",      abbr = "O",  code = colors and colors.orange     or nil },
  { name = "Magenta",     abbr = "M",  code = colors and colors.magenta    or nil },
  { name = "Light Blue",  abbr = "LB", code = colors and colors.lightBlue  or nil },
  { name = "Yellow",      abbr = "Y",  code = colors and colors.yellow     or nil },
  { name = "Lime",        abbr = "L",  code = colors and colors.lime       or nil },
  { name = "Pink",        abbr = "P",  code = colors and colors.pink       or nil },
  { name = "Gray",        abbr = "Gy", code = colors and colors.gray       or nil },
  { name = "Light Gray",  abbr = "LG", code = colors and colors.lightGray  or nil },
  { name = "Cyan",        abbr = "C",  code = colors and colors.cyan       or nil },
  { name = "Purple",      abbr = "Pu", code = colors and colors.purple     or nil },
  { name = "Blue",        abbr = "B",  code = colors and colors.blue       or nil },
  { name = "Brown",       abbr = "Br", code = colors and colors.brown      or nil },
  { name = "Green",       abbr = "G",  code = colors and colors.green      or nil },
  { name = "Red",         abbr = "R",  code = colors and colors.red        or nil },
  { name = "Black",       abbr = "Bk", code = colors and colors.black      or nil },
}

local function dyeByName(name)
  for _, d in ipairs(DYE_COLORS) do
    if d.name == name then return d end
  end
  return nil
end

local function abbrFor(colorName)
  local d = dyeByName(colorName)
  return d and d.abbr or "?"
end

-- Format [W/O/M] style code
local function freqCode(freq)
  local t = abbrFor(freq.colors and freq.colors.top    or "?")
  local m = abbrFor(freq.colors and freq.colors.middle or "?")
  local b = abbrFor(freq.colors and freq.colors.bottom or "?")
  return "[" .. t .. "/" .. m .. "/" .. b .. "]"
end

-- ─────────────────────────────────────────────
-- View frequencies
-- ─────────────────────────────────────────────
local function viewFrequencies(cfg)
  if #cfg.frequencies == 0 then
    ui.alert("No frequencies saved yet.\nUse 'Add Frequency' to create one.", "info")
    return
  end

  -- Sort alphabetically
  local sorted = {}
  for i, f in ipairs(cfg.frequencies) do
    table.insert(sorted, { idx = i, freq = f })
  end
  table.sort(sorted, function(a, b)
    return (a.freq.label or ""):lower() < (b.freq.label or ""):lower()
  end)

  while true do
    local w = select(1, term.getSize())
    local items = {}
    for _, entry in ipairs(sorted) do
      local f     = entry.freq
      local code  = freqCode(f)
      local label = code .. " " .. (f.label or "?")
      table.insert(items, {
        label       = label:sub(1, w - 1),
        description = "",
      })
    end
    table.insert(items, { label = "< Back" })

    local idx = ui.drawMenu(items, "Ender Frequencies")
    if not idx or idx > #sorted then return end

    -- Show detail for selected frequency
    local entry = sorted[idx]
    local f     = entry.freq
    local lines = {
      "Frequency: " .. freqCode(f),
      string.rep("-", 26),
      "Label:  " .. (f.label or "?"),
      "",
      "Colors:",
      "  Top:    " .. (f.colors and f.colors.top    or "?"),
      "  Middle: " .. (f.colors and f.colors.middle or "?"),
      "  Bottom: " .. (f.colors and f.colors.bottom or "?"),
    }
    if f.notes and f.notes ~= "" then
      table.insert(lines, "")
      table.insert(lines, "Notes:")
      for _, line in ipairs(ui.wordWrap(f.notes, 24)) do
        table.insert(lines, "  " .. line)
      end
    end
    table.insert(lines, "")
    table.insert(lines, "[Q] Back  [D] Delete")

    ui.pager(lines, f.label or "Frequency")

    -- Ask if user wants to delete (handled by Q-back from pager)
  end
end

-- ─────────────────────────────────────────────
-- Color picker
-- ─────────────────────────────────────────────
local function pickColor(prompt)
  local items = {}
  for _, d in ipairs(DYE_COLORS) do
    table.insert(items, { label = d.name, description = d.abbr })
  end
  table.insert(items, { label = "< Cancel" })

  local idx = ui.drawMenu(items, prompt)
  if not idx or idx > #DYE_COLORS then return nil end
  return DYE_COLORS[idx].name
end

-- ─────────────────────────────────────────────
-- Add frequency
-- ─────────────────────────────────────────────
local function addFrequency(cfg)
  -- Step 1: label
  local label = ui.inputText("Label (e.g. 'Main Storage AE2'): ")
  if not label or label == "" then return end

  -- Step 2: pick 3 colors
  local topColor = pickColor("Top color (slot 1 of chest)")
  if not topColor then return end
  local midColor = pickColor("Middle color (slot 2)")
  if not midColor then return end
  local botColor = pickColor("Bottom color (slot 3)")
  if not botColor then return end

  -- Step 3: optional notes
  local notes = ui.inputText("Notes (optional, press Enter to skip): ")

  table.insert(cfg.frequencies, {
    label  = label,
    colors = { top = topColor, middle = midColor, bottom = botColor },
    notes  = notes or "",
  })
  config.save(CFG_FILE, cfg)

  ui.alert(
    "Frequency saved!\n" ..
    freqCode({ colors = { top=topColor, middle=midColor, bottom=botColor } }) ..
    " = " .. label,
    "success"
  )
end

-- ─────────────────────────────────────────────
-- Delete frequency
-- ─────────────────────────────────────────────
local function deleteFrequency(cfg)
  if #cfg.frequencies == 0 then
    ui.alert("No frequencies to delete.", "info")
    return
  end

  local items = {}
  for _, f in ipairs(cfg.frequencies) do
    table.insert(items, { label = freqCode(f) .. " " .. (f.label or "?") })
  end
  table.insert(items, { label = "< Cancel" })

  local idx = ui.drawMenu(items, "Delete Frequency")
  if not idx or idx > #cfg.frequencies then return end

  if ui.confirm("Delete '" .. (cfg.frequencies[idx].label or "?") .. "'?") then
    table.remove(cfg.frequencies, idx)
    config.save(CFG_FILE, cfg)
    ui.alert("Frequency deleted.", "success")
  end
end

-- ─────────────────────────────────────────────
-- Search frequencies
-- ─────────────────────────────────────────────
local function searchFrequencies(cfg)
  local query = ui.inputText("Search label: ")
  if not query or query == "" then return end
  query = query:lower()

  local found = {}
  for _, f in ipairs(cfg.frequencies) do
    if (f.label or ""):lower():find(query, 1, true) then
      table.insert(found, f)
    end
  end

  if #found == 0 then
    ui.alert("No frequencies matching '" .. query .. "'", "info")
    return
  end

  local lines = {
    "Results for: " .. query,
    string.rep("-", 26),
    "",
  }
  for _, f in ipairs(found) do
    table.insert(lines, freqCode(f) .. " " .. (f.label or "?"))
    if f.notes and f.notes ~= "" then
      table.insert(lines, "  " .. f.notes:sub(1, 24))
    end
    table.insert(lines, "")
  end
  table.insert(lines, "Press Q to return.")
  ui.pager(lines, "Search Results")
end

-- ─────────────────────────────────────────────
-- Color reference guide
-- ─────────────────────────────────────────────
local function colorGuide()
  local lines = {
    "Ender Chest Color Guide",
    string.rep("=", 26),
    "",
    "Minecraft dye colors used in",
    "ender chest frequencies:",
    "",
  }
  for _, d in ipairs(DYE_COLORS) do
    table.insert(lines, string.format("%-4s = %s", d.abbr, d.name))
  end
  table.insert(lines, "")
  table.insert(lines, "Abbreviations used in codes:")
  table.insert(lines, "[Top/Middle/Bottom]")
  table.insert(lines, "")
  table.insert(lines, "Example:")
  table.insert(lines, "[W/O/M] = White top, Orange")
  table.insert(lines, "          middle, Magenta bottom")
  table.insert(lines, "")
  table.insert(lines, "Frequencies are set by placing")
  table.insert(lines, "dye items in the chest slots.")
  table.insert(lines, "")
  table.insert(lines, "Press Q to return.")
  ui.pager(lines, "Color Guide")
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  local cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  local running = true
  while running do
    local items = {
      { label = "View Frequencies",  description = #cfg.frequencies .. " saved" },
      { label = "Add Frequency",     description = "new color code" },
      { label = "Delete Frequency",  description = "" },
      { label = "Search",            description = "find by label" },
      { label = "Color Guide",       description = "abbreviation ref" },
      { label = "< Back to Hub",     description = "" },
    }

    local idx = ui.drawMenu(items, "Ender Link")
    if not idx or idx == 6 then running = false; break end

    if idx == 1 then viewFrequencies(cfg)
    elseif idx == 2 then addFrequency(cfg)
    elseif idx == 3 then deleteFrequency(cfg)
    elseif idx == 4 then searchFrequencies(cfg)
    elseif idx == 5 then colorGuide()
    end
  end
end

main()
