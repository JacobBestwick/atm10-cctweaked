-- mob_grinder.lua
-- ATM10 Mobile Mob Farm Assistant
-- Device: Turtle / Advanced Turtle (sword equipped)
-- Required: Turtle
-- Optional: inventoryManager (auto-dump loot)
--
-- Patrols a kill-box area, attacks mobs, and periodically
-- returns to dump collected loot into a chest.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local ui     = require("ui")
local config = require("config")

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────
local CFG_FILE = "mob_grinder.cfg"
local DEFAULTS = {
  patrolWidth    = 5,
  patrolLength   = 5,
  killDelay      = 0.5,
  returnInterval = 300,  -- seconds between dumps
  dumpChestDir   = "down",
  autoRefuel     = true,
  fuelWarning    = 200,
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
    sleep(0.2)
  end
  return false
end

local function tryUp()
  if turtle.up() then pos.y = pos.y + 1; return true end
  return false
end

local function tryDown()
  if turtle.down() then pos.y = pos.y - 1; return true end
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
-- Combat & loot
-- ─────────────────────────────────────────────
local stats = {
  kills  = 0,
  items  = 0,
  dumps  = 0,
  cycles = 0,
}

local function attackAll()
  local hit = false
  -- Attack in all 6 directions
  if turtle.attack()     then stats.kills = stats.kills + 1; hit = true end
  if turtle.attackUp()   then stats.kills = stats.kills + 1; hit = true end
  if turtle.attackDown() then stats.kills = stats.kills + 1; hit = true end

  -- Spin and attack the other sides
  for dir = 1, 3 do
    turnRight()
    if turtle.attack() then stats.kills = stats.kills + 1; hit = true end
  end
  turnRight()  -- back to original facing

  return hit
end

local function countItems()
  local count = 0
  for i = 1, 16 do count = count + turtle.getItemCount(i) end
  return count
end

local function slotsFull()
  local used = 0
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then used = used + 1 end
  end
  return used >= 15
end

local function dumpLoot(chestDir)
  chestDir = chestDir or "down"
  local prevItems = countItems()
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then
      turtle.select(i)
      local ok = false
      if chestDir == "down" then
        ok = turtle.dropDown()
      elseif chestDir == "up" then
        ok = turtle.dropUp()
      else
        ok = turtle.drop()
      end
    end
  end
  turtle.select(1)
  local newItems = countItems()
  stats.items = stats.items + (prevItems - newItems)
  stats.dumps = stats.dumps + 1
end

local function refuel()
  if not cfg_global then return end
  for i = 1, 16 do
    turtle.select(i)
    if turtle.refuel(0) then
      turtle.refuel()
      if turtle.getFuelLevel() > 1000 then break end
    end
  end
  turtle.select(1)
end

-- ─────────────────────────────────────────────
-- Status display
-- ─────────────────────────────────────────────
cfg_global = nil  -- global for refuel access

local function showStatus(cfg)
  local w, h = term.getSize()
  term.clear()
  term.setCursorPos(1, 1)
  ui.drawHeader("Mob Grinder", "Running")

  local row = 3
  local function line(text, color)
    ui.setColor(color or colors.white, colors.black)
    term.setCursorPos(2, row)
    term.write(text:sub(1, w - 2))
    row = row + 1
    ui.resetColor()
  end

  line("Kills:  " .. stats.kills,  colors.orange)
  line("Items:  " .. stats.items,  colors.cyan)
  line("Dumps:  " .. stats.dumps,  colors.lightGray)
  line("Cycles: " .. stats.cycles, colors.lightGray)
  row = row + 1
  line("Fuel:   " .. turtle.getFuelLevel(),
       turtle.getFuelLevel() < (cfg.fuelWarning or 200) and colors.orange or colors.white)
  line(string.format("Pos: X=%d Z=%d", pos.x, pos.z), colors.gray)

  ui.drawFooter("[Q] Stop  — attacking mobs")
end

-- ─────────────────────────────────────────────
-- Patrol loop
-- ─────────────────────────────────────────────
local function runGrinder(cfg)
  cfg_global = cfg

  local grindRunning = true
  local lastDump     = os.clock()

  while grindRunning do
    stats.cycles = stats.cycles + 1

    -- Sweep the patrol area in snake pattern
    for row = 0, cfg.patrolLength - 1 do
      for colRaw = 0, cfg.patrolWidth - 1 do
        local col = (row % 2 == 0) and colRaw or (cfg.patrolWidth - 1 - colRaw)

        -- Navigate to cell
        moveToXZ(col, row)
        faceDir(0)

        -- Attack!
        attackAll()
        sleep(cfg.killDelay or 0.5)

        -- Check for terminate/quit
        local event = os.pullEventRaw("terminate", "key")
        if event == "terminate" then grindRunning = false; break end

        -- Fuel check
        if turtle.getFuelLevel() < (cfg.fuelWarning or 200) then
          if cfg.autoRefuel then
            refuel()
          else
            showStatus(cfg)
            if turtle.getFuelLevel() < 50 then
              print("CRITICAL: Fuel too low! Returning home.")
              grindRunning = false
              break
            end
          end
        end

        -- Inventory check
        if slotsFull() then
          moveToXZ(0, 0)
          dumpLoot(cfg.dumpChestDir)
          lastDump = os.clock()
        end
      end

      if not grindRunning then break end
    end

    -- Periodic dump
    if os.clock() - lastDump >= cfg.returnInterval then
      moveToXZ(0, 0)
      dumpLoot(cfg.dumpChestDir)
      refuel()
      lastDump = os.clock()
    end

    showStatus(cfg)
  end

  -- Return home
  moveToXZ(0, 0)
  faceDir(0)
  dumpLoot(cfg.dumpChestDir)
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  local cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  ui.clear()
  ui.drawHeader("Mob Grinder", "Setup")

  term.setCursorPos(2, 3)
  print("Patrol area: " .. cfg.patrolWidth .. "x" .. cfg.patrolLength)
  term.setCursorPos(2, 4)
  print("Kill delay: " .. cfg.killDelay .. "s per cell")
  term.setCursorPos(2, 5)
  print("Dump interval: " .. cfg.returnInterval .. "s")
  term.setCursorPos(2, 6)
  print("Dump direction: " .. cfg.dumpChestDir)
  term.setCursorPos(2, 7)
  print("Fuel: " .. turtle.getFuelLevel())

  term.setCursorPos(2, 9)
  print("Setup tips:")
  term.setCursorPos(2, 10)
  print(" - Equip sword (will be replaced by pickaxe)")
  term.setCursorPos(2, 11)
  print(" - Place chest " .. cfg.dumpChestDir .. " of turtle at origin")
  term.setCursorPos(2, 12)
  print(" - Place turtle IN the kill box area")

  ui.drawFooter("[Enter] Start  [C] Config  [Q] Cancel")

  while true do
    local _, key = os.pullEvent("key")
    if key == keys.q then return end
    if key == keys.enter then break end
    if key == keys.c then
      local raw = ui.inputText("Patrol width (current " .. cfg.patrolWidth .. "): ")
      if tonumber(raw) then cfg.patrolWidth = tonumber(raw) end
      raw = ui.inputText("Patrol length (current " .. cfg.patrolLength .. "): ")
      if tonumber(raw) then cfg.patrolLength = tonumber(raw) end
      raw = ui.inputText("Kill delay (current " .. cfg.killDelay .. "): ")
      if tonumber(raw) then cfg.killDelay = tonumber(raw) end
      raw = ui.inputText("Dump interval seconds (current " .. cfg.returnInterval .. "): ")
      if tonumber(raw) then cfg.returnInterval = tonumber(raw) end
      local dirs = { "down", "up", "forward", "< Cancel" }
      local didx = ui.drawMenu(dirs, "Chest direction")
      if didx and didx <= 3 then cfg.dumpChestDir = dirs[didx] end
      config.save(CFG_FILE, cfg)
      main(); return
    end
  end

  print("Starting Mob Grinder...")
  print("Kill area: " .. cfg.patrolWidth .. "x" .. cfg.patrolLength)
  sleep(1)

  local ok, err = pcall(runGrinder, cfg)
  if not ok then
    print("Error: " .. tostring(err))
  end

  print("\nMob Grinder stopped.")
  print("Final stats:")
  print("  Kills: " .. stats.kills)
  print("  Items dumped: " .. stats.items)
  print("  Cycles: " .. stats.cycles)
  print("Press any key.")
  os.pullEvent("key")
end

main()
