-- remote_dash.lua
-- ATM10 Remote Base Dashboard
-- Device: Pocket Computer / Advanced Pocket Computer
-- Required: Wireless modem on pocket computer
-- Optional: None (base computer must have base_monitor running with net enabled)
--
-- Connects to your base computer over wireless rednet and shows
-- a compact status summary: power, storage, weather, players.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local ui     = require("ui")
local config = require("config")
local net    = require("net")

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────
local CFG_FILE   = "remote_dash.cfg"
local CACHE_FILE = "remote_dash_cache.cfg"
local DEFAULTS   = {
  channel         = 4200,
  baseId          = nil,
  refreshInterval = 10,
}

-- ─────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────
local function checkModem()
  if net.hasModem() then return true end
  ui.alert(
    "No wireless modem found!\n\n" ..
    "To use Remote Dash:\n" ..
    "1. Craft a Wireless Modem\n" ..
    "2. Right-click your Pocket Computer\n" ..
    "   while holding the modem to attach it\n\n" ..
    "Then reopen Remote Dash.",
    "error"
  )
  return false
end

-- ─────────────────────────────────────────────
-- Discovery: find a base computer on the network
-- ─────────────────────────────────────────────
local function discoverBase(cfg)
  ui.clear()
  ui.drawHeader("Remote Dash", "Searching...")
  local w, h = term.getSize()
  ui.writeCentered(4, "Broadcasting discovery ping...")
  ui.writeCentered(5, "Channel: " .. cfg.channel)

  net.open(cfg.channel)
  net.broadcast(cfg.channel, "atm10_discovery", { query = "base" })

  -- Listen for responses
  local found = {}
  local deadline = os.startTimer(5)

  while true do
    local evt, p1, p2, p3, p4 = os.pullEvent()

    if evt == "modem_message" then
      local msg = p4
      if type(msg) == "table" and msg.type == "atm10_discovery_reply" then
        local data = msg.data
        if type(data) == "table" then
          table.insert(found, {
            id    = msg.sender,
            label = data.label or ("Computer #" .. tostring(msg.sender)),
          })
        end
      end

    elseif evt == "timer" and p1 == deadline then
      break
    end
  end

  if #found == 0 then
    ui.alert(
      "No base computers found!\n\n" ..
      "Make sure your base computer:\n" ..
      "1. Has a wireless modem attached\n" ..
      "2. Is running base_monitor or hub\n\n" ..
      "Set the base ID manually in Settings.",
      "warn"
    )
    return nil
  end

  -- Let user pick
  local items = {}
  for _, b in ipairs(found) do
    table.insert(items, { label = b.label, description = "ID: " .. b.id })
  end
  table.insert(items, { label = "< Cancel" })

  local idx = ui.drawMenu(items, "Select Base Computer")
  if not idx or idx > #found then return nil end
  return found[idx]
end

-- ─────────────────────────────────────────────
-- Request status from base
-- ─────────────────────────────────────────────
local function requestStatus(cfg)
  net.open(cfg.channel)
  local response = net.requestResponse(cfg.channel, "atm10_status_request", {
    requester = os.getComputerID()
  }, 5)
  return response
end

