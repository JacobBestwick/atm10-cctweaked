-- net.lua
-- Networking library for ATM10 automation suite (CC:Tweaked)

local net = {}

-- ─────────────────────────────────────────────
-- Channel constants
-- ─────────────────────────────────────────────
net.CHANNEL_BASE      = 4200
net.CHANNEL_TURTLE    = 4201
net.CHANNEL_POCKET    = 4202
net.CHANNEL_BROADCAST = 4299

-- Internal modem cache
local _modem     = nil
local _modemName = nil

-- ─────────────────────────────────────────────
-- Modem management
-- ─────────────────────────────────────────────

-- Find and return a modem peripheral. Prefers wireless over wired.
function net.getModem()
  -- Return cached modem if still present
  if _modem and _modemName then
    local ok, _ = pcall(function()
      -- Verify modem is still accessible
      _modem.isWireless()
    end)
    if ok then
      return _modem
    else
      _modem     = nil
      _modemName = nil
    end
  end

  -- Search for wireless modem first
  local names = peripheral.getNames()
  local wiredCandidate = nil
  local wiredName      = nil

  for _, name in ipairs(names) do
    local ok, pType = pcall(peripheral.getType, name)
    if ok and pType == "modem" then
      local m = peripheral.wrap(name)
      if m then
        local okW, isWireless = pcall(function() return m.isWireless() end)
        if okW and isWireless then
          _modem     = m
          _modemName = name
          return _modem
        elseif not wiredCandidate then
          wiredCandidate = m
          wiredName      = name
        end
      end
    end
  end

  -- Fall back to wired modem
  if wiredCandidate then
    _modem     = wiredCandidate
    _modemName = wiredName
    return _modem
  end

  return nil
end

function net.hasModem()
  return net.getModem() ~= nil
end

-- Open a channel on the modem. Returns bool success.
function net.open(channel)
  local m = net.getModem()
  if not m then return false end
  local ok, err = pcall(m.open, channel)
  return ok
end

-- Close a channel on the modem.
function net.close(channel)
  local m = net.getModem()
  if not m then return end
  pcall(m.close, channel)
end

-- ─────────────────────────────────────────────
-- Messaging
-- ─────────────────────────────────────────────

-- Broadcast a message on channel.
-- Wraps payload in { type, data, sender, time }
function net.broadcast(channel, msgType, data)
  local m = net.getModem()
  if not m then return false end

  local payload = {
    type   = msgType,
    data   = data,
    sender = os.getComputerID(),
    time   = os.time(),
  }

  local ok, err = pcall(function()
    if not m.isOpen(channel) then
      m.open(channel)
    end
    m.transmit(channel, channel, payload)
  end)

  return ok
end

-- Listen on channel for a message of msgType (or any if nil).
-- timeout: seconds to wait. Returns data payload or nil on timeout.
function net.listen(channel, msgType, timeout)
  local m = net.getModem()
  if not m then return nil end

  local ok = pcall(function()
    if not m.isOpen(channel) then
      m.open(channel)
    end
  end)
  if not ok then return nil end

  local timerId = nil
  if timeout and timeout > 0 then
    timerId = os.startTimer(timeout)
  end

  while true do
    local evt, p1, p2, p3, p4, p5 = os.pullEvent()

    if evt == "modem_message" then
      -- p1=side, p2=senderChannel, p3=replyChannel, p4=message, p5=distance
      local side        = p1
      local senderCh    = p2
      local msg         = p4

      if senderCh == channel then
        if type(msg) == "table" then
          if msgType == nil or msg.type == msgType then
            -- Cancel timer
            if timerId then
              -- No cancel API; just ignore future timer event
            end
            return msg.data
          end
        end
      end

    elseif evt == "timer" and timerId and p1 == timerId then
      return nil

    elseif evt == "terminate" then
      return nil
    end
  end
end

-- ─────────────────────────────────────────────
-- Request/Response pattern
-- ─────────────────────────────────────────────

-- Send a request and wait for a reply with matching requestId.
-- Returns response data or nil on timeout.
function net.requestResponse(channel, reqType, data, timeout)
  local m = net.getModem()
  if not m then return nil end

  -- Generate unique request ID
  local requestId = tostring(os.getComputerID()) .. "_" .. tostring(os.time()) ..
                    "_" .. tostring(math.random(1, 99999))

  local payload = {
    type      = reqType,
    data      = data,
    sender    = os.getComputerID(),
    time      = os.time(),
    requestId = requestId,
  }

  local ok = pcall(function()
    if not m.isOpen(channel) then
      m.open(channel)
    end
    m.transmit(channel, channel, payload)
  end)

  if not ok then return nil end

  -- Wait for reply with matching requestId
  local timerId = nil
  if timeout and timeout > 0 then
    timerId = os.startTimer(timeout)
  end

  while true do
    local evt, p1, p2, p3, p4, p5 = os.pullEvent()

    if evt == "modem_message" then
      local senderCh = p2
      local msg      = p4

      if senderCh == channel and type(msg) == "table" then
        if msg.requestId == requestId then
          return msg.data
        end
      end

    elseif evt == "timer" and timerId and p1 == timerId then
      return nil

    elseif evt == "terminate" then
      return nil
    end
  end
end

-- ─────────────────────────────────────────────
-- Server loop
-- handlers = { [msgType] = function(data, senderId) return replyData end }
-- Exits cleanly on terminate event.
-- ─────────────────────────────────────────────
function net.serve(channel, handlers)
  local m = net.getModem()
  if not m then
    error("net.serve: no modem available")
  end

  local ok = pcall(function()
    if not m.isOpen(channel) then
      m.open(channel)
    end
  end)
  if not ok then
    error("net.serve: could not open channel " .. tostring(channel))
  end

  local running = true

  -- Use parallel.waitForAny so terminate is always catchable
  local function serverLoop()
    while running do
      local evt, p1, p2, p3, p4, p5 = os.pullEvent()

      if evt == "modem_message" then
        local senderCh  = p2
        local replyChRaw = p3
        local msg       = p4

        if senderCh == channel and type(msg) == "table" then
          local msgType   = msg.type
          local handler   = handlers[msgType]

          if handler then
            local ok2, replyData = pcall(handler, msg.data, msg.sender)
            if ok2 and replyData ~= nil and msg.requestId then
              -- Send reply
              local replyPayload = {
                type      = msgType .. "_reply",
                data      = replyData,
                sender    = os.getComputerID(),
                time      = os.time(),
                requestId = msg.requestId,
              }
              pcall(function()
                m.transmit(channel, channel, replyPayload)
              end)
            end
          end
        end

      elseif evt == "terminate" then
        running = false
        return
      end
    end
  end

  local function terminateWatcher()
    os.pullEvent("terminate")
    running = false
  end

  -- Run server with parallel terminate watcher
  if parallel then
    parallel.waitForAny(serverLoop, terminateWatcher)
  else
    serverLoop()
  end

  -- Clean up
  pcall(m.close, channel)
end

return net
