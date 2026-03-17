-- scoreboard.lua
-- ATM10 Multiplayer Scoreboard Display
-- Device: Computer / Advanced Computer
-- Required: Advanced Monitor
-- Optional: playerDetector (Advanced Peripherals) for live player list,
--           chatBox for announcements,
--           meBridge/rsBridge for storage stats
--
-- Shows a live multiplayer information board:
--   - Player list with online status
--   - Shared task/goal list
--   - Server announcements
--   - Storage totals
--   - Scrolling message ticker

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local ui     = require("ui")
local config = require("config")

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────
local CFG_FILE  = "scoreboard.cfg"
local DATA_FILE = "scoreboard_data.cfg"  -- shared data (tasks, messages)
local DEFAULTS  = {
  monitorSide   = "auto",
  textScale     = 1,
  refreshRate   = 5,
  tickerSpeed   = 0.5,     -- seconds per scroll step
  showPlayers   = true,
  showTasks     = true,
  showTicker    = true,
  serverName    = "ATM10 Server",
  layout        = "split", -- "split" = players left + tasks right, "full" = one big column
}

local DATA_DEFAULTS = {
  tasks        = {},
  messages     = {},   -- ticker messages
  announcements = {},  -- pinned announcements
  playerNotes  = {},   -- { name=string, note=string }
}

-- ─────────────────────────────────────────────
-- Peripheral helpers
-- ─────────────────────────────────────────────
local function findMonitor(cfg)
  if cfg.monitorSide ~= "auto" then
    local t = peripheral.getType(cfg.monitorSide)
    if t and t:find("monitor") then
      return peripheral.wrap(cfg.monitorSide), cfg.monitorSide
    end
  end
  local best, bestName, bestSz = nil, nil, 0
  local function check(name)
    local t = peripheral.getType(name)
    if t and t:find("monitor") then
      local m = peripheral.wrap(name)
      if m then
        local w, h = m.getSize()
        local sz = (w or 0) * (h or 0)
        if sz > bestSz then best, bestName, bestSz = m, name, sz end
      end
    end
  end
  for _, name in ipairs(peripheral.getNames()) do check(name) end
  for _, side in ipairs({"top","bottom","left","right","front","back"}) do check(side) end
  return best, bestName
end

local function wrapPeripheral(pType)
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == pType then return peripheral.wrap(name) end
  end
  for _, side in ipairs({"top","bottom","left","right","front","back"}) do
    if peripheral.getType(side) == pType then return peripheral.wrap(side) end
  end
  return nil
end

