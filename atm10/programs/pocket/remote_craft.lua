-- remote_craft.lua
-- ATM10 Remote Crafting Requester
-- Device: Pocket Computer / Advanced Pocket Computer
-- Required: Wireless modem; base computer with craft_manager in server mode
-- Optional: None
--
-- Request items to be crafted in your AE2/RS network while
-- you're out exploring. Search items, send crafting requests,
-- and check the queue status remotely.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local ui     = require("ui")
local config = require("config")
local net    = require("net")

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────
local CFG_FILE = "remote_craft.cfg"
local DEFAULTS = {
  channel    = 4200,
  baseId     = nil,
  quickCraft = {
    { label = "Steel Casing x16",      name = "mekanism:steel_casing",          count = 16 },
    { label = "Basic Circuit x8",      name = "mekanism:basic_control_circuit", count = 8  },
    { label = "Osmium Ingot x64",      name = "mekanism:osmium_ingot",          count = 64 },
    { label = "Certus Quartz Dust x32",name = "ae2:certus_quartz_dust",         count = 32 },
    { label = "Fluix Crystal x16",     name = "ae2:fluix_crystal",              count = 16 },
  },
}

-- ─────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────
local function checkModem()
  if net.hasModem() then return true end
  ui.alert("No wireless modem!\nAttach one to use Remote Craft.", "error")
  return false
end

local function isConnected(cfg)
  return cfg.baseId ~= nil
end

local function sendRequest(cfg, reqType, data, timeout)
  net.open(cfg.channel)
  return net.requestResponse(cfg.channel, reqType, data, timeout or 5)
end

-- ─────────────────────────────────────────────
-- Connection status line
-- ─────────────────────────────────────────────
local function connStatus(cfg)
  if cfg.baseId then
    return "Base #" .. cfg.baseId
  end
  return "Not connected"
end

-- ─────────────────────────────────────────────
-- Search items
-- ─────────────────────────────────────────────
local function searchItems(cfg)
  if not isConnected(cfg) then
    ui.alert("Not connected to a base.\nUse Settings to connect.", "warn")
    return
  end

  local query = ui.inputText("Search (name or keyword): ")
  if not query or query == "" then return end

  -- Send search request
  ui.clear()
  ui.drawHeader("Remote Craft", "Searching...")
  ui.writeCentered(5, "Querying storage...")

  local response = sendRequest(cfg, "atm10_storage_search", { query = query }, 8)

  if not response then
    ui.alert("No response from base.\nIs craft_manager running?", "error")
    return
  end

  if type(response) ~= "table" or not response.items then
    ui.alert("Invalid response from base.", "error")
    return
  end

  local items = response.items
  if #items == 0 then
    ui.alert("No items matching '" .. query .. "' found in storage.", "warn")
    return
  end

  -- Show results and let user pick
  local w = select(1, term.getSize())
  local menuItems = {}
  for _, item in ipairs(items) do
    local countStr = ui.formatNumber(item.count or 0)
    local craftStr = item.craftable and " [C]" or ""
    table.insert(menuItems, {
      label       = (item.displayName or item.name):sub(1, w - 12),
      description = countStr .. craftStr,
    })
  end
  table.insert(menuItems, { label = "< Cancel" })

  local idx = ui.drawMenu(menuItems, "Search: " .. query)
  if not idx or idx > #items then return end

  local selected = items[idx]
  if not selected.craftable then
    ui.alert(selected.displayName .. "\n\nNot craftable.\n(No crafting pattern in AE2/RS)", "warn")
    return
  end

  -- Ask count
  local raw   = ui.inputText("How many to craft? ", "1")
  local count = tonumber(raw)
  if not count or count < 1 then
    ui.alert("Invalid count.", "warn")
    return
  end

  -- Send craft request
  ui.clear()
  ui.drawHeader("Remote Craft", "Requesting...")
  ui.writeCentered(5, "Requesting " .. count .. "x " .. (selected.displayName or selected.name))

  local craftResp = sendRequest(cfg, "atm10_craft_request", {
    name  = selected.name,
    count = math.floor(count),
  }, 8)

  if not craftResp then
    ui.alert("No response from base.\nRequest may or may not have been sent.", "warn")
    return
  end

  if craftResp.success then
    ui.alert("Crafting requested!\n" .. count .. "x " .. (selected.displayName or selected.name), "success")
  else
    ui.alert("Craft failed:\n" .. (craftResp.message or "Unknown error"), "error")
  end
end

