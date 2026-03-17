-- gps_nav.lua
-- ATM10 GPS Navigator & Waypoint Manager
-- Device: Pocket Computer / Advanced Pocket Computer
-- Required: GPS towers in the world (4+ towers for 3D fix)
-- Optional: Wireless modem (for waypoint sharing)
--
-- Shows your current coordinates, manages named waypoints,
-- and gives heading/distance to selected destinations.

local basePath = "/atm10"
package.path = basePath .. "/lib/?.lua;" .. package.path
local ui     = require("ui")
local config = require("config")
local net    = require("net")

-- ─────────────────────────────────────────────
-- Config
-- ─────────────────────────────────────────────
local CFG_FILE = "gps_nav.cfg"
local DEFAULTS = {
  waypoints = {},
  -- Default template waypoints (all unset)
  lastX = nil, lastY = nil, lastZ = nil,
}

-- Preset waypoint templates
local PRESET_WAYPOINTS = {
  { name = "Home Base",       x = nil, y = nil, z = nil },
  { name = "Nether Portal",   x = nil, y = nil, z = nil },
  { name = "End Portal",      x = nil, y = nil, z = nil },
  { name = "Village",         x = nil, y = nil, z = nil },
  { name = "Ocean Monument",  x = nil, y = nil, z = nil },
}

-- ─────────────────────────────────────────────
-- GPS helpers
-- ─────────────────────────────────────────────
local function getPosition()
  local ok, x, y, z = pcall(gps.locate, 2)
  if ok and x then
    return x, y, z
  end
  -- Try without timeout
  ok, x, y, z = pcall(gps.locate)
  if ok and x then return x, y, z end
  return nil, nil, nil
end

local function distance(x1, y1, z1, x2, y2, z2)
  local dx = x2 - x1
  local dy = y2 - y1
  local dz = z2 - z1
  return math.sqrt(dx*dx + dy*dy + dz*dz), dx, dy, dz
end

-- Returns a direction string based on dx, dz
local function bearingStr(dx, dz)
  local angle = math.atan2(dx, -dz) * 180 / math.pi
  if angle < 0 then angle = angle + 360 end
  local dirs = { "N", "NE", "E", "SE", "S", "SW", "W", "NW", "N" }
  local idx   = math.floor((angle + 22.5) / 45) + 1
  return dirs[idx] or "?"
end

-- Big arrow for navigation display
local function bigArrow(bearing)
  local arrows = {
    N  = "  ^  ",
    NE = "   / ",
    E  = "  -> ",
    SE = "  \\  ",
    S  = "  v  ",
    SW = " /   ",
    W  = " <-  ",
    NW = " \\   ",
  }
  return arrows[bearing] or "  ?  "
end

-- ─────────────────────────────────────────────
-- Current position screen
-- ─────────────────────────────────────────────
local function showCurrentPosition(cfg)
  local posRunning = true
  local timerId    = os.startTimer(2)

  local function draw()
    local x, y, z = getPosition()
    local w, h    = term.getSize()

    ui.clear()
    ui.drawHeader("GPS Nav", "Position")

    if not x then
      ui.setColor(colors.orange, colors.black)
      ui.writeCentered(4, "No GPS signal!")
      ui.setColor(colors.white, colors.black)
      ui.writeCentered(6, "Build GPS towers to get")
      ui.writeCentered(7, "position data. You need:")
      ui.writeCentered(8, "4 towers at different")
      ui.writeCentered(9, "X/Y/Z coordinates.")
      ui.setColor(colors.gray, colors.black)
      ui.writeCentered(11, "gps host program on each")
      ui.resetColor()
    else
      -- Save last known position
      cfg.lastX, cfg.lastY, cfg.lastZ = x, y, z
      config.save(CFG_FILE, cfg)

      ui.setColor(colors.cyan, colors.black)
      ui.writeCentered(3, "Your Location")
      ui.resetColor()

      local row = 5
      local function coordLine(label, value, color)
        term.setCursorPos(4, row)
        ui.setColor(colors.gray, colors.black)
        term.write(label .. ": ")
        ui.setColor(color or colors.white, colors.black)
        term.write(string.format("%.1f", value))
        row = row + 1
        ui.resetColor()
      end

      coordLine("X", x, colors.red)
      coordLine("Y", y, colors.lime)
      coordLine("Z", z, colors.blue)

      -- Nearest waypoint
      local nearest = nil
      local nearestDist = math.huge
      for _, wp in ipairs(cfg.waypoints) do
        if wp.x and wp.y and wp.z then
          local d = distance(x, y, z, wp.x, wp.y, wp.z)
          if d < nearestDist then
            nearestDist = d
            nearest     = wp
          end
        end
      end

      if nearest then
        row = row + 1
        ui.setColor(colors.yellow, colors.black)
        term.setCursorPos(2, row)
        term.write("Nearest: " .. nearest.name)
        row = row + 1
        local d, dx, _, dz = distance(x, y, z, nearest.x, nearest.y, nearest.z)
        local bear = bearingStr(dx, dz)
        term.setCursorPos(2, row)
        ui.setColor(colors.white, colors.black)
        term.write(string.format("%.0fm %s", d, bear))
        ui.resetColor()
      end
    end

    ui.drawFooter("[Q] Back  — updates every 2s")
  end

  draw()

  while posRunning do
    local evt, p1 = os.pullEvent()
    if evt == "timer" and p1 == timerId then
      draw()
      timerId = os.startTimer(2)
    elseif evt == "key" and (p1 == keys.q or p1 == keys.backspace) then
      posRunning = false
    elseif evt == "terminate" then
      posRunning = false
    end
  end
