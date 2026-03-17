-- detect.lua
-- Device and peripheral detection library for ATM10 automation suite

local detect = {}

-- Advanced Peripherals types
local AP_TYPES = {
  environmentDetector = true,
  playerDetector = true,
  blockReader = true,
  inventoryManager = true,
  redstoneIntegrator = true,
  geoScanner = true,
  chatBox = true,
  nbtStorage = true,
  colonyIntegrator = true,
}

local STORAGE_TYPES = {
  meBridge = true,
  rsBridge = true,
}

local ENERGY_TYPES = {
  energyDetector = true,
}

-- Returns one of: "computer", "advanced_computer", "turtle", "advanced_turtle",
-- "pocket", "advanced_pocket"
function detect.getDeviceType()
  local isTurtle = (turtle ~= nil)
  local isPocket = (pocket ~= nil)
  local isAdv = term.isColor()

  if isTurtle then
    return isAdv and "advanced_turtle" or "turtle"
  elseif isPocket then
    return isAdv and "advanced_pocket" or "pocket"
  else
    return isAdv and "advanced_computer" or "computer"
  end
end

function detect.isTurtle()
  return turtle ~= nil
end

function detect.isPocket()
  return pocket ~= nil
end

function detect.isAdvanced()
  return term.isColor()
end

function detect.getDeviceName()
  local dt = detect.getDeviceType()
  local names = {
    computer          = "Computer",
    advanced_computer = "Advanced Computer",
    turtle            = "Turtle",
    advanced_turtle   = "Advanced Turtle",
    pocket            = "Pocket Computer",
    advanced_pocket   = "Advanced Pocket Computer",
  }
  return names[dt] or "Unknown Device"
end

function detect.getScreenSize()
  return term.getSize()
end

-- Checks if a peripheral of pType exists locally or on the wired network
function detect.hasPeripheral(pType)
  local p, _ = detect.findPeripheral(pType)
  return p ~= nil
end

-- Returns wrapped peripheral (or nil) and name (or nil).
-- Checks local sides first, then networked via wired modems.
function detect.findPeripheral(pType)
  -- Check local sides
  local sides = { "top", "bottom", "left", "right", "front", "back" }
  for _, side in ipairs(sides) do
    if peripheral.isPresent(side) and peripheral.getType(side) == pType then
      return peripheral.wrap(side), side
    end
  end

  -- Check via peripheral.find (handles both local and networked in newer CC:T)
  local found = peripheral.find(pType)
  if found then
    -- Find its name
    for _, name in ipairs(peripheral.getNames()) do
      if peripheral.getType(name) == pType then
        return found, name
      end
    end
    return found, nil
  end

  -- Manual networked scan through wired modems
  for _, side in ipairs(sides) do
    if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
      local modem = peripheral.wrap(side)
      if modem and modem.getNamesRemote then
        local ok, names = pcall(modem.getNamesRemote)
        if ok and names then
          for _, remoteName in ipairs(names) do
            local ok2, remoteType = pcall(modem.getTypeRemote, remoteName)
            if ok2 and remoteType == pType then
              local ok3, wrapped = pcall(peripheral.wrap, remoteName)
              if ok3 and wrapped then
                return wrapped, remoteName
              end
            end
          end
        end
      end
    end
  end

  return nil, nil
end

-- Returns categorised table of all detected peripherals
-- { monitors={}, modems={}, storage={}, energy={}, advanced_peripherals={}, misc={} }
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

  local function classify(name, pType)
    if seen[name] then return end
    seen[name] = true

    local entry = { name = name, type = pType }

    if pType == "monitor" then
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

  -- Scan all known peripheral names (local + networked via CC:T peripheral API)
  local ok, names = pcall(peripheral.getNames)
  if ok and names then
    for _, name in ipairs(names) do
      local ok2, pType = pcall(peripheral.getType, name)
      if ok2 and pType then
        classify(name, pType)
      end
    end
  end

  return result
end

-- Returns table of { name, type, via } for peripherals found via wired modems
function detect.getNetworkedPeripherals()
  local result = {}
  local sides = { "top", "bottom", "left", "right", "front", "back" }

  for _, side in ipairs(sides) do
    if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
      local modem = peripheral.wrap(side)
      if modem and modem.getNamesRemote then
        local ok, names = pcall(modem.getNamesRemote)
        if ok and names then
          for _, remoteName in ipairs(names) do
            local ok2, remoteType = pcall(modem.getTypeRemote, remoteName)
            if ok2 and remoteType then
              table.insert(result, {
                name = remoteName,
                type = remoteType,
                via  = side,
              })
            end
          end
        end
      end
    end
  end

  return result
end

return detect
