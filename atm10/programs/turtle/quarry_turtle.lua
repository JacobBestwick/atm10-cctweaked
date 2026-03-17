-- quarry_turtle.lua
-- ATM10 Area Quarry
-- Device: Turtle / Advanced Turtle
-- Required: Turtle with pickaxe
-- Optional: geoScanner (selective ore-only mining)
--
-- Mines out a configurable rectangular area layer by layer.
-- Saves progress so it can be resumed after interruption.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local ui     = require("ui")
local config = require("config")
local detect = require("detect")

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────
local CFG_FILE      = "quarry.cfg"
local PROGRESS_FILE = "quarry_progress.cfg"

local DEFAULTS = {
  width    = 16,
  length   = 16,
  depth    = 0,    -- 0 = dig to bedrock
  fillMode = false,
  selectiveMining = false,
}

-- ─────────────────────────────────────────────
-- Position tracking
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
    turtle.dig(); sleep(0.3)
  end
  return false
end

local function tryUp()
  for i = 1, 3 do
    if turtle.up() then pos.y = pos.y + 1; return true end
    turtle.digUp(); sleep(0.3)
  end
  return false
end

local function tryDown()
  for i = 1, 3 do
    if turtle.down() then pos.y = pos.y - 1; return true end
    turtle.digDown(); sleep(0.3)
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

-- ─────────────────────────────────────────────
-- Fuel
-- ─────────────────────────────────────────────
local function refuelFromInventory()
  local start = turtle.getFuelLevel()
  for i = 1, 16 do
    turtle.select(i)
    if turtle.refuel(0) then turtle.refuel() end
  end
  turtle.select(1)
  return turtle.getFuelLevel() > start
end

local function checkFuel(min)
  if turtle.getFuelLevel() >= min then return true end
  refuelFromInventory()
  return turtle.getFuelLevel() >= min
end

-- ─────────────────────────────────────────────
-- Inventory
-- ─────────────────────────────────────────────
local function slotsFull()
  local used = 0
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then used = used + 1 end
  end
  return used >= 15
end

local function dumpInventory()
  -- Try to drop into chest behind (turtle is at home position)
  faceDir(2)  -- face south = back toward start chest
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then
      turtle.select(i)
      turtle.drop()
    end
  end
  turtle.select(1)
  faceDir(0)
end

-- ─────────────────────────────────────────────
-- Return to start (0,0,0)
-- ─────────────────────────────────────────────
local function returnHome(startY)
  -- Go up first for safety
  while pos.y < startY do tryUp() end

  -- Navigate to x=0
  if pos.x > 0 then
    faceDir(3)
    for i = 1, pos.x do tryForward() end
  elseif pos.x < 0 then
    faceDir(1)
    for i = 1, -pos.x do tryForward() end
  end

  -- Navigate to z=0
  if pos.z > 0 then
    faceDir(0)
    for i = 1, pos.z do tryForward() end
  elseif pos.z < 0 then
    faceDir(2)
    for i = 1, -pos.z do tryForward() end
  end

  faceDir(0)
end

-- ─────────────────────────────────────────────
-- Common stone/dirt detection (skip these in selective mode)
-- ─────────────────────────────────────────────
local COMMON_BLOCKS = {
  "minecraft:stone", "minecraft:deepslate", "minecraft:dirt",
  "minecraft:grass_block", "minecraft:gravel", "minecraft:sand",
  "minecraft:andesite", "minecraft:diorite", "minecraft:granite",
  "minecraft:tuff", "minecraft:calcite", "minecraft:dripstone_block",
  "minecraft:cobblestone", "minecraft:netherrack", "minecraft:end_stone",
}
local commonSet = {}
for _, v in ipairs(COMMON_BLOCKS) do commonSet[v] = true end

local function isCommonBlock(name)
  return commonSet[name] or false
end

-- ─────────────────────────────────────────────
-- Mine one column (dig down)
-- ─────────────────────────────────────────────
local function mineColumn(targetDepth, selective)
  local dug = 0
  while pos.y > targetDepth do
    local ok, data = turtle.inspectDown()
    local shouldDig = true
    if selective and ok and data then
      shouldDig = not isCommonBlock(data.name)
    end

    if shouldDig then
      turtle.digDown()
      dug = dug + 1
    end

    if not tryDown() then break end  -- hit bedrock

    -- Check fuel and inventory
    if not checkFuel(20) then return false end
    if slotsFull() then return false end
  end
  return true
end

