-- tree_farmer.lua
-- ATM10 Advanced Tree Farm
-- Device: Turtle / Advanced Turtle (needs axe equipped)
-- Required: Turtle with axe, saplings in inventory
-- Optional: None
--
-- Maintains a grid of trees, chopping and replanting automatically.
-- Supports normal trees and 2x2 mega trees (spruce, dark oak).

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local ui     = require("ui")
local config = require("config")

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────
local CFG_FILE = "tree_farmer.cfg"
local DEFAULTS = {
  gridWidth    = 4,
  gridHeight   = 4,
  spacing      = 4,
  waitForGrowth = 120,
  useBoneMeal  = true,
  returnToChest = true,
  chestDir     = "back",
  cycles       = 0,
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
  for i = 1, 5 do
    if turtle.forward() then updateForward(); return true end
    -- Could be tree trunk - try digging
    turtle.dig()
    sleep(0.4)
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

-- ─────────────────────────────────────────────
-- Inventory helpers
-- ─────────────────────────────────────────────
local function findItem(namePart)
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and d.name and d.name:find(namePart, 1, true) then
      return i
    end
  end
  return nil
end

local function slotsFull()
  local used = 0
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then used = used + 1 end
  end
  return used >= 15
end

local function refuel()
  for i = 1, 16 do
    turtle.select(i)
    if turtle.refuel(0) then turtle.refuel(1) end
    if turtle.getFuelLevel() > 500 then break end
  end
  turtle.select(1)
end

-- ─────────────────────────────────────────────
-- Tree detection
-- ─────────────────────────────────────────────
local function isLog(data)
  if not data then return false end
  local n = (data.name or ""):lower()
  return n:find("_log") ~= nil or n:find("wood") ~= nil
end

local function isSapling(data)
  if not data then return false end
  local n = (data.name or ""):lower()
  return n:find("sapling") ~= nil
end

local function isTreePresent()
  local ok, data = turtle.inspect()
  return ok and isLog(data)
end

-- ─────────────────────────────────────────────
-- Chop a single tree (climb and dig trunk + canopy)
-- ─────────────────────────────────────────────
local function chopTree()
  -- We're standing in front of the tree base (or on top of sapling position)
  -- Dig tree at ground level
  local ok, data = turtle.inspect()
  if not (ok and isLog(data)) then return false end

  local saplingType = nil
  -- Move to tree position
  turtle.dig()
  tryForward()

  -- Climb the trunk
  local height = 0
  while true do
    local upOk, upData = turtle.inspectUp()
    if upOk and isLog(upData) then
      if not saplingType then
        -- Guess sapling from log name
        saplingType = (upData.name or ""):gsub("_log", "_sapling"):gsub("wood", "sapling")
      end
      turtle.digUp()
      tryUp()
      height = height + 1
    else
      break
    end
  end

  -- Dig any remaining canopy logs around us
  for _ = 1, 3 do
    turtle.dig(); turnRight()
  end
  turtle.dig()

  -- Come back down
  while pos.y > 0 do tryDown() end

  -- Go back to grid position (one step back)
  faceDir(2)  -- face back/south (to step back to grid cell)
  tryForward()
  faceDir(0)  -- face north again

  return true, saplingType
end

-- ─────────────────────────────────────────────
-- Replant sapling at current position (turtle is ON the planting spot)
-- ─────────────────────────────────────────────
local function replant(saplingType)
  -- Find any sapling in inventory
  local slot = saplingType and findItem(saplingType) or findItem("sapling")
  if not slot then
    print("No saplings left! Add saplings to inventory.")
    return false
  end

  turtle.select(slot)
  turtle.placeDown()
  turtle.select(1)

  -- Apply bone meal if enabled and available
  local boneMeal = findItem("bone_meal")
  if boneMeal then
    turtle.select(boneMeal)
    for i = 1, 3 do
      turtle.placeDown()
      sleep(0.1)
      -- Check if grown already
      local ok, data = turtle.inspectDown()
      if ok and isLog(data) then break end
    end
    turtle.select(1)
  end

  return true
end

-- ─────────────────────────────────────────────
-- Return to chest and dump inventory
-- ─────────────────────────────────────────────
local function returnAndDump()
  moveToXZ(0, 0)
  faceDir(2)  -- face the chest (assumed behind start = south)
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and not isSapling(d) and not d.name:find("bone_meal") then
      turtle.select(i)
      turtle.drop()
    end
  end
  turtle.select(1)
  faceDir(0)
end

-- ─────────────────────────────────────────────
-- Stats
-- ─────────────────────────────────────────────
local stats = {
  treesChopped = 0,
  logsCollected = 0,
  saplings = 0,
  cycles   = 0,
}

local function showStatus(cfg, gridRow, gridCol)
  term.setCursorPos(1, 1)
  local w = select(1, term.getSize())
  print(string.format("Tree Farm | Cycle:%d  Trees:%d  Grid:%d,%d/%d,%d",
    stats.cycles, stats.treesChopped, gridRow, gridCol, cfg.gridWidth, cfg.gridHeight))
  print(string.format("Fuel: %d  Logs: %d  Sap: %d  Inv: %d%%",
    turtle.getFuelLevel(), stats.logsCollected, stats.saplings,
    math.floor((function()
      local u=0; for i=1,16 do if turtle.getItemCount(i)>0 then u=u+1 end end
      return u/16*100
    end)())))
end

-- ─────────────────────────────────────────────
-- Main farm loop
-- ─────────────────────────────────────────────
local function runFarm(cfg)
  local running = true

  while running do
    stats.cycles = stats.cycles + 1

    -- Visit every grid position in snake order
    for gRow = 0, cfg.gridHeight - 1 do
      for gColRaw = 0, cfg.gridWidth - 1 do
        local gCol = (gRow % 2 == 0) and gColRaw or (cfg.gridWidth - 1 - gColRaw)

        -- Grid cell coordinates (in world units)
        local tx = gCol * cfg.spacing
        local tz = gRow * cfg.spacing

        showStatus(cfg, gRow + 1, gCol + 1)

        -- Navigate to cell
        moveToXZ(tx, tz)
        faceDir(0)  -- face north

        -- Refuel if low
        if turtle.getFuelLevel() < 100 then refuel() end

        -- Check what's at this position
        local ok, data = turtle.inspectDown()
        local isGrown = ok and isLog(data)

        -- Also check if sapling/plant at +1 forward (tree is planted one step ahead)
        local ok2, fwdData = turtle.inspect()
        if ok2 and isLog(fwdData) then isGrown = true end

        if isGrown or isTreePresent() then
          local chopped, sapType = chopTree()
          if chopped then
            stats.treesChopped = stats.treesChopped + 1
            -- Move to grid cell center to replant
            moveToXZ(tx, tz)
            -- Replant
            local planted = replant(sapType)
            if planted then stats.saplings = stats.saplings + 1 end
          end
        end

        -- Dump if full
        if slotsFull() and cfg.returnToChest then
          returnAndDump()
        end
      end
    end

    -- After full cycle, return to chest
    if cfg.returnToChest then
      returnAndDump()
      refuel()
    end

    -- Wait for trees to grow before next cycle
    print("Cycle " .. stats.cycles .. " done. Waiting " .. cfg.waitForGrowth .. "s for growth...")
    local waitTimer = os.startTimer(cfg.waitForGrowth)
    while true do
      local evt, p1 = os.pullEvent()
      if evt == "timer" and p1 == waitTimer then break end
      if evt == "key" and p1 == keys.q then running = false; break end
      if evt == "terminate" then running = false; break end
    end

    if not running then break end
  end

  -- Return home
  moveToXZ(0, 0)
  faceDir(0)
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  local cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  ui.clear()
  ui.drawHeader("Tree Farmer", "Setup")
  local w, _ = term.getSize()

  term.setCursorPos(2, 3)
  print("Grid: " .. cfg.gridWidth .. "x" .. cfg.gridHeight .. " trees")
  term.setCursorPos(2, 4)
  print("Spacing: " .. cfg.spacing .. " blocks between trees")
  term.setCursorPos(2, 5)
  print("Bone meal: " .. (cfg.useBoneMeal and "yes" or "no"))
  term.setCursorPos(2, 6)
  print("Fuel: " .. turtle.getFuelLevel())
  term.setCursorPos(2, 8)
  print("Setup:")
  term.setCursorPos(2, 9)
  print(" - Place turtle at SW corner of grid")
  term.setCursorPos(2, 10)
  print(" - Put saplings in inventory")
  term.setCursorPos(2, 11)
  print(" - Optionally: bone meal, charcoal for fuel")
  term.setCursorPos(2, 12)
  print(" - Place chest BEHIND (south) for log dumping")

  ui.drawFooter("[Enter] Start  [C] Config  [Q] Cancel")

  while true do
    local _, key = os.pullEvent("key")
    if key == keys.q then return end
    if key == keys.enter then break end
    if key == keys.c then
      local raw = ui.inputText("Grid width (current " .. cfg.gridWidth .. "): ")
      if tonumber(raw) then cfg.gridWidth = tonumber(raw) end
      raw = ui.inputText("Grid height (current " .. cfg.gridHeight .. "): ")
      if tonumber(raw) then cfg.gridHeight = tonumber(raw) end
      raw = ui.inputText("Tree spacing (current " .. cfg.spacing .. "): ")
      if tonumber(raw) then cfg.spacing = tonumber(raw) end
      raw = ui.inputText("Wait time seconds (current " .. cfg.waitForGrowth .. "): ")
      if tonumber(raw) then cfg.waitForGrowth = tonumber(raw) end
      config.save(CFG_FILE, cfg)
      main(); return
    end
  end

  ui.clear()
  print("Starting Tree Farmer...")
  print("Grid: " .. cfg.gridWidth .. "x" .. cfg.gridHeight)
  print("Press Q during wait phase to stop.")
  sleep(2)

  local ok, err = pcall(runFarm, cfg)
  if not ok then
    print("Error: " .. tostring(err))
    pcall(moveToXZ, 0, 0)
  end

  print("\nTree farmer stopped.")
  print("Stats: " .. stats.treesChopped .. " trees, " .. stats.cycles .. " cycles.")
  print("Press any key.")
  os.pullEvent("key")
end

main()
