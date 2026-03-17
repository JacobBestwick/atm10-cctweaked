-- storage.lua
-- AE2 ME Bridge / RS Bridge abstraction layer for ATM10 automation suite
-- Provides a unified API regardless of which storage mod is in use.
--
-- ME Bridge API  (Advanced Peripherals):
--   listItems()                         → { {name, displayName, count, isCraftable}, ... }
--   craftItem({name=..., count=...})    → { success, message }
--   isItemCraftable({name=...})         → bool
--   getEnergyUsage()                    → FE/t number
--   getCraftingCPUs()                   → { {storage, coProcessors, busy}, ... }
--   getUsedItemStorageSpace()           → number
--   getTotalItemStorageSpace()          → number
--
-- RS Bridge API (similar shape):
--   listItems()                         → same format
--   craftItem({name=..., count=...})    → result
--   isItemCraftable({name=...})         → bool
--   getEnergyUsage()                    → FE/t number
--   getUsedItemStorageSpace()           → number
--   getTotalItemStorageSpace()          → number

local storage = {}

-- ─────────────────────────────────────────────
-- Internal state
-- ─────────────────────────────────────────────
local _bridge = nil   -- wrapped peripheral
local _type   = "none" -- "ae2" | "rs" | "none"

-- ─────────────────────────────────────────────
-- Initialisation – finds ME/RS bridge
-- ─────────────────────────────────────────────

-- Scan peripheral.getNames() for a type match.
local function findByType(pType)
  local ok, names = pcall(peripheral.getNames)
  if not ok or not names then return nil end
  for _, name in ipairs(names) do
    local ok2, t = pcall(peripheral.getType, name)
    if ok2 and t == pType then
      local ok3, p = pcall(peripheral.wrap, name)
      if ok3 and p then return p end
    end
  end
  return nil
end

--- Locate a storage bridge peripheral.
--- Returns bool success, string type ("ae2"|"rs"|"none")
function storage.init()
  _bridge = nil
  _type   = "none"

  -- Prefer ME Bridge
  local me = findByType("meBridge")
  if me then
    _bridge = me
    _type   = "ae2"
    return true, "ae2"
  end

  -- Fall back to RS Bridge
  local rs = findByType("rsBridge")
  if rs then
    _bridge = rs
    _type   = "rs"
    return true, "rs"
  end

  return false, "none"
end

-- ─────────────────────────────────────────────
-- Status helpers
-- ─────────────────────────────────────────────

function storage.getType()
  return _type
end

function storage.isAvailable()
  if not _bridge then return false end
  -- Quick liveness check
  local ok, _ = pcall(function() _bridge.listItems() end)
  if not ok then
    _bridge = nil
    _type   = "none"
    return false
  end
  return true
end

-- ─────────────────────────────────────────────
-- Item queries
-- ─────────────────────────────────────────────

--- Return all items as { {name, displayName, count, craftable}, ... }
function storage.getItems()
  if not _bridge then return {} end
  local ok, items = pcall(function() return _bridge.listItems() end)
  if not ok or type(items) ~= "table" then return {} end

  local result = {}
  for _, item in ipairs(items) do
    table.insert(result, {
      name        = tostring(item.name        or ""),
      displayName = tostring(item.displayName or item.name or ""),
      count       = tonumber(item.count)      or 0,
      craftable   = item.isCraftable          or false,
    })
  end
  return result
end

--- Return {count, craftable} for the first item whose name or displayName
--- contains `query` (case-insensitive substring match), or nil if not found.
function storage.getItem(query)
  if not _bridge or not query then return nil end
  local q = query:lower()
  local ok, items = pcall(function() return _bridge.listItems() end)
  if not ok or type(items) ~= "table" then return nil end

  for _, item in ipairs(items) do
    local n  = (item.name        or ""):lower()
    local dn = (item.displayName or ""):lower()
    if n == q or dn == q or n:find(q, 1, true) or dn:find(q, 1, true) then
      return {
        count     = tonumber(item.count) or 0,
        craftable = item.isCraftable or false,
        name      = item.name or "",
        displayName = item.displayName or item.name or "",
      }
    end
  end
  return nil
end

--- Return all items whose name or displayName contain `query`.
function storage.searchItems(query)
  if not _bridge then return {} end
  query = (query or ""):lower()
  local ok, items = pcall(function() return _bridge.listItems() end)
  if not ok or type(items) ~= "table" then return {} end

  local result = {}
  for _, item in ipairs(items) do
    local n  = (item.name        or ""):lower()
    local dn = (item.displayName or ""):lower()
    if query == "" or n:find(query, 1, true) or dn:find(query, 1, true) then
      table.insert(result, {
        name        = item.name or "",
        displayName = item.displayName or item.name or "",
        count       = tonumber(item.count) or 0,
        craftable   = item.isCraftable or false,
      })
    end
  end
  return result
end

-- ─────────────────────────────────────────────
-- Crafting
-- ─────────────────────────────────────────────

--- Request crafting of `count` units of item `name`.
--- Returns bool success, string message.
function storage.craftItem(name, count)
  if not _bridge then
    return false, "No storage bridge connected"
  end
  count = math.max(1, tonumber(count) or 1)

  local ok, result = pcall(function()
    return _bridge.craftItem({ name = name, count = count })
  end)

  if not ok then
    return false, tostring(result)
  end

  -- Both ME and RS bridges return a table with a success/message field
  if type(result) == "table" then
    local success = result.success or result[1] or false
    local msg     = result.message or result[2] or "Craft requested"
    return success, tostring(msg)
  end

  -- Some versions return just a bool
  return result == true, result == true and "Craft requested" or "Craft failed"
end

--- Return active crafting jobs (ME Bridge only; RS returns empty list).
function storage.getCraftingJobs()
  if not _bridge then return {} end
  if _type ~= "ae2" then return {} end

  local ok, cpus = pcall(function() return _bridge.getCraftingCPUs() end)
  if not ok or type(cpus) ~= "table" then return {} end

  local jobs = {}
  for i, cpu in ipairs(cpus) do
    if cpu.busy then
      table.insert(jobs, {
        id          = i,
        storage     = cpu.storage     or 0,
        coProcessors = cpu.coProcessors or 0,
        busy        = true,
      })
    end
  end
  return jobs
end

-- ─────────────────────────────────────────────
-- Storage space
-- ─────────────────────────────────────────────

function storage.getUsedSpace()
  if not _bridge then return 0 end
  local ok, v = pcall(function() return _bridge.getUsedItemStorageSpace() end)
  return (ok and tonumber(v)) or 0
end

function storage.getTotalSpace()
  if not _bridge then return 0 end
  local ok, v = pcall(function() return _bridge.getTotalItemStorageSpace() end)
  return (ok and tonumber(v)) or 0
end

function storage.getEnergyUsage()
  if not _bridge then return 0 end
  local ok, v = pcall(function() return _bridge.getEnergyUsage() end)
  return (ok and tonumber(v)) or 0
end

return storage