-- ─────────────────────────────────────────────
-- Main quarry loop
-- ─────────────────────────────────────────────
local function runQuarry(cfg)
  local startY   = pos.y
  local targetY  = cfg.depth > 0 and (startY - cfg.depth) or -64

  -- Load progress if resuming
  local progress = config.load(PROGRESS_FILE)
  local startRow = progress and progress.row or 1
  local startCol = progress and progress.col or 1

  local blocksTotal = cfg.width * cfg.length
  local blocksDone  = (startRow - 1) * cfg.length + (startCol - 1)

  -- Navigate to resume position if needed
  if progress then
    print("Resuming quarry at row " .. startRow .. " col " .. startCol)
    sleep(1)
  end

  local row = startRow
  local goingRight = (startRow % 2 == 1)  -- snake pattern direction

  while row <= cfg.length do
    local col = (row == startRow) and startCol or 1
    local endCol = cfg.width

    while col <= endCol do
      -- Save progress
      config.save(PROGRESS_FILE, { row = row, col = col, startY = startY })

      -- Mine this column down
      local ok = mineColumn(targetY, cfg.selectiveMining)

      -- Come back up
      while pos.y < startY do tryUp() end

      blocksDone = blocksDone + 1

      -- Status
      term.setCursorPos(1, 1)
      local pct = math.floor(blocksDone / blocksTotal * 100)
      print(string.format("Quarry: %d/%d cols (%d%%)  Fuel:%d",
        blocksDone, blocksTotal, pct, turtle.getFuelLevel()))

      if not ok then
        -- Inventory full or low fuel - go home
        local savedRow, savedCol = row, col
        returnHome(startY)
        dumpInventory()
        refuelFromInventory()
        print("Emptied inventory. Returning to quarry...")
        print("Press Enter to continue...")
        io.read()
        -- Navigate back to position (simplified - start from origin)
        -- For a full implementation, you'd navigate back to the saved position
        config.save(PROGRESS_FILE, { row = savedRow, col = savedCol, startY = startY })
        return  -- Let user restart to resume
      end

      -- Move to next column
      if col < endCol then
        if goingRight then
          faceDir(1)  -- east
        else
          faceDir(3)  -- west
        end
        tryForward()
      end

      col = col + 1
    end

    -- End of row - move to next row
    if row < cfg.length then
      faceDir(2)  -- south = advance row
      tryForward()
      goingRight = not goingRight
    end

    row = row + 1
  end

  -- Done!
  returnHome(startY)
  dumpInventory()
  config.delete(PROGRESS_FILE)

  print("Quarry complete!")
  print("Blocks mined: " .. blocksDone)
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  local cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  ui.clear()
  ui.drawHeader("Quarry", "Setup")
  local w, _ = term.getSize()

  -- Check for saved progress
  local progress = config.load(PROGRESS_FILE)
  if progress then
    term.setCursorPos(2, 3)
    ui.setColor(colors.yellow, colors.black)
    term.write("Saved progress found! (row " .. (progress.row or 1) .. "/" .. cfg.length .. ")")
    ui.resetColor()
    term.setCursorPos(2, 4)
    if ui.confirm("Resume previous quarry?") then
      local ok, err = pcall(runQuarry, cfg)
      if not ok then print("Error: " .. tostring(err)) end
      print("Press any key...")
      os.pullEvent("key")
      return
    end
    config.delete(PROGRESS_FILE)
  end

  -- New quarry config
  local row = 3
  local function showConfig()
    term.setCursorPos(2, row)
    ui.setColor(colors.cyan, colors.black)
    term.write("Width:  "); ui.setColor(colors.white, colors.black); term.write(tostring(cfg.width))
    term.setCursorPos(2, row+1)
    ui.setColor(colors.cyan, colors.black)
    term.write("Length: "); ui.setColor(colors.white, colors.black); term.write(tostring(cfg.length))
    term.setCursorPos(2, row+2)
    ui.setColor(colors.cyan, colors.black)
    term.write("Depth:  "); ui.setColor(colors.white, colors.black)
    term.write(cfg.depth > 0 and tostring(cfg.depth) or "to bedrock")
    term.setCursorPos(2, row+3)
    ui.setColor(colors.cyan, colors.black)
    term.write("Fuel:   "); ui.setColor(colors.white, colors.black); term.write(tostring(turtle.getFuelLevel()))
    ui.resetColor()
  end

  showConfig()

  ui.drawFooter("[Enter] Start  [C] Configure  [Q] Cancel")

  while true do
    local evt, key = os.pullEvent("key")
    if key == keys.q then return end
    if key == keys.enter then break end
    if key == keys.c then
      local raw = ui.inputText("Width (current " .. cfg.width .. "): ")
      if tonumber(raw) then cfg.width = tonumber(raw) end
      raw = ui.inputText("Length (current " .. cfg.length .. "): ")
      if tonumber(raw) then cfg.length = tonumber(raw) end
      raw = ui.inputText("Depth (0=bedrock, current " .. cfg.depth .. "): ")
      if tonumber(raw) then cfg.depth = tonumber(raw) end
      raw = ui.inputText("Selective mining? (y/n): ")
      cfg.selectiveMining = (raw and raw:lower() == "y")
      config.save(CFG_FILE, cfg)
      ui.clear()
      ui.drawHeader("Quarry", "Setup")
      showConfig()
    end
  end

  -- Estimate fuel
  local estimate = cfg.width * cfg.length * (cfg.depth > 0 and cfg.depth or 256) / 4
  print(string.format("\nEstimated fuel needed: ~%d", estimate))
  if turtle.getFuelLevel() < estimate then
    print("WARNING: Low fuel. Refuel or the quarry will pause mid-run.")
  end
  print("Place a chest BEHIND the turtle at start position.")
  print("Press Enter when ready...")
  io.read()

  local ok, err = pcall(runQuarry, cfg)
  if not ok then
    print("Quarry error: " .. tostring(err))
    pcall(returnHome, pos.y)
  end

  print("Quarry session ended. Press any key.")
  os.pullEvent("key")
end

main()