-- ─────────────────────────────────────────────
-- Draw the compact dashboard
-- ─────────────────────────────────────────────
local function drawDash(data, cfg, cacheAge)
  local w, h = term.getSize()
  ui.clear()

  local isAdv = term.isColor()

  -- Header
  local label = cfg.baseLabel or "Base"
  ui.setColor(colors.blue, colors.black)
  term.setCursorPos(1, 1)
  term.write(string.rep(" ", w))
  ui.writeCentered(1, "ATM10 Remote | " .. label)
  ui.resetColor()

  local row = 3

  if not data then
    -- No data - show cached
    local cached = config.load(CACHE_FILE)
    if cached then
      data = cached
      cacheAge = cacheAge or "?"
    end
  end

  if not data then
    ui.setColor(colors.orange, colors.black)
    ui.writeCentered(row, "No connection to base.")
    row = row + 1
    ui.writeCentered(row, "Channel: " .. cfg.channel)
    row = row + 1
    ui.writeCentered(row, "Base ID: " .. (cfg.baseId and tostring(cfg.baseId) or "not set"))
    row = row + 1
    ui.setColor(colors.gray, colors.black)
    ui.writeCentered(row + 1, "Press R to retry")
    ui.resetColor()
    ui.drawFooter("[R] Retry  [S] Settings  [Q] Quit")
    return
  end

  -- Cache indicator
  if cacheAge then
    ui.setColor(colors.gray, colors.black)
    term.setCursorPos(1, 2)
    term.write("CACHED " .. tostring(cacheAge) .. "s ago":sub(1, w))
    ui.resetColor()
    row = 3
  end

  -- Power bar
  if data.power then
    local pct   = tonumber(data.power.pct) or 0
    local rateStr = ui.formatEnergy(math.abs(data.power.rate or 0)) .. "/t"
    local barColor = colors.lime
    if isAdv then
      if pct < 10 then barColor = colors.red
      elseif pct < 25 then barColor = colors.yellow end
    end
    ui.setColor(colors.gray, colors.black)
    term.setCursorPos(1, row)
    term.write("PWR:")
    ui.drawProgressBar(5, row, w - 9, pct, barColor, colors.gray, math.floor(pct) .. "%")
    ui.setColor(isAdv and barColor or nil, colors.black)
    term.setCursorPos(w - 3, row)
    term.write(rateStr:sub(-4))
    row = row + 1
    ui.resetColor()
  else
    ui.setColor(colors.gray, colors.black)
    term.setCursorPos(1, row)
    term.write("PWR: N/A")
    row = row + 1
    ui.resetColor()
  end

  -- Storage
  if data.storage then
    ui.setColor(colors.cyan, colors.black)
    term.setCursorPos(1, row)
    local itStr = "STO: " .. ui.formatNumber(data.storage.itemTypes or 0) .. " types"
    term.write(itStr:sub(1, w))
    row = row + 1
    ui.resetColor()
  end

  -- Environment
  if data.env then
    ui.setColor(colors.yellow, colors.black)
    term.setCursorPos(1, row)
    local timeStr = "Day " .. (data.env.day or "?")
    local weatherStr = "  " .. (data.env.weather or "clear"):sub(1, 6)
    term.write((timeStr .. weatherStr):sub(1, w))
    row = row + 1
    ui.resetColor()
  end

  -- Players
  if data.players then
    local names = data.players.players or {}
    ui.setColor(colors.lime, colors.black)
    term.setCursorPos(1, row)
    term.write(("Players: " .. #names):sub(1, w))
    row = row + 1
    ui.resetColor()
  end

  -- Alerts
  if data.alerts and #data.alerts > 0 then
    row = row + 1
    ui.setColor(colors.orange, colors.black)
    for _, alert in ipairs(data.alerts) do
      if row >= h - 1 then break end
      term.setCursorPos(1, row)
      term.write(("! " .. alert):sub(1, w))
      row = row + 1
    end
    ui.resetColor()
  end

  -- Refresh info
  ui.setColor(colors.gray, colors.black)
  term.setCursorPos(1, h - 1)
  term.write(("Refresh: " .. cfg.refreshInterval .. "s"):sub(1, w))
  ui.resetColor()

  ui.drawFooter("[R] Refresh  [S] Settings  [Q] Quit")
end

-- ─────────────────────────────────────────────
-- Settings
-- ─────────────────────────────────────────────
local function showSettings(cfg)
  while true do
    local items = {
      { label = "Channel: " .. cfg.channel,    description = "rednet channel" },
      { label = "Base ID: " .. (cfg.baseId and tostring(cfg.baseId) or "not set") },
      { label = "Refresh: " .. cfg.refreshInterval .. "s" },
      { label = "Discover Base",  description = "scan network" },
      { label = "< Back" },
    }
    local idx = ui.drawMenu(items, "Settings")
    if not idx or idx == 5 then return end

    if idx == 1 then
      local raw = ui.inputText("Channel (current " .. cfg.channel .. "): ")
      if tonumber(raw) then cfg.channel = tonumber(raw); config.save(CFG_FILE, cfg) end
    elseif idx == 2 then
      local raw = ui.inputText("Base computer ID: ")
      if tonumber(raw) then cfg.baseId = tonumber(raw); config.save(CFG_FILE, cfg) end
    elseif idx == 3 then
      local raw = ui.inputText("Refresh interval (s): ")
      if tonumber(raw) then cfg.refreshInterval = tonumber(raw); config.save(CFG_FILE, cfg) end
    elseif idx == 4 then
      local base = discoverBase(cfg)
      if base then
        cfg.baseId    = base.id
        cfg.baseLabel = base.label
        config.save(CFG_FILE, cfg)
        ui.alert("Base set: " .. base.label, "success")
      end
    end
  end
end

-- ─────────────────────────────────────────────
-- Main loop
-- ─────────────────────────────────────────────
local function main()
  if not checkModem() then return end

  local cfg = config.getOrDefault(CFG_FILE, DEFAULTS)
  net.open(cfg.channel)

  local dashRunning = true
  local timerId     = os.startTimer(1)
  local lastData    = nil
  local lastFetch   = 0
  local cacheAge    = nil

  -- Initial fetch
  drawDash(nil, cfg, nil)

  while dashRunning do
    local evt, p1 = os.pullEvent()

    if evt == "timer" and p1 == timerId then
      -- Fetch data
      local data = requestStatus(cfg)
      if data then
        lastData  = data
        lastFetch = os.clock()
        cacheAge  = nil
        config.save(CACHE_FILE, data)
      else
        -- Use cached
        local age = math.floor(os.clock() - lastFetch)
        cacheAge  = lastData and age or nil
      end
      drawDash(lastData, cfg, cacheAge)
      timerId = os.startTimer(cfg.refreshInterval)

    elseif evt == "key" then
      if p1 == keys.q or p1 == keys.backspace then
        dashRunning = false
      elseif p1 == keys.r then
        -- Force refresh
        local data = requestStatus(cfg)
        if data then
          lastData = data
          cacheAge = nil
          config.save(CACHE_FILE, data)
        end
        drawDash(lastData, cfg, cacheAge)
        timerId = os.startTimer(cfg.refreshInterval)
      elseif p1 == keys.s then
        showSettings(cfg)
        drawDash(lastData, cfg, cacheAge)
      end

    elseif evt == "terminate" then
      dashRunning = false
    end
  end

  ui.clear()
  ui.resetColor()
end

main()
