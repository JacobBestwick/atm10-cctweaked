-- tunnel_bore.lua
-- ATM10 Long-Distance Tunnel Builder
-- Device: Turtle / Advanced Turtle
-- Required: Turtle with pickaxe
-- Optional: None
--
-- Bores a lit, 3-tall tunnel in the current direction.
-- Perfect for connecting bases, rail lines, or reaching
-- distant Waystones in your ATM10 world.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local ui     = require("ui")
local config = require("config")

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────
local CFG_FILE = "tunnel_bore.cfg"
local DEFAULTS = {
  length        = 64,
  tunnelHeight  = 3,
  placeTorches  = true,
  torchSpacing  = 8,
  placeRails    = false,
  sealLiquid    = true,
  fillFloor     = true,   -- fill air/lava below floor
  torchSide     = "left", -- "left", "right", or "wall"
}

-- ─────────────────────────────────────────────
-- State
-- ─────────────────────────────────────────────
local blocksMined = 0
local torchesPlaced = 0
local railsPlaced   = 0
local liquidSeals   = 0

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

local function refuel()
  local ok = false
  for i = 1, 16 do
    turtle.select(i)
    if turtle.refuel(0) then
      turtle.refuel()
      ok = true
      if turtle.getFuelLevel() > 1000 then break end
    end
  end
  turtle.select(1)
  return ok
end

-- ─────────────────────────────────────────────
-- Liquid detection and sealing
-- ─────────────────────────────────────────────
local function isLiquid(data)
  if not data then return false end
  local n = (data.name or ""):lower()
  return n:find("lava") or n:find("water") or n:find("flowing")
end

local function sealLiquidFront()
  local ok, data = turtle.inspect()
  if ok and isLiquid(data) then
    local cobble = findItem("cobblestone") or findItem("stone") or findItem("dirt")
    if cobble then
      turtle.select(cobble)
      turtle.place()
      turtle.select(1)
      liquidSeals = liquidSeals + 1
      return true
    end
  end
  return false
end

local function sealLiquidAbove()
  local ok, data = turtle.inspectUp()
  if ok and isLiquid(data) then
    local cobble = findItem("cobblestone") or findItem("stone")
    if cobble then
      turtle.select(cobble)
      turtle.placeUp()
      turtle.select(1)
      liquidSeals = liquidSeals + 1
      return true
    end
  end
  return false
end

local function sealLiquidBelow()
  local ok, data = turtle.inspectDown()
  if ok and isLiquid(data) then
    local cobble = findItem("cobblestone") or findItem("stone")
    if cobble then
      turtle.select(cobble)
      turtle.placeDown()
      turtle.select(1)
      liquidSeals = liquidSeals + 1
      return true
    end
  end
  return false
end

-- ─────────────────────────────────────────────
-- Gravel/sand ceiling support
-- ─────────────────────────────────────────────
local function supportCeiling()
  local ok, data = turtle.inspectUp()
  if ok and data then
    local n = (data.name or ""):lower()
    if n:find("gravel") or n:find("sand") then
      local cobble = findItem("cobblestone") or findItem("stone")
      if cobble then
        turtle.select(cobble)
        turtle.placeUp()
        turtle.select(1)
      end
    end
  end
end

-- ─────────────────────────────────────────────
-- Dig a single 1-wide column (height=3)
-- Turtle is at floor level, digs forward then up
-- ─────────────────────────────────────────────
local function digColumn(cfg)
  -- Before digging, check for liquid
  if cfg.sealLiquid then sealLiquidFront() end

  -- Dig floor-level block
  turtle.dig()
  blocksMined = blocksMined + 1

  -- Move forward at floor level
  for i = 1, 5 do
    if turtle.forward() then break end
    sleep(0.3)
  end

  -- Dig the rest of the height (rows above floor level)
  for h = 2, cfg.tunnelHeight do
    if cfg.sealLiquid then sealLiquidAbove() end
    supportCeiling()
    turtle.digUp()
    blocksMined = blocksMined + 1
    turtle.up()
  end

  -- Come back down
  for h = 2, cfg.tunnelHeight do
    turtle.down()
  end

  -- Ensure floor exists (fill air/lava below)
  if cfg.fillFloor then
    local floorOk, floorData = turtle.inspectDown()
    if not floorOk or isLiquid(floorData) then
      local cobble = findItem("cobblestone") or findItem("stone")
      if cobble then
        turtle.select(cobble)
        turtle.placeDown()
        turtle.select(1)
      end
    end
  end
end

-- ─────────────────────────────────────────────
-- Place torch on wall
-- ─────────────────────────────────────────────
local function placeTorch(side)
  local torchSlot = findItem("torch")
  if not torchSlot then return false end
  turtle.select(torchSlot)
  local ok = false
  if side == "left" then
    turtle.turnLeft()
    ok = turtle.place()
    turtle.turnRight()
  elseif side == "right" then
    turtle.turnRight()
    ok = turtle.place()
    turtle.turnLeft()
  else
    ok = turtle.placeDown()
  end
  turtle.select(1)
  if ok then torchesPlaced = torchesPlaced + 1 end
  return ok
end

-- ─────────────────────────────────────────────
-- Place rail
-- ─────────────────────────────────────────────
local function placeRail()
  local railSlot = findItem("rail") or findItem("powered_rail")
  if not railSlot then return false end
  turtle.select(railSlot)
  local ok = turtle.placeDown()
  turtle.select(1)
  if ok then railsPlaced = railsPlaced + 1 end
  return ok
end

