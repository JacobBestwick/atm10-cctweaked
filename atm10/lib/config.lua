-- config.lua
-- Config and log management library for ATM10 automation suite

local config = {}

local DATA_DIR = "/atm10/data/"

-- Ensure data directory exists
local function ensureDir()
  if not fs.exists(DATA_DIR) then
    fs.makeDir(DATA_DIR)
  end
end

local function fullPath(filename)
  ensureDir()
  return DATA_DIR .. filename
end

-- Load a config file. Returns deserialized table or nil.
function config.load(filename)
  local path = fullPath(filename)
  if not fs.exists(path) then
    return nil
  end
  local ok, result = pcall(function()
    local f = fs.open(path, "r")
    if not f then return nil end
    local raw = f.readAll()
    f.close()
    if not raw or raw == "" then return nil end
    return textutils.unserialize(raw)
  end)
  if ok then
    return result
  end
  return nil
end

-- Save a table to a config file. Returns bool success, errMsg.
function config.save(filename, data)
  local path = fullPath(filename)
  local ok, err = pcall(function()
    local serialized = textutils.serialize(data)
    local f = fs.open(path, "w")
    if not f then error("Could not open file for writing: " .. path) end
    f.write(serialized)
    f.close()
  end)
  if ok then
    return true, nil
  else
    return false, tostring(err)
  end
end

-- Load config or create it with defaults. Merges missing keys from defaults.
function config.getOrDefault(filename, defaults)
  local data = config.load(filename)
  if type(data) ~= "table" then
    data = {}
  end
  -- Merge missing keys from defaults
  if type(defaults) == "table" then
    for k, v in pairs(defaults) do
      if data[k] == nil then
        data[k] = v
      end
    end
  end
  -- Save merged result back
  config.save(filename, data)
  return data
end

-- Set a single key in a config file.
function config.set(filename, key, value)
  local data = config.load(filename)
  if type(data) ~= "table" then
    data = {}
  end
  data[key] = value
  return config.save(filename, data)
end

-- Get a single key from a config file, or default if missing.
function config.get(filename, key, default)
  local data = config.load(filename)
  if type(data) ~= "table" then
    return default
  end
  local val = data[key]
  if val == nil then
    return default
  end
  return val
end

-- Delete a config file. Returns bool.
function config.delete(filename)
  local path = fullPath(filename)
  local ok, _ = pcall(function()
    if fs.exists(path) then
      fs.delete(path)
    end
  end)
  return ok
end

-- Format current time as [HH:MM:SS]
local function timestamp()
  local t = os.time()
  local h = math.floor(t)
  local m = math.floor((t - h) * 60)
  local s = math.floor(((t - h) * 60 - m) * 60)
  -- Use os.clock for seconds if available, otherwise estimate
  return string.format("[%02d:%02d:%02d]", h % 24, m % 60, s % 60)
end

-- Append a timestamped line to a log file.
function config.appendLog(filename, entry)
  local path = fullPath(filename)
  local ok, _ = pcall(function()
    local line = timestamp() .. " " .. tostring(entry)
    local f = fs.open(path, "a")
    if not f then error("Could not open log for appending: " .. path) end
    f.writeLine(line)
    f.close()
  end)
  return ok
end

-- Read the last maxLines lines from a log file. Returns table of strings.
function config.readLog(filename, maxLines)
  local path = fullPath(filename)
  maxLines = maxLines or 100
  local lines = {}
  local ok, _ = pcall(function()
    if not fs.exists(path) then return end
    local f = fs.open(path, "r")
    if not f then return end
    local line = f.readLine()
    while line ~= nil do
      table.insert(lines, line)
      line = f.readLine()
    end
    f.close()
  end)
  if not ok or #lines == 0 then
    return {}
  end
  -- Return last maxLines
  if #lines <= maxLines then
    return lines
  end
  local result = {}
  local start = #lines - maxLines + 1
  for i = start, #lines do
    table.insert(result, lines[i])
  end
  return result
end

return config
