-- builder_turtle.lua
-- ATM10 Structure Builder from Blueprints
-- Device: Turtle / Advanced Turtle
-- Required: Turtle (building)
-- Optional: blockReader (placement validation)
--
-- Reads blueprint files and builds structures block by block.
-- Blueprints live in /atm10/blueprints/ and use a simple
-- palette + layer format.

local basePath   = "/atm10"
local BLUEPRINT_DIR = basePath .. "/blueprints/"
package.path = basePath .. "/lib/?.lua;" .. package.path
local ui     = require("ui")
local config = require("config")
local detect = require("detect")

-- ─────────────────────────────────────────────
-- Position tracking
-- Facing: 0=north(−z), 1=east(+x), 2=south(+z), 3=west(−x)
-- ─────────────────────────────────────────────
local pos = { x = 0, y = 0, z = 0, f = 0 }

local function updateForward()
  if pos.f == 0 then pos.z = pos.z - 1
  elseif pos.f == 1 then pos.x = pos.x + 1
  elseif pos.f == 2 then pos.z = pos.z + 1
  else pos.x = pos.x - 1 end
end

local function tryForward()
  for i = 1, 3 do
    if turtle.forward() then updateForward(); return true end
    sleep(0.3)
  end
  return false
end

local function tryUp()
  for i = 1, 3 do
    if turtle.up() then pos.y = pos.y + 1; return true end
    sleep(0.3)
  end
  return false
end

local function tryDown()
  for i = 1, 3 do
    if turtle.down() then pos.y = pos.y - 1; return true end
    sleep(0.3)
  end
  return false
end

local function turnLeft()  turtle.turnLeft();  pos.f = (pos.f - 1) % 4 end
local function turnRight() turtle.turnRight(); pos.f = (pos.f + 1) % 4 end

local function faceDir(d)
  local diff = (d - pos.f) % 4
  if diff == 1 then turnRight()
  elseif diff == 2 then turnRight(); turnRight()
  elseif diff == 3 then turnLeft()
  end
end

local function moveToXZ(tx, tz)
  local dx = tx - pos.x
  local dz = tz - pos.z
  if dx > 0 then faceDir(1); for i = 1, dx do tryForward() end
  elseif dx < 0 then faceDir(3); for i = 1, -dx do tryForward() end end
  if dz > 0 then faceDir(2); for i = 1, dz do tryForward() end
  elseif dz < 0 then faceDir(0); for i = 1, -dz do tryForward() end end
end

local function moveToY(ty)
  while pos.y < ty do tryUp() end
  while pos.y > ty do tryDown() end
end

-- ─────────────────────────────────────────────
-- Inventory helpers
-- ─────────────────────────────────────────────
local function findBlockInInventory(blockName)
  for i = 1, 16 do
    local detail = turtle.getItemDetail(i)
    if detail and detail.name == blockName then
      return i
    end
  end
  return nil
end

local function countBlock(blockName)
  local count = 0
  for i = 1, 16 do
    local detail = turtle.getItemDetail(i)
    if detail and detail.name == blockName then
      count = count + detail.count
    end
  end
  return count
end

-- ─────────────────────────────────────────────
-- Load blueprint file
-- ─────────────────────────────────────────────
local function loadBlueprint(path)
  if not fs.exists(path) then return nil, "File not found: " .. path end
  local f = fs.open(path, "r")
  if not f then return nil, "Cannot open: " .. path end
  local content = f.readAll()
  f.close()

  -- Blueprint files start with 'return { ... }' Lua table
  local ok, data = pcall(load, content)
  if not ok then return nil, "Parse error: " .. tostring(data) end
  local ok2, bp = pcall(data)
  if not ok2 then return nil, "Execution error: " .. tostring(bp) end
  if type(bp) ~= "table" then return nil, "Blueprint must return a table" end
  return bp, nil
end

-- ─────────────────────────────────────────────
-- Analyse blueprint: count blocks needed per type
-- ─────────────────────────────────────────────
local function analyseBlueprintNeeds(bp)
  local needs = {}
  for _, layer in ipairs(bp.layers or {}) do
    for _, row in ipairs(layer) do
      for i = 1, #row do
        local char = row:sub(i, i)
        local blockName = bp.palette and bp.palette[char]
        if blockName then
          needs[blockName] = (needs[blockName] or 0) + 1
        end
      end
    end
  end
  return needs
end

-- ─────────────────────────────────────────────
-- Place a block down (turtle is above target cell)
-- ─────────────────────────────────────────────
local function placeBlock(blockName)
  local slot = findBlockInInventory(blockName)
  if not slot then
    return false, "Missing: " .. blockName
  end
  turtle.select(slot)
  local ok, err = turtle.placeDown()
  turtle.select(1)
  return ok, err
end