end

-- ─────────────────────────────────────────────
-- Navigation screen (heading to a waypoint)
-- ─────────────────────────────────────────────
local function navigateTo(waypoint, cfg)
  local navRunning = true
  local timerId    = os.startTimer(2)

  local function draw()
    local x, y, z = getPosition()
    local w, h    = term.getSize()

    ui.clear()
    ui.drawHeader("GPS Nav", waypoint.name)

    if not x then
      ui.setColor(colors.orange, colors.black)
      ui.writeCentered(4, "No GPS signal!")
      ui.resetColor()
      ui.drawFooter("[Q] Back")
      return
    end

    if not (waypoint.x and waypoint.y and waypoint.z) then
      ui.setColor(colors.orange, colors.black)
      ui.writeCentered(4, "Waypoint has no coordinates!")
      ui.writeCentered(5, "Edit it to set a position.")
      ui.resetColor()
      ui.drawFooter("[Q] Back")
      return
    end

    local dist, dx, dy, dz = distance(x, y, z, waypoint.x, waypoint.y, waypoint.z)
    local bear = bearingStr(dx, dz)
    local arrow = bigArrow(bear)

    -- Target info
    ui.setColor(colors.yellow, colors.black)
    ui.writeCentered(3, "Target: " .. waypoint.name)
    ui.resetColor()

    -- Distance
    ui.setColor(colors.white, colors.black)
    ui.writeCentered(5, string.format("Distance: %.0f blocks", dist))

    -- Direction
    ui.setColor(colors.cyan, colors.black)
    ui.writeCentered(7, "Direction: " .. bear)
    ui.writeCentered(9, arrow)

    -- Vertical
    if math.abs(dy) > 5 then
      ui.setColor(dy > 0 and colors.lime or colors.orange, colors.black)
      ui.writeCentered(11, (dy > 0 and "Go UP " or "Go DOWN ") .. string.format("%.0f", math.abs(dy)) .. " blocks")
    end

    -- Target coords
    ui.setColor(colors.gray, colors.black)
    ui.writeCentered(13, string.format("Target: %.0f, %.0f, %.0f", waypoint.x, waypoint.y, waypoint.z))
    ui.writeCentered(14, string.format("You:    %.0f, %.0f, %.0f", x, y, z))
    ui.resetColor()

    -- Arrived check
    if dist < 5 then
      ui.setColor(colors.lime, colors.black)
      ui.writeCentered(h - 2, "*** ARRIVED! ***")
      ui.resetColor()
    end

    ui.drawFooter("[Q] Back  — updates every 2s")
  end

  draw()

  while navRunning do
    local evt, p1 = os.pullEvent()
    if evt == "timer" and p1 == timerId then
      draw()
      timerId = os.startTimer(2)
    elseif evt == "key" and (p1 == keys.q or p1 == keys.backspace) then
      navRunning = false
    elseif evt == "terminate" then
      navRunning = false
    end
  end
end