-- ─────────────────────────────────────────────
-- Status display
-- ─────────────────────────────────────────────
local function showStatus(cfg, progress)
  term.clear()
  term.setCursorPos(1, 1)
  ui.drawHeader("Tunnel Bore", progress .. "/" .. cfg.length .. " blocks")
  local w, _ = term.getSize()
  local pct  = math.floor(progress / cfg.length * 100)

  ui.drawProgressBar(1, 2, w, pct, colors.lime, colors.gray,
    progress .. "/" .. cfg.length .. " (" .. pct .. "%)")

  local row = 4
  local function line(text, color)
    ui.setColor(color or colors.white, colors.black)
    term.setCursorPos(2, row)
    term.write(text:sub(1, w - 2))
    row = row + 1
    ui.resetColor()
  end

  line("Blocks mined:   " .. blocksMined,  colors.cyan)
  line("Torches placed: " .. torchesPlaced, colors.yellow)
  if cfg.placeRails then
    line("Rails placed:   " .. railsPlaced, colors.orange)
  end
  if cfg.sealLiquid then
    line("Liquid seals:   " .. liquidSeals, colors.lightBlue)
  end
  line("Fuel:           " .. turtle.getFuelLevel(),
       turtle.getFuelLevel() < 200 and colors.orange or colors.white)

  ui.drawFooter("Boring tunnel...")
end

-- ─────────────────────────────────────────────
-- Main tunnel boring loop
-- ─────────────────────────────────────────────
local function runBore(cfg)
  local torchCounter = 0

  for i = 1, cfg.length do
    -- Check fuel
    if turtle.getFuelLevel() < 50 then
      refuel()
      if turtle.getFuelLevel() < 20 then
        print("Fuel critically low! Stopping.")
        return i - 1
      end
    end

    -- Dig column
    digColumn(cfg)

    torchCounter = torchCounter + 1

    -- Place torch
    if cfg.placeTorches and torchCounter >= cfg.torchSpacing then
      placeTorch(cfg.torchSide)
      torchCounter = 0
    end

    -- Place rail
    if cfg.placeRails then
      placeRail()
    end

    -- Status update every 5 blocks
    if i % 5 == 0 then
      showStatus(cfg, i)
    end
  end

  return cfg.length
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  local cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  ui.clear()
  ui.drawHeader("Tunnel Bore", "Setup")

  local w, _ = term.getSize()
  local row = 3

  local function cfgLine(label, value, color)
    term.setCursorPos(2, row)
    ui.setColor(colors.cyan, colors.black)
    term.write(label .. ": ")
    ui.setColor(color or colors.white, colors.black)
    term.write(tostring(value):sub(1, w - #label - 4))
    ui.resetColor()
    row = row + 1
  end

  cfgLine("Length",       cfg.length .. " blocks")
  cfgLine("Height",       cfg.tunnelHeight .. " blocks tall")
  cfgLine("Torches",      cfg.placeTorches and ("every " .. cfg.torchSpacing .. "m") or "no")
  cfgLine("Rails",        cfg.placeRails and "yes" or "no")
  cfgLine("Seal liquids", cfg.sealLiquid and "yes" or "no")
  cfgLine("Fuel",         turtle.getFuelLevel(),
          turtle.getFuelLevel() < cfg.length * 3 and colors.orange or colors.white)

  -- Fuel estimate
  local estFuel = cfg.length * (cfg.tunnelHeight + 2)
  row = row + 1
  cfgLine("Est. fuel needed", "~" .. estFuel,
    turtle.getFuelLevel() < estFuel and colors.orange or colors.lime)

  -- Material requirements
  row = row + 1
  if cfg.placeTorches then
    cfgLine("Torches needed", "~" .. math.ceil(cfg.length / cfg.torchSpacing))
  end
  if cfg.placeRails then
    cfgLine("Rails needed", cfg.length)
  end
  cfgLine("Cobblestone", "for liquid sealing (keep some in inv)")

  ui.drawFooter("[Enter] Start  [C] Config  [Q] Cancel")

  while true do
    local _, key = os.pullEvent("key")
    if key == keys.q then return end
    if key == keys.enter then break end
    if key == keys.c then
      local raw = ui.inputText("Length (current " .. cfg.length .. "): ")
      if tonumber(raw) then cfg.length = tonumber(raw) end
      raw = ui.inputText("Place torches? (y/n, current " .. (cfg.placeTorches and "y" or "n") .. "): ")
      if raw then cfg.placeTorches = (raw:lower() == "y") end
      raw = ui.inputText("Torch spacing (current " .. cfg.torchSpacing .. "): ")
      if tonumber(raw) then cfg.torchSpacing = tonumber(raw) end
      raw = ui.inputText("Place rails? (y/n, current " .. (cfg.placeRails and "y" or "n") .. "): ")
      if raw then cfg.placeRails = (raw:lower() == "y") end
      config.save(CFG_FILE, cfg)
      main(); return
    end
  end

  ui.clear()
  print("Starting Tunnel Bore...")
  print("Length: " .. cfg.length .. " blocks")
  print("Face the direction you want the tunnel to go.")
  print("Press Enter when ready...")
  io.read()

  local ok, err = pcall(function()
    local bored = runBore(cfg)
    print("\nTunnel bore complete!")
    print("Blocks bored: " .. bored)
    print("Torches placed: " .. torchesPlaced)
    if cfg.placeRails then print("Rails placed: " .. railsPlaced) end
  end)

  if not ok then
    print("Error: " .. tostring(err))
  end

  print("\nPress any key to return.")
  os.pullEvent("key")
end

main()