-- ─────────────────────────────────────────────
-- Monitor drawing helpers
-- ─────────────────────────────────────────────
local function mCenter(mon, y, text, fg, bg)
  local w = select(1, mon.getSize())
  if fg and mon.isColor and mon.isColor() then mon.setTextColor(fg) end
  if bg and mon.isColor and mon.isColor() then mon.setBackgroundColor(bg) end
  local x = math.max(1, math.floor((w - #text) / 2) + 1)
  mon.setCursorPos(x, y)
  mon.write(text:sub(1, w))
end

local function mWrite(mon, x, y, text, fg, bg)
  local w = select(1, mon.getSize())
  if fg and mon.isColor and mon.isColor() then mon.setTextColor(fg) end
  if bg and mon.isColor and mon.isColor() then mon.setBackgroundColor(bg) end
  mon.setCursorPos(x, y)
  mon.write(text:sub(1, w - x + 1))
end

local function mFill(mon, y, char, fg, bg)
  local w = select(1, mon.getSize())
  if fg and mon.isColor and mon.isColor() then mon.setTextColor(fg) end
  if bg and mon.isColor and mon.isColor() then mon.setBackgroundColor(bg) end
  mon.setCursorPos(1, y)
  mon.write(string.rep(char or " ", w))
end

local function mRect(mon, x, y, w, h, char, bg)
  if bg and mon.isColor and mon.isColor() then mon.setBackgroundColor(bg) end
  for row = y, y + h - 1 do
    mon.setCursorPos(x, row)
    mon.write(string.rep(char or " ", w))
  end
end

-- ─────────────────────────────────────────────
-- Get player list
-- ─────────────────────────────────────────────
local function getOnlinePlayers(playerDet)
  if not playerDet then return {} end
  -- Try getOnlinePlayers first (returns name strings)
  local ok, result = pcall(function()
    if playerDet.getOnlinePlayers then
      return playerDet.getOnlinePlayers()
    end
    if playerDet.getPlayersInRange then
      return playerDet.getPlayersInRange(512)
    end
    return {}
  end)
  if ok and type(result) == "table" then return result end
  return {}
end

-- ─────────────────────────────────────────────
-- Draw scoreboard to monitor
-- ─────────────────────────────────────────────
local function drawScoreboard(mon, cfg, data, players, storage, tickerOffset)
  local w, h   = mon.getSize()
  local isAdv  = mon.isColor and mon.isColor() or false

  -- Full clear
  if isAdv then
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
  end
  mon.clear()

  local row = 1

  -- ── Header ──
  mFill(mon, 1, " ", colors.white, colors.blue)
  local headerText = " " .. cfg.serverName .. " "
  local timeStr = " " .. textutils.formatTime(os.time(), false) .. " "
  mWrite(mon, 1, 1, headerText, colors.white, colors.blue)
  mWrite(mon, w - #timeStr + 1, 1, timeStr, colors.yellow, colors.blue)
  row = 2

  if cfg.layout == "split" and w >= 30 then
    -- ── SPLIT LAYOUT ──
    local midX  = math.floor(w / 2)
    local leftW = midX - 1
    local rightW = w - midX - 1

    -- Divider
    for r = 2, h - (cfg.showTicker and 2 or 0) do
      if isAdv then mon.setTextColor(colors.gray) end
      mon.setCursorPos(midX, r)
      mon.write("|")
    end

    -- LEFT: Players
    if isAdv then mon.setTextColor(colors.lime) end
    mon.setCursorPos(1, row)
    mon.write("Players (" .. #players .. ")")

    local pRow = row + 1
    for _, p in ipairs(players) do
      if pRow >= h - (cfg.showTicker and 2 or 1) then break end
      local name = type(p) == "string" and p or (p.player or p.name or "?")
      local dist = type(p) == "table" and p.distance and string.format(" %.0fm", p.distance) or ""

      if isAdv then mon.setTextColor(colors.white) end
      mon.setCursorPos(1, pRow)
      mon.write((" " .. name .. dist):sub(1, leftW))
      pRow = pRow + 1
    end

    if #players == 0 then
      if isAdv then mon.setTextColor(colors.gray) end
      mon.setCursorPos(1, pRow)
      mon.write(" (none online)")
    end

    -- RIGHT: Tasks
    if isAdv then mon.setTextColor(colors.yellow) end
    mon.setCursorPos(midX + 1, row)
    local doneCount = 0
    for _, t in ipairs(data.tasks) do
      if t.done then doneCount = doneCount + 1 end
    end
    mon.write("Tasks (" .. doneCount .. "/" .. #data.tasks .. ")")

    local tRow = row + 1
    for _, task in ipairs(data.tasks) do
      if tRow >= h - (cfg.showTicker and 2 or 1) then break end
      local icon = task.done and "[x]" or "[ ]"
      if isAdv then
        mon.setTextColor(task.done and colors.lime or colors.white)
      end
      mon.setCursorPos(midX + 1, tRow)
      mon.write((" " .. icon .. " " .. (task.text or "?")):sub(1, rightW))
      tRow = tRow + 1
    end

    if #data.tasks == 0 then
      if isAdv then mon.setTextColor(colors.gray) end
      mon.setCursorPos(midX + 1, tRow)
      mon.write(" (no tasks)")
    end

    -- Storage row (if space)
    if storage and tRow < h - (cfg.showTicker and 2 or 1) then
      if isAdv then mon.setTextColor(colors.cyan) end
      mon.setCursorPos(midX + 1, tRow)
      mon.write((" STO: " .. ui.formatNumber(storage.itemTypes or 0) .. " types"):sub(1, rightW))
    end

  else
    -- ── FULL LAYOUT (single column or narrow monitor) ──
    -- Players
    if cfg.showPlayers then
      if isAdv then mon.setTextColor(colors.lime) end
      mon.setCursorPos(1, row)
      mon.write("Online (" .. #players .. "):")
      row = row + 1

      for _, p in ipairs(players) do
        if row >= h - (cfg.showTasks and 4 or 0) - (cfg.showTicker and 2 or 0) then break end
        local name = type(p) == "string" and p or (p.player or p.name or "?")
        if isAdv then mon.setTextColor(colors.white) end
        mon.setCursorPos(2, row)
        mon.write(name:sub(1, w - 2))
        row = row + 1
      end

      if #players == 0 then
        if isAdv then mon.setTextColor(colors.gray) end
        mon.setCursorPos(2, row)
        mon.write("No players online")
        row = row + 1
      end

      -- Divider
      if isAdv then mon.setTextColor(colors.gray) end
      mon.setCursorPos(1, row)
      mon.write(string.rep("-", w))
      row = row + 1
    end

    -- Tasks
    if cfg.showTasks then
      if isAdv then mon.setTextColor(colors.yellow) end
      mon.setCursorPos(1, row)
      local doneCount = 0
      for _, t in ipairs(data.tasks) do if t.done then doneCount = doneCount + 1 end end
      mon.write("Tasks " .. doneCount .. "/" .. #data.tasks)
      row = row + 1

      for _, task in ipairs(data.tasks) do
        if row >= h - (cfg.showTicker and 2 or 1) then break end
        local icon = task.done and "[x] " or "[ ] "
        if isAdv then
          mon.setTextColor(task.done and colors.lime or colors.white)
        end
        mon.setCursorPos(1, row)
        mon.write((icon .. (task.text or "?")):sub(1, w))
        row = row + 1
      end
    end

    -- Announcements
    if #data.announcements > 0 then
      if isAdv then
        mFill(mon, row, " ", colors.white, colors.orange)
        mon.setTextColor(colors.white)
        mon.setBackgroundColor(colors.orange)
      end
      mon.setCursorPos(1, row)
      mon.write(("! " .. data.announcements[1].text):sub(1, w))
      row = row + 1
      if isAdv then
        mon.setBackgroundColor(colors.black)
        mon.setTextColor(colors.white)
      end
    end
  end

  -- ── Ticker (scrolling messages) ──
  if cfg.showTicker and #data.messages > 0 then
    local tickerY = h - 1

    -- Separator
    if isAdv then
      mFill(mon, tickerY - 1, " ", colors.white, colors.gray)
      mon.setTextColor(colors.white)
      mon.setBackgroundColor(colors.gray)
    end
    mon.setCursorPos(1, tickerY - 1)
    mon.write(string.rep("-", w))

    -- Build full ticker string
    local fullTicker = ""
    for _, msg in ipairs(data.messages) do
      fullTicker = fullTicker .. "  " .. msg.text .. "   ***   "
    end

    -- Scroll: show a window of w characters from offset
    local tickerLen  = #fullTicker
    local offset     = (tickerOffset or 0) % tickerLen
    local visible    = ""
    for i = 1, w do
      local charIdx = (offset + i - 1) % tickerLen + 1
      visible = visible .. fullTicker:sub(charIdx, charIdx)
    end

    if isAdv then
      mFill(mon, tickerY, " ", colors.black, colors.cyan)
      mon.setTextColor(colors.black)
      mon.setBackgroundColor(colors.cyan)
    end
    mon.setCursorPos(1, tickerY)
    mon.write(visible:sub(1, w))
    if isAdv then
      mon.setBackgroundColor(colors.black)
      mon.setTextColor(colors.white)
    end
  end
end

-- ─────────────────────────────────────────────
-- Manage tasks (terminal)
-- ─────────────────────────────────────────────
local function manageTasks(data)
  while true do
    local items = {}
    for i, t in ipairs(data.tasks) do
      local prefix = t.done and "[x] " or "[ ] "
      table.insert(items, { label = prefix .. (t.text or "?"):sub(1, 24) })
    end
    table.insert(items, { label = "+ Add Task" })
    table.insert(items, { label = "< Back" })

    local idx = ui.drawMenu(items, "Tasks (" .. #data.tasks .. ")")
    if not idx or idx == #items then return end

    if idx == #items - 1 then
      local text = ui.inputText("Task description: ")
      if text and text ~= "" then
        table.insert(data.tasks, { text = text, done = false })
        config.save(DATA_FILE, data)
        ui.alert("Task added.", "success")
      end
    else
      local task = data.tasks[idx]
      local opts = {
        { label = task.done and "Mark incomplete" or "Mark complete" },
        { label = "Edit text" },
        { label = "Delete" },
        { label = "< Cancel" },
      }
      local oidx = ui.drawMenu(opts, task.text or "Task")
      if oidx == 1 then
        task.done = not task.done
        config.save(DATA_FILE, data)
      elseif oidx == 2 then
        local raw = ui.inputText("New text: ", task.text)
        if raw and raw ~= "" then task.text = raw; config.save(DATA_FILE, data) end
      elseif oidx == 3 then
        if ui.confirm("Delete '" .. (task.text or "?") .. "'?") then
          table.remove(data.tasks, idx)
          config.save(DATA_FILE, data)
        end
      end
    end
  end
end

-- ─────────────────────────────────────────────
-- Manage messages/ticker (terminal)
-- ─────────────────────────────────────────────
local function manageMessages(data)
  while true do
    local items = {}
    for _, m in ipairs(data.messages) do
      table.insert(items, { label = m.text:sub(1, 26) })
    end
    table.insert(items, { label = "+ Add Message" })
    table.insert(items, { label = "< Back" })

    local idx = ui.drawMenu(items, "Ticker Messages")
    if not idx or idx == #items then return end

    if idx == #items - 1 then
      local text = ui.inputText("Ticker message: ")
      if text and text ~= "" then
        table.insert(data.messages, { text = text })
        config.save(DATA_FILE, data)
        ui.alert("Message added.", "success")
      end
    else
      local msg = data.messages[idx]
      if ui.confirm("Delete message?") then
        table.remove(data.messages, idx)
        config.save(DATA_FILE, data)
      end
    end
  end
end

-- ─────────────────────────────────────────────
-- Manage announcements
-- ─────────────────────────────────────────────
local function manageAnnouncements(data)
  while true do
    local items = {}
    for _, a in ipairs(data.announcements) do
      table.insert(items, { label = ("! " .. a.text):sub(1, 26) })
    end
    table.insert(items, { label = "+ Add Announcement" })
    table.insert(items, { label = "< Back" })

    local idx = ui.drawMenu(items, "Announcements")
    if not idx or idx == #items then return end

    if idx == #items - 1 then
      local text = ui.inputText("Announcement: ")
      if text and text ~= "" then
        table.insert(data.announcements, { text = text })
        config.save(DATA_FILE, data)
        ui.alert("Announcement added.", "success")
      end
    else
      if ui.confirm("Delete announcement?") then
        table.remove(data.announcements, idx)
        config.save(DATA_FILE, data)
      end
    end
  end
end

-- ─────────────────────────────────────────────
-- Settings
-- ─────────────────────────────────────────────
local function showSettings(cfg)
  while true do
    local items = {
      { label = "Server name: " .. cfg.serverName:sub(1,16) },
      { label = "Monitor: " .. cfg.monitorSide },
      { label = "Text scale: " .. cfg.textScale },
      { label = "Refresh: " .. cfg.refreshRate .. "s" },
      { label = "Layout: " .. cfg.layout, description = "split/full" },
      { label = "Show ticker: " .. (cfg.showTicker and "yes" or "no") },
      { label = "< Back" },
    }
    local idx = ui.drawMenu(items, "Scoreboard Settings")
    if not idx or idx == 7 then return end

    if idx == 1 then
      local raw = ui.inputText("Server name: ", cfg.serverName)
      if raw and raw ~= "" then cfg.serverName = raw; config.save(CFG_FILE, cfg) end
    elseif idx == 2 then
      local raw = ui.inputText("Monitor side/name: ", cfg.monitorSide)
      if raw and raw ~= "" then cfg.monitorSide = raw; config.save(CFG_FILE, cfg) end
    elseif idx == 3 then
      local raw = ui.inputText("Text scale (0.5/1/1.5/2/3): ")
      local v = tonumber(raw)
      if v then cfg.textScale = v; config.save(CFG_FILE, cfg) end
    elseif idx == 4 then
      local raw = ui.inputText("Refresh interval (s): ")
      local v = tonumber(raw)
      if v and v >= 1 then cfg.refreshRate = v; config.save(CFG_FILE, cfg) end
    elseif idx == 5 then
      cfg.layout = cfg.layout == "split" and "full" or "split"
      config.save(CFG_FILE, cfg)
    elseif idx == 6 then
      cfg.showTicker = not cfg.showTicker
      config.save(CFG_FILE, cfg)
    end
  end
end

-- ─────────────────────────────────────────────
-- Main display loop
-- ─────────────────────────────────────────────
local function runDisplay(mon, cfg)
  local playerDet = wrapPeripheral("playerDetector")
  local meBridge  = wrapPeripheral("meBridge") or wrapPeripheral("rsBridge")

  if mon.setTextScale then
    pcall(function() mon.setTextScale(cfg.textScale or 1) end)
  end

  local running      = true
  local refreshTimer = os.startTimer(cfg.refreshRate)
  local tickerTimer  = os.startTimer(cfg.tickerSpeed)
  local tickerOffset = 0
  local lastPlayers  = {}
  local lastStorage  = nil

  -- Load shared data
  local data = config.getOrDefault(DATA_FILE, DATA_DEFAULTS)

  local function fetchData()
    lastPlayers = getOnlinePlayers(playerDet)
    if meBridge then
      local ok, items = pcall(function()
        if meBridge.listItems then return meBridge.listItems()
        elseif meBridge.getItems then return meBridge.getItems()
        else return {} end
      end)
      if ok then
        local ok2, types = pcall(function()
          if meBridge.getTotalItemTypes then return meBridge.getTotalItemTypes() end
          return #items
        end)
        lastStorage = { itemTypes = ok2 and types or #items }
      end
    end
    -- Reload data file in case another computer updated it
    local fresh = config.load(DATA_FILE)
    if fresh then data = fresh end
  end

  local function redraw()
    local oldTerm = term.redirect(mon)
    pcall(function()
      drawScoreboard(mon, cfg, data, lastPlayers, lastStorage, tickerOffset)
    end)
    term.redirect(oldTerm)
  end

  fetchData()
  redraw()

  -- Host terminal instructions
  term.clear()
  term.setCursorPos(1, 1)
  ui.drawHeader("Scoreboard", "Running")
  term.setCursorPos(1, 3)
  print("Keys: [Q] quit  [T] tasks  [M] messages")
  print("      [A] announcements")
  print("Players: " .. #lastPlayers)

  while running do
    local evt, p1, p2 = os.pullEvent()

    if evt == "timer" then
      if p1 == refreshTimer then
        fetchData()
        redraw()
        refreshTimer = os.startTimer(cfg.refreshRate)
        term.setCursorPos(1, 5)
        term.write("Players: " .. #lastPlayers .. "     ")

      elseif p1 == tickerTimer then
        tickerOffset = tickerOffset + 1
        -- Only redraw ticker portion (full redraw is ok for simplicity)
        if cfg.showTicker and #data.messages > 0 then
          redraw()
        end
        tickerTimer = os.startTimer(cfg.tickerSpeed)
      end

    elseif evt == "key" then
      if p1 == keys.q then
        running = false
      elseif p1 == keys.t then
        manageTasks(data)
        fetchData(); redraw()
      elseif p1 == keys.m then
        manageMessages(data)
        fetchData(); redraw()
      elseif p1 == keys.a then
        manageAnnouncements(data)
        fetchData(); redraw()
      elseif p1 == keys.r then
        fetchData(); redraw()
      end

    elseif evt == "monitor_touch" then
      -- Touch bottom half = cycle players shown, top = toggle ticker
      local _, mh = mon.getSize()
      if p2 < mh / 2 then
        cfg.showTicker = not cfg.showTicker
        config.save(CFG_FILE, cfg)
      end
      redraw()

    elseif evt == "terminate" then
      running = false
    end
  end

  -- Clear monitor
  local oldTerm = term.redirect(mon)
  pcall(function()
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1, 1)
  end)
  term.redirect(oldTerm)
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  local cfg  = config.getOrDefault(CFG_FILE, DEFAULTS)
  local data = config.getOrDefault(DATA_FILE, DATA_DEFAULTS)

  local mon, monName = findMonitor(cfg)
  if not mon then
    ui.alert(
      "No monitor found!\n\n" ..
      "Attach an Advanced Monitor\n" ..
      "to use the Scoreboard.",
      "error"
    )
    return
  end
  cfg.monitorSide = monName

  local running = true
  while running do
    local w, h = mon.getSize()
    local tasksDone = 0
    for _, t in ipairs(data.tasks) do if t.done then tasksDone = tasksDone + 1 end end

    local items = {
      { label = "Start Scoreboard",    description = monName .. " " .. w .. "x" .. h },
      { label = "Manage Tasks",        description = tasksDone .. "/" .. #data.tasks .. " done" },
      { label = "Ticker Messages",     description = #data.messages .. " messages" },
      { label = "Announcements",       description = #data.announcements .. " pinned" },
      { label = "Settings",            description = "scale, layout" },
      { label = "< Back to Hub",       description = "" },
    }

    local idx = ui.drawMenu(items, "Scoreboard")
    if not idx or idx == 6 then running = false; break end

    if idx == 1 then
      runDisplay(mon, cfg)
      mon, monName = findMonitor(cfg)
      if not mon then
        ui.alert("Monitor disconnected!", "error"); return
      end
      -- Reload data in case it changed
      data = config.getOrDefault(DATA_FILE, DATA_DEFAULTS)
    elseif idx == 2 then
      data = config.getOrDefault(DATA_FILE, DATA_DEFAULTS)
      manageTasks(data)
    elseif idx == 3 then
      data = config.getOrDefault(DATA_FILE, DATA_DEFAULTS)
      manageMessages(data)
    elseif idx == 4 then
      data = config.getOrDefault(DATA_FILE, DATA_DEFAULTS)
      manageAnnouncements(data)
    elseif idx == 5 then
      showSettings(cfg)
    end
  end
end

main()