-- ─────────────────────────────────────────────
-- Waypoints menu
-- ─────────────────────────────────────────────
local function manageWaypoints(cfg)
  local function getCoords()
    local x, y, z = getPosition()
    if x then return x, y, z end
    -- Manual entry
    ui.alert("No GPS signal. Enter coordinates manually.", "warn")
    local rx = ui.inputText("X: "); local xv = tonumber(rx)
    local ry = ui.inputText("Y: "); local yv = tonumber(ry)
    local rz = ui.inputText("Z: "); local zv = tonumber(rz)
    return xv, yv, zv
  end

  while true do
    local items = {}
    local x, y, z = getPosition()

    for _, wp in ipairs(cfg.waypoints) do
      local desc = "no coords"
      if wp.x and x then
        local d = distance(x, y, z, wp.x, wp.y, wp.z)
        desc = string.format("%.0fm", d)
      elseif wp.x then
        desc = string.format("%.0f,%.0f,%.0f", wp.x, wp.y or 0, wp.z)
      end
      table.insert(items, { label = wp.name, description = desc })
    end
    table.insert(items, { label = "+ Add Waypoint" })
    table.insert(items, { label = "< Back" })

    local idx = ui.drawMenu(items, "Waypoints")
    if not idx or idx == #items then return end

    if idx == #items - 1 then
      -- Add waypoint
      local name = ui.inputText("Waypoint name: ")
      if name and name ~= "" then
        local cx, cy, cz = getCoords()
        table.insert(cfg.waypoints, {
          name = name,
          x    = cx, y = cy, z = cz,
        })
        config.save(CFG_FILE, cfg)
        ui.alert("Waypoint '" .. name .. "' saved.", "success")
      end
    else
      -- Options for existing waypoint
      local wp = cfg.waypoints[idx]
      local opts = {
        { label = "Navigate",        description = "get heading" },
        { label = "Update coords",   description = "set to current pos" },
        { label = "Edit name",       description = "" },
        { label = "Manual coords",   description = "enter X,Y,Z" },
        { label = "Delete",          description = "" },
        { label = "< Cancel" },
      }
      local oidx = ui.drawMenu(opts, wp.name)
      if oidx == 1 then
        navigateTo(wp, cfg)
      elseif oidx == 2 then
        local cx, cy, cz = getPosition()
        if cx then
          wp.x, wp.y, wp.z = cx, cy, cz
          config.save(CFG_FILE, cfg)
          ui.alert("Coords updated to current position.", "success")
        else
          ui.alert("No GPS signal.", "error")
        end
      elseif oidx == 3 then
        local n = ui.inputText("New name: ", wp.name)
        if n and n ~= "" then wp.name = n; config.save(CFG_FILE, cfg) end
      elseif oidx == 4 then
        local cx, cy, cz = getCoords()
        wp.x, wp.y, wp.z = cx, cy, cz
        config.save(CFG_FILE, cfg)
        ui.alert("Coords set.", "success")
      elseif oidx == 5 then
        if ui.confirm("Delete '" .. wp.name .. "'?") then
          table.remove(cfg.waypoints, idx)
          config.save(CFG_FILE, cfg)
        end
      end
    end
  end
end

-- ─────────────────────────────────────────────
-- Share waypoints via rednet
-- ─────────────────────────────────────────────
local function shareWaypoints(cfg)
  if not net.hasModem() then
    ui.alert("No modem found.\nCannot share waypoints.", "error")
    return
  end

  local items = {
    { label = "Send my waypoints",   description = "broadcast to nearby" },
    { label = "Receive waypoints",   description = "listen for 5s" },
    { label = "< Back" },
  }
  local idx = ui.drawMenu(items, "Share Waypoints")
  if not idx or idx == 3 then return end

  if idx == 1 then
    net.broadcast(net.CHANNEL_POCKET, "atm10_waypoints", {
      sender    = os.getComputerID(),
      waypoints = cfg.waypoints,
    })
    ui.alert("Waypoints broadcast to nearby\npocket computers.", "success")

  elseif idx == 2 then
    ui.clear()
    ui.drawHeader("GPS Nav", "Receiving...")
    ui.writeCentered(5, "Listening for 5 seconds...")
    ui.writeCentered(6, "Ask a friend to send theirs.")

    net.open(net.CHANNEL_POCKET)
    local data = net.listen(net.CHANNEL_POCKET, "atm10_waypoints", 5)

    if data and type(data) == "table" and data.waypoints then
      local added = 0
      for _, wp in ipairs(data.waypoints) do
        local exists = false
        for _, own in ipairs(cfg.waypoints) do
          if own.name == wp.name then exists = true; break end
        end
        if not exists then
          table.insert(cfg.waypoints, wp)
          added = added + 1
        end
      end
      config.save(CFG_FILE, cfg)
      ui.alert("Received " .. added .. " new waypoints\nfrom ID " .. (data.sender or "?"), "success")
    else
      ui.alert("No waypoints received.", "warn")
    end
  end
end

-- ─────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────
local function main()
  local cfg = config.getOrDefault(CFG_FILE, DEFAULTS)

  -- Ensure preset templates exist if no waypoints set
  if #cfg.waypoints == 0 then
    for _, p in ipairs(PRESET_WAYPOINTS) do
      table.insert(cfg.waypoints, {
        name = p.name, x = p.x, y = p.y, z = p.z
      })
    end
    config.save(CFG_FILE, cfg)
  end

  local running = true
  while running do
    local x, y, z = getPosition()
    local posStr  = x and string.format("%.0f,%.0f,%.0f", x, y, z) or "No GPS"

    local items = {
      { label = "Current Position", description = posStr },
      { label = "Waypoints",        description = #cfg.waypoints .. " saved" },
      { label = "Navigate",         description = "choose destination" },
      { label = "Share Waypoints",  description = "via rednet" },
      { label = "< Back to Hub",    description = "" },
    }

    local idx = ui.drawMenu(items, "GPS Navigator")
    if not idx or idx == 5 then running = false; break end

    if idx == 1 then showCurrentPosition(cfg)
    elseif idx == 2 or idx == 3 then
      manageWaypoints(cfg)
    elseif idx == 4 then
      shareWaypoints(cfg)
    end
  end
end

main()
