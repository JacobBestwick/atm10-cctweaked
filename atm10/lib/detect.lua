-- detect.lua
-- Device and peripheral detection library for ATM10 automation suite

local detect = {}

-- Advanced Peripherals types
local AP_TYPES = {
  environmentDetector = true,
  playerDetector      = true,
  blockReader         = true,
  inventoryManager    = true,
  redstoneIntegrator  = true,
  geoScanner          = true,
  chatBox             = true,
  nbtStorage          = true,
  colonyIntegrator    = true,
}

local STORAGE_TYPES = {
  meBridge = true,
  rsBridge = true,
}

local ENERGY_TYPES = {
  energyDetector = true,
}

-- ─────────────────────────────────────────────
-- Internal: check if a peripheral name matches a type.
-- Uses peripheral.hasType if available (CC:T 1.99+),
-- otherwise falls back to iterating peripheral.getType()
-- return values (which can be multiple in modern CC:T).
-- ─────────────────────────────────────────────
local function peripheralHasType(name, pType)
  -- peripheral.hasType is the correct API in CC:T 1.99+ (MC 1.19+)
  if peripheral.hasType then
    local ok, result = pcall(peripheral.hasType, name, pType)
    if ok then return result end
  end

  -- Fallback: peripheral.getType returns one or more type strings
  local ok, t1, t2, t3, t4, t5 = pcall(peripheral.getType, name)
  if not ok then return false end
  for _, t in ipairs({ t1, t2, t3, t4, t5 }) do
    if t == pType then return true end
  end
  return false
end

-- ─────────────────────────────────────────────
-- Device type detection
-- ─────────────────────────────────────────────

-- Returns one of: "computer", "advanced_computer", "turtle",
-- "advanced_turtle", "pocket", "advanced_pocket"
function detect.getDeviceType()
  local isTurtle = (turtle ~= nil)
  local isPocket = (pocket ~= nil)
  local isAdv    = term.isColor()

  if isTurtle     then return isAdv and "advanced_turtle" or "turtle"
  elseif isPocket then return isAdv and "advanced_pocket" or "pocket"
  else                 return isAdv and "advanced_computer" or "computer"
  end
end

function detect.isTurtle()   return turtle ~= nil end
function detect.isPocket()   return pocket ~= nil end
function detect.isAdvanced() return term.isColor() end

function detect.getDeviceName()
  local names = {
    computer          = "Computer",
    advanced_computer = "Advanced Computer",
    turtle            = "Turtle",
    advanced_turtle   = "Advanced Turtle",
    pocket            = "Pocket Computer",
    advanced_pocket   = "Advanced Pocket Computer",
  }
  return names[detect.getDeviceType()] or "Unknown Device"
end

function detect.getScreenSize()
  return term.getSize()
end

-- ─────────────────────────────────────────────
-- Peripheral discovery
-- ─────────────────────────────────────────────

-- Returns wrapped peripheral + name, or nil, nil.
-- Strategy:
--   1. peripheral.find(pType)  — most reliable, searches sides + wired network
--   2. Manual scan of peripheral.getNames() with hasType check
--   3. Manual side scan fallback
function detect.findPeripheral(pType)
  -- 1. peripheral.find — handles local sides AND wired network automatically
  local ok, found = pcall(peripheral.find, pType)
  if ok and found then
    -- find() returns the wrapped peripheral; also get its name
    local okN, names = pcall(peripheral.getNames)
    if okN and names then
      for _, name in ipairs(names) do
        if peripheralHasType(name, pType) then
          return found, name
        end
      end
    end
    return found, nil
  end

  -- 2. Scan all peripheral names (getNames includes sides + wired network)
  local okN, names = pcall(peripheral.getNames)
  if okN and names then
    for _, name in ipairs(names) do
      if peripheralHasType(name, pType) then
        local okW, wrapped = pcall(peripheral.wrap, name)
        if okW and wrapped then
          return wrapped, name
        end
      end
    end
  end

  -- 3. Explicit side scan (belt-and-braces fallback)
  for _, side in ipairs({ "top", "bottom", "left", "right", "front", "back" }) do
    if peripheral.isPresent(side) and peripheralHasType(side, pType) then
      local okW, wrapped = pcall(peripheral.wrap, side)
      if okW and wrapped then
        return wrapped, side
      end
    end
  end

  return nil, nil
end

function detect.hasPeripheral(pType)
  local p, _ = detect.findPeripheral(pType)
  return p ~= nil
end

-- ─────────────────────────────────────────────
-- Categorised peripheral listing
-- ─────────────────────────────────────────────
function detect.getPeripherals()
  local result = {
    monitors             = {},
    modems               = {},
    storage              = {},
    energy               = {},
    advanced_peripherals = {},
    misc                 = {},
  }

  local seen = {}

  local function classify(name)
    if seen[name] then return end

    -- Get all types for this peripheral
    local ok, t1, t2, t3, t4, t5 = pcall(peripheral.getType, name)
    if not ok or not t1 then return end

    seen[name] = true
    -- Use the first type for classification
    local pType = t1

    local entry = { name = name, type = pType }

    if pType == "monitor" or peripheralHasType(name, "monitor") then
      table.insert(result.monitors, entry)
    elseif pType == "modem" then
      table.insert(result.modems, entry)
    elseif STORAGE_TYPES[pType] then
      table.insert(result.storage, entry)
    elseif ENERGY_TYPES[pType] then
      table.insert(result.energy, entry)
    elseif AP_TYPES[pType] then
      table.insert(result.advanced_peripherals, entry)
    else
      table.insert(result.misc, entry)
    end
  end

  local ok, names = pcall(peripheral.getNames)
  if ok and names then
    for _, name in ipairs(names) do
      classify(name)
    end
  end

  return result
end

-- Returns all peripherals found via wired modems only
function detect.getNetworkedPeripherals()
  local result = {}
  for _, side in ipairs({ "top", "bottom", "left", "right", "front", "back" }) do
    if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
      local modem = peripheral.wrap(side)
      if modem and modem.getNamesRemote then
        local ok, names = pcall(modem.getNamesRemote)
        if ok and names then
          for _, remoteName in ipairs(names) do
            local ok2, remoteType = pcall(modem.getTypeRemote, remoteName)
            if ok2 and remoteType then
              table.insert(result, { name = remoteName, type = remoteType, via = side })
            end
          end
        end
      end
    end
  end
  return result
end

return detect