-- ─────────────────────────────────────────────
-- Build from blueprint
-- ─────────────────────────────────────────────
local function buildBlueprint(bp)
  local blockReader, _ = detect.findPeripheral("blockReader")
  local layers = bp.layers or {}
  local palette = bp.palette or {}
  local totalBlocks = 0
  local placed      = 0
  local errors      = {}

  -- Count total blocks
  for _, layer in ipairs(layers) do
    for _, row in ipairs(layer) do
      for i = 1, #row do
        if palette[row:sub(i,i)] then
          totalBlocks = totalBlocks + 1
        end
      end
    end
  end

  -- Build layer by layer (Y increases going up)
  for layerIdx, layer in ipairs(layers) do
    local targetY = layerIdx - 1  -- layer 1 = y=0, etc.
    -- Move up one level from previous layer
    moveToY(targetY + 1)  -- turtle is one above where it will place

    for rowIdx, row in ipairs(layer) do
      local targetZ = rowIdx - 1

      for colIdx = 1, #row do
        local char      = row:sub(colIdx, colIdx)
        local blockName = palette[char]
        local targetX   = colIdx - 1

        if blockName then
          -- Move to position (one above target cell)
          moveToXZ(targetX, targetZ)

          -- Check fuel
          if turtle.getFuelLevel() < 10 then
            for s = 1, 16 do
              turtle.select(s)
              if turtle.refuel(0) then turtle.refuel(1) end
            end
            turtle.select(1)
          end

          -- Place block
          local ok, err = placeBlock(blockName)
          if ok then
            placed = placed + 1
          else
            table.insert(errors, string.format("(%d,%d,%d): %s", targetX, targetY, targetZ, tostring(err)))
            -- Pause and ask user to add the block
            print("Missing block: " .. blockName)
            print("Add it to the turtle's inventory, then press Enter.")
            io.read()
            -- Try again
            ok, err = placeBlock(blockName)
            if ok then placed = placed + 1 end
          end

          -- Status
          if placed % 10 == 0 then
            local pct = math.floor(placed / totalBlocks * 100)
            term.setCursorPos(1, 1)
            print(string.format("Building: %d/%d (%d%%)  Layer %d/%d  Fuel:%d",
              placed, totalBlocks, pct, layerIdx, #layers, turtle.getFuelLevel()))
          end
        end
      end
    end
  end

  -- Return to start
  moveToY(#layers + 1)
  moveToXZ(0, 0)
  moveToY(0)
  faceDir(0)

  return placed, totalBlocks, errors
end

-- ─────────────────────────────────────────────
-- List available blueprints
-- ─────────────────────────────────────────────
local function listBlueprints()
  local files = {}
  if not fs.exists(BLUEPRINT_DIR) then
    fs.makeDir(BLUEPRINT_DIR)
  end
  local listing = fs.list(BLUEPRINT_DIR)
  for _, name in ipairs(listing) do
    if name:sub(-10) == ".blueprint" or name:sub(-4) == ".lua" then
      table.insert(files, name)
    end
  end
  return files
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  local files = listBlueprints()

  if #files == 0 then
    ui.clear()
    ui.drawHeader("Builder", "No Blueprints")
    print("\nNo blueprint files found in:")
    print(BLUEPRINT_DIR)
    print()
    print("Blueprint files end in .blueprint")
    print("Copy blueprints to the directory above.")
    print()
    print("Press any key to return.")
    os.pullEvent("key")
    return
  end

  -- Show blueprint list
  local items = {}
  for _, name in ipairs(files) do
    table.insert(items, { label = name })
  end
  table.insert(items, { label = "< Back" })

  local idx = ui.drawMenu(items, "Select Blueprint")
  if not idx or idx > #files then return end

  local bpPath = BLUEPRINT_DIR .. files[idx]
  local bp, err = loadBlueprint(bpPath)
  if not bp then
    ui.alert("Failed to load blueprint:\n" .. (err or "unknown error"), "error")
    return
  end

  -- Show blueprint info
  ui.clear()
  ui.drawHeader("Builder", bp.name or files[idx])
  local w, _ = term.getSize()
  local row  = 3

  local function infoLine(label, value, color)
    term.setCursorPos(2, row)
    ui.setColor(colors.cyan, colors.black)
    term.write(label .. ": ")
    ui.setColor(color or colors.white, colors.black)
    term.write(tostring(value):sub(1, w - #label - 4))
    ui.resetColor()
    row = row + 1
  end

  infoLine("Name",   bp.name or "?")
  infoLine("Size",   string.format("%dx%dx%d", bp.width or 0, bp.height or 0, bp.depth or 0))
  infoLine("Layers", #(bp.layers or {}))
  if bp.description then
    row = row + 1
    for _, line in ipairs(ui.wordWrap(bp.description, w - 4)) do
      infoLine("", line, colors.lightGray)
    end
  end
  row = row + 1

  -- Material checklist
  local needs = analyseBlueprintNeeds(bp)
  infoLine("Materials needed:", "", colors.yellow)
  row = row + 1
  for blockName, count in pairs(needs) do
    local have   = countBlock(blockName)
    local color  = have >= count and colors.lime or colors.orange
    local status = have >= count and "OK" or (have .. "/" .. count)
    term.setCursorPos(4, row)
    ui.setColor(color, colors.black)
    term.write(string.format("%-30s %s", blockName:sub(1, 29), status):sub(1, w - 4))
    ui.resetColor()
    row = row + 1
    if row >= select(2, term.getSize()) - 2 then
      term.setCursorPos(4, row)
      term.write("... (more items)")
      row = row + 1
      break
    end
  end

  ui.drawFooter("[Enter] Build  [Q] Cancel")
  while true do
    local _, key = os.pullEvent("key")
    if key == keys.q or key == keys.backspace then return end
    if key == keys.enter then break end
  end

  -- Build!
  ui.clear()
  print("Building: " .. (bp.name or files[idx]))
  print("Turtle starts at origin, builds forward/right and up.")
  print("Ensure area is clear! Press Enter to begin...")
  io.read()

  local ok, err2 = pcall(function()
    local placed, total, errs = buildBlueprint(bp)
    print(string.format("\nBuild complete: %d/%d blocks placed.", placed, total))
    if #errs > 0 then
      print(#errs .. " errors:")
      for i, e in ipairs(errs) do
        print("  " .. e)
        if i >= 5 then print("  ... and more"); break end
      end
    end
  end)

  if not ok then
    print("Builder error: " .. tostring(err2))
    pcall(moveToXZ, 0, 0)
  end

  print("Press any key to return.")
  os.pullEvent("key")
end

main()
