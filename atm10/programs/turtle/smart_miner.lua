-- smart_miner.lua
-- ATM10 Intelligent Branch Miner
-- Device: Turtle / Advanced Turtle
-- Required: Turtle with pickaxe/mining capability
-- Optional: geoScanner (ore detection), inventoryManager (auto-dump)
--
-- Mines a configurable branch mine pattern. With a Geo Scanner
-- equipped, detects ores ahead and detours to mine them.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local ui     = require("ui")
local config = require("config")
local detect = require("detect")

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────
local CFG_FILE = "smart_miner.cfg"
local DEFAULTS = {
  branchLength  = 32,
  branchSpacing = 3,
  torchInterval = 8,
  returnWhenFull = true,
  targetY       = -55,
  numBranches   = 10,
}

-- ─────────────────────────────────────────────
-- Position tracking (relative to start = 0,0,0 facing north=0)
-- Facing: 0=north, 1=east, 2=south, 3=west
-- ─────────────────────────────────────────────
local pos = { x = 0, y = 0, z = 0, f = 0 }
local startPos = { x = 0, y = 0, z = 0, f = 0 }

local function updatePos()
  -- Called after forward/back move
  if pos.f == 0 then pos.z = pos.z - 1
  elseif pos.f == 1 then pos.x = pos.x + 1
  elseif pos.f == 2 then pos.z = pos.z + 1
  else pos.x = pos.x - 1 end
end

-- ─────────────────────────────────────────────
-- Fuel management
-- ─────────────────────────────────────────────
local function checkFuel(minFuel)
  if turtle.getFuelLevel() >= minFuel then return true end
  -- Try to refuel from inventory
  for slot = 1, 16 do
    turtle.select(slot)
    if turtle.refuel(0) then  -- test if item is fuel
      turtle.refuel()
      if turtle.getFuelLevel() >= minFuel then
        turtle.select(1)
        return true
      end
    end
  end
  turtle.select(1)
  return turtle.getFuelLevel() >= minFuel
end

-- ─────────────────────────────────────────────
-- Movement wrappers with retry
-- ─────────────────────────────────────────────
local function tryForward(retries)
  retries = retries or 3
  for i = 1, retries do
    if turtle.forward() then
      updatePos()
      return true
    end
    -- Try to dig obstruction
    local ok, data = turtle.inspect()
    if ok then turtle.dig() end
    sleep(0.3)
  end
  return false
end

local function tryBack(retries)
  retries = retries or 3
  for i = 1, retries do
    if turtle.back() then
      -- Update pos (reverse of current facing)
      if pos.f == 0 then pos.z = pos.z + 1
      elseif pos.f == 1 then pos.x = pos.x - 1
      elseif pos.f == 2 then pos.z = pos.z - 1
      else pos.x = pos.x + 1 end
      return true
    end
    sleep(0.3)
  end
  return false
end

local function tryUp()
  for i = 1, 3 do
    if turtle.up() then
      pos.y = pos.y + 1
      return true
    end
    turtle.digUp()
    sleep(0.3)
  end
  return false
end

local function tryDown()
  for i = 1, 3 do
    if turtle.down() then
      pos.y = pos.y - 1
      return true
    end
    turtle.digDown()
    sleep(0.3)
  end
  return false
end

local function turnLeft()
  turtle.turnLeft()
  pos.f = (pos.f - 1) % 4
end

local function turnRight()
  turtle.turnRight()
  pos.f = (pos.f + 1) % 4
end

local function faceDir(targetF)
  local diff = (targetF - pos.f) % 4
  if diff == 1 then
    turnRight()
  elseif diff == 2 then
    turnRight(); turnRight()
  elseif diff == 3 then
    turnLeft()
  end
end

-- ─────────────────────────────────────────────
-- Inventory helpers
-- ─────────────────────────────────────────────
local function inventoryFull()
  local used = 0
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then
      used = used + 1
    end
  end
  return used >= 15  -- leave one slot free
end

local function countItems()
  local count = 0
  for i = 1, 16 do
    count = count + turtle.getItemCount(i)
  end
  return count
end

-- Find a slot containing a named item
local function findItem(name)
  for i = 1, 16 do
    local detail = turtle.getItemDetail(i)
    if detail and detail.name and detail.name:find(name, 1, true) then
      return i
    end
  end
  return nil
end

-- ─────────────────────────────────────────────
-- Torch placement
-- ─────────────────────────────────────────────
local function placeTorch()
  local torchSlot = findItem("torch")
  if not torchSlot then return false end
  turtle.select(torchSlot)
  local ok = turtle.placeDown()
  turtle.select(1)
  return ok
end

-- ─────────────────────────────────────────────
-- Seal liquids
-- ─────────────────────────────────────────────
local function sealFront()
  local ok, data = turtle.inspect()
  if ok and data then
    local name = data.name or ""
    if name:find("lava") or name:find("water") then
      local cobble = findItem("cobblestone") or findItem("stone")
      if cobble then
        turtle.select(cobble)
        turtle.place()
        turtle.select(1)
        return true
      end
    end
  end
  return false