-- ─────────────────────────────────────────────
-- Quick craft
-- ─────────────────────────────────────────────
local function quickCraft(cfg)
  if not isConnected(cfg) then
    ui.alert("Not connected to a base.", "warn")
    return
  end

  while true do
    local items = {}
    for _, qc in ipairs(cfg.quickCraft) do
      table.insert(items, { label = qc.label, description = "x" .. qc.count })
    end
    table.insert(items, { label = "+ Add Quick Craft" })
    table.insert(items, { label = "< Back" })

    local idx = ui.drawMenu(items, "Quick Craft")
    if not idx or idx == #items then return end

    if idx == #items - 1 then
      -- Add quick craft
      local label = ui.inputText("Label (e.g. 'Steel Casing x16'): ")
      if not label or label == "" then return end
      local name  = ui.inputText("Item ID (e.g. mekanism:steel_casing): ")
      if not name or name == "" then return end
      local raw   = ui.inputText("Count: ", "1")
      local count = tonumber(raw) or 1

      table.insert(cfg.quickCraft, {
        label = label,
        name  = name,
        count = math.floor(count),
      })
      config.save(CFG_FILE, cfg)
      ui.alert("Quick craft '" .. label .. "' added.", "success")

    else
      local qc = cfg.quickCraft[idx]
      -- Confirm and send
      if ui.confirm("Craft " .. qc.count .. "x " .. qc.label .. "?") then
        ui.clear()
        ui.drawHeader("Remote Craft", "Requesting...")
        ui.writeCentered(5, "Crafting: " .. qc.label)

        local resp = sendRequest(cfg, "atm10_craft_request", {
          name  = qc.name,
          count = qc.count,
        }, 8)

        if resp and resp.success then
          ui.alert("Crafting started!\n" .. qc.label, "success")
        elseif resp then
          ui.alert("Craft failed:\n" .. (resp.message or "?"), "error")
        else
          ui.alert("No response from base.", "warn")
        end
      end
    end
  end
end

-- ─────────────────────────────────────────────
-- Crafting queue
-- ─────────────────────────────────────────────
local function viewQueue(cfg)
  if not isConnected(cfg) then
    ui.alert("Not connected to a base.", "warn")
    return
  end

  ui.clear()
  ui.drawHeader("Remote Craft", "Fetching Queue...")
  ui.writeCentered(5, "Requesting crafting queue...")

  local resp = sendRequest(cfg, "atm10_craft_queue", {}, 8)

  if not resp then
    ui.alert("No response from base.\n(AE2 only — RS has no queue API)", "warn")
    return
  end

  if type(resp) ~= "table" or not resp.jobs then
    ui.alert("No crafting jobs active.", "info")
    return
  end

  local lines = {
    "Active Crafting Jobs",
    string.rep("-", 28),
  }
  if #resp.jobs == 0 then
    table.insert(lines, "(no active jobs)")
  else
    for i, job in ipairs(resp.jobs) do
      table.insert(lines, string.format("CPU %d: %s", i, job.busy and "BUSY" or "idle"))
    end
  end
  table.insert(lines, "")
  table.insert(lines, "Press Q to return.")

  ui.pager(lines, "Crafting Queue")
end

-- ─────────────────────────────────────────────
-- Settings
-- ─────────────────────────────────────────────
local function showSettings(cfg)
  while true do
    local items = {
      { label = "Channel: " .. cfg.channel },
      { label = "Base ID: " .. (cfg.baseId and tostring(cfg.baseId) or "not set") },
      { label = "< Back" },
    }
    local idx = ui.drawMenu(items, "Settings")
    if not idx or idx == 3 then return end

    if idx == 1 then
      local raw = ui.inputText("Channel: ", tostring(cfg.channel))
      if tonumber(raw) then cfg.channel = tonumber(raw); config.save(CFG_FILE, cfg) end
    elseif idx == 2 then
      local raw = ui.inputText("Base computer ID: ")
      if tonumber(raw) then cfg.baseId = tonumber(raw); config.save(CFG_FILE, cfg) end
    end
  end
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  if not checkModem() then return end

  local cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  local running = true
  while running do
    local w = select(1, term.getSize())
    local items = {
      { label = "Search Items",   description = "find & craft" },
      { label = "Quick Craft",    description = #cfg.quickCraft .. " presets" },
      { label = "Crafting Queue", description = "AE2 jobs" },
      { label = "Settings",       description = connStatus(cfg) },
      { label = "< Back to Hub",  description = "" },
    }

    local idx = ui.drawMenu(items, "Remote Craft")
    if not idx or idx == 5 then running = false; break end

    if idx == 1 then searchItems(cfg)
    elseif idx == 2 then quickCraft(cfg)
    elseif idx == 3 then viewQueue(cfg)
    elseif idx == 4 then showSettings(cfg)
    end
  end
end

main()