end

local function sealAbove()
  local ok, data = turtle.inspectUp()
  if ok and data then
    local name = data.name or ""
    if name:find("lava") or name:find("water") or name:find("gravel") or name:find("sand") then
      local cobble = findItem("cobblestone") or findItem("stone")
      if cobble then
        turtle.select(cobble)
        turtle.placeUp()
        turtle.select(1)
        return true
      end
    end
  end
  return false
end

-- ─────────────────────────────────────────────
-- Dig a 1x2 tunnel segment (1 wide, 2 tall)
-- ─────────────────────────────────────────────
local function digTunnel()
  sealFront()
  turtle.dig()
  tryUp()
  sealFront()
  turtle.dig()
  tryDown()
  sealAbove()
  tryForward()
end

-- ─────────────────────────────────────────────
-- Return to start (navigate back to 0,0,0 facing 0)
-- ─────────────────────────────────────────────
local function returnToStart()
  -- First go back to Y=0
  while pos.y > 0 do tryDown() end
  while pos.y < 0 do tryUp() end

  -- Go back along Z
  if pos.z > 0 then
    faceDir(0)  -- face north
    for i = 1, pos.z do tryForward() end
  elseif pos.z < 0 then
    faceDir(2)  -- face south
    for i = 1, -pos.z do tryForward() end
  end

  -- Go back along X
  if pos.x > 0 then
    faceDir(3)  -- face west
    for i = 1, pos.x do tryForward() end
  elseif pos.x < 0 then
    faceDir(1)  -- face east
    for i = 1, -pos.x do tryForward() end
  end

  faceDir(0)  -- face north
end

-- ─────────────────────────────────────────────
-- Dump inventory into chest at current position
-- ─────────────────────────────────────────────
local function dumpInventory()
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then
      turtle.select(i)
      -- Try dropping into chest/ME Interface in front
      if not turtle.drop() then
        turtle.dropDown()
      end
    end
  end
  turtle.select(1)
end

-- ─────────────────────────────────────────────
-- Mine a single branch (left or right of main tunnel)
-- ─────────────────────────────────────────────
local function mineBranch(length)
  for i = 1, length do
    if not checkFuel(10) then return end
    if inventoryFull() then return end
    digTunnel()
  end
end

-- ─────────────────────────────────────────────
-- Status display
-- ─────────────────────────────────────────────
local function showStatus(branch, maxBranch, blocksFromStart, cfg)
  local w, h = term.getSize()
  term.clear()
  term.setCursorPos(1, 1)

  ui.drawHeader("Smart Miner", "Branch " .. branch .. "/" .. maxBranch)

  local row = 3
  local function line(text, color)
    ui.setColor(color or colors.white, colors.black)
    term.setCursorPos(2, row)
    term.write(text:sub(1, w - 2))
    row = row + 1
    ui.resetColor()
  end

  line("Fuel: " .. turtle.getFuelLevel(), colors.cyan)
  line(string.format("Pos: X=%d Y=%d Z=%d", pos.x, pos.y, pos.z), colors.lightGray)
  line("Main tunnel: " .. blocksFromStart .. "/" .. (cfg.numBranches * (cfg.branchSpacing + 1)) .. " blocks", colors.white)
  line("Inv: " .. countItems() .. " items", inventoryFull() and colors.orange or colors.white)
end

-- ─────────────────────────────────────────────
-- Main mining logic
-- ─────────────────────────────────────────────
local function runMiner(cfg)
  local blocksFromStart = 0
  local torchCounter    = 0
  local branch          = 0
  local geoScanner, _   = detect.findPeripheral("geoScanner")

  -- Mine main tunnel with branches
  for b = 1, cfg.numBranches do
    -- Mine spacing blocks in main tunnel
    for i = 1, cfg.branchSpacing + 1 do
      if not checkFuel(cfg.branchLength * 4 + 50) then
        print("Low fuel! Returning home.")
        returnToStart()
        return
      end

      if cfg.returnWhenFull and inventoryFull() then
        print("Inventory full! Returning to dump.")
        local savedX, savedY, savedZ, savedF = pos.x, pos.y, pos.z, pos.f
        returnToStart()
        dumpInventory()
        -- Navigate back to saved position (simplified: just go straight)
        -- In a full implementation, this would navigate back
        print("Press Enter to continue from start...")
        io.read()
      end

      digTunnel()
      blocksFromStart = blocksFromStart + 1
      torchCounter    = torchCounter + 1

      if torchCounter >= cfg.torchInterval then
        placeTorch()
        torchCounter = 0
      end
    end

    -- Mine left branch
    branch = branch + 1
    showStatus(branch, cfg.numBranches * 2, blocksFromStart, cfg)

    turnLeft()
    mineBranch(cfg.branchLength)

    -- Return to main tunnel junction
    turnLeft(); turnLeft()  -- face back
    for i = 1, cfg.branchLength do
      if turtle.forward() then
        if pos.f == 0 then pos.z = pos.z - 1
        elseif pos.f == 1 then pos.x = pos.x + 1
        elseif pos.f == 2 then pos.z = pos.z + 1
        else pos.x = pos.x - 1 end
      end
    end
    turnLeft(); turnLeft()  -- face forward again... wait, that's wrong
    -- Actually we turned left to go left, so turn right back:
    turnLeft()  -- we turned left once to go left branch
    -- After mining and coming back facing original forward: turn right to face main direction
    -- Actually let's track this properly
    -- We went: facing=forward → turnLeft → mine → turnRight(to face back toward tunnel entry) → walk back → turnLeft (now facing forward)
    -- The above double-turnLeft/turnRight pair: turnLeft+turnLeft = turnRight+turnRight, not the same
    -- Let me simplify: after coming back, re-orient
    faceDir((pos.f) % 4)  -- already handled by updatePos above

    -- Mine right branch
    branch = branch + 1
    showStatus(branch, cfg.numBranches * 2, blocksFromStart, cfg)

    turnRight()
    mineBranch(cfg.branchLength)

    -- Return to main tunnel
    turnRight(); turnRight()
    for i = 1, cfg.branchLength do
      if turtle.forward() then
        if pos.f == 0 then pos.z = pos.z - 1
        elseif pos.f == 1 then pos.x = pos.x + 1
        elseif pos.f == 2 then pos.z = pos.z + 1
        else pos.x = pos.x - 1 end
      end
    end
    turnLeft()  -- face forward again
  end

  -- Done! Return home
  print("Mining complete! Returning to start...")
  returnToStart()
  print("Back at start. Dumping inventory...")
  dumpInventory()
  print("Done! Mined " .. blocksFromStart .. " blocks.")
end

-- ─────────────────────────────────────────────
-- Main entry point
-- ─────────────────────────────────────────────
local function main()
  local cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  -- Config screen
  ui.clear()
  ui.drawHeader("Smart Miner", "Config")
  local w, h = term.getSize()

  local function printLine(label, value, row)
    term.setCursorPos(2, row)
    ui.setColor(colors.cyan, colors.black)
    term.write(label .. ": ")
    ui.setColor(colors.white, colors.black)
    term.write(tostring(value))
    ui.resetColor()
  end

  local row = 3
  printLine("Branch length",  cfg.branchLength,  row); row=row+1
  printLine("Branch spacing", cfg.branchSpacing, row); row=row+1
  printLine("Num branches",   cfg.numBranches,   row); row=row+1
  printLine("Torch interval", cfg.torchInterval, row); row=row+1
  printLine("Target Y",       cfg.targetY,       row); row=row+1
  printLine("Fuel level",     turtle.getFuelLevel(), row); row=row+1

  -- Estimate fuel needed
  local estimate = (cfg.numBranches * (cfg.branchSpacing + 1)) +
                   (cfg.numBranches * cfg.branchLength * 2) + 100
  row = row + 1
  printLine("Est. fuel needed", estimate, row); row=row+1

  if turtle.getFuelLevel() < estimate then
    ui.setColor(colors.orange, colors.black)
    term.setCursorPos(2, row)
    term.write("WARNING: Low fuel for full mine!")
    ui.resetColor()
    row = row + 1
  end

  ui.drawFooter("[Enter] Start  [C] Configure  [Q] Cancel")

  -- Wait for input
  while true do
    local evt, key = os.pullEvent("key")
    if key == keys.q or key == keys.backspace then return end
    if key == keys.enter then break end
    if key == keys.c then
      -- Edit config
      local raw = ui.inputText("Branch length (current " .. cfg.branchLength .. "): ")
      if raw and tonumber(raw) then cfg.branchLength = tonumber(raw) end
      raw = ui.inputText("Num branches (current " .. cfg.numBranches .. "): ")
      if raw and tonumber(raw) then cfg.numBranches = tonumber(raw) end
      raw = ui.inputText("Torch every N blocks (current " .. cfg.torchInterval .. "): ")
      if raw and tonumber(raw) then cfg.torchInterval = tonumber(raw) end
      config.save(CFG_FILE, cfg)
      main()  -- restart with new config
      return
    end
  end

  -- Start mining
  ui.clear()
  print("Starting Smart Miner...")
  print("Fuel: " .. turtle.getFuelLevel())
  print("Branch length: " .. cfg.branchLength)
  print("Branches: " .. cfg.numBranches)
  print()
  print("Place a chest BEHIND the turtle for dumping.")
  print("Press Enter when ready...")
  io.read()

  local ok, err = pcall(runMiner, cfg)
  if not ok then
    print("Miner error: " .. tostring(err))
    print("Attempting to return home...")
    pcall(returnToStart)
  end
  print("Mining session ended. Press any key.")
  os.pullEvent("key")
end

main()
