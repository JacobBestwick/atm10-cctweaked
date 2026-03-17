-- install.lua
-- ATM10 CC:Tweaked Hub Suite — One-Command Installer
--
-- USAGE (in-game):
--   pastebin get <YOUR_CODE> install
--   install
--
-- This script downloads the entire ATM10 suite from your
-- GitHub repository (or any HTTP host) and sets everything up.
--
-- ─────────────────────────────────────────────────────────────
-- CONFIGURATION: set this to YOUR raw file host base URL
-- GitHub example:
--   https://raw.githubusercontent.com/YOUR_NAME/YOUR_REPO/main
-- ─────────────────────────────────────────────────────────────
local BASE_URL = "https://raw.githubusercontent.com/JacobBestwick/atm10-cctweaked/main/atm10"

-- ─────────────────────────────────────────────────────────────
-- All files to download.
-- Format: { remotePath, localPath }
-- remotePath is appended to BASE_URL.
-- ─────────────────────────────────────────────────────────────
local FILES = {
  -- Shared libraries
  { "/lib/ui.lua",                              "/atm10/lib/ui.lua" },
  { "/lib/detect.lua",                          "/atm10/lib/detect.lua" },
  { "/lib/config.lua",                          "/atm10/lib/config.lua" },
  { "/lib/net.lua",                             "/atm10/lib/net.lua" },
  { "/lib/storage.lua",                         "/atm10/lib/storage.lua" },

  -- Hub + boot
  { "/hub.lua",                                 "/atm10/hub.lua" },

  -- Default config
  { "/data/default_config.lua",                 "/atm10/data/default_config.lua" },

  -- Computer programs
  { "/programs/computer/base_monitor.lua",      "/atm10/programs/computer/base_monitor.lua" },
  { "/programs/computer/craft_manager.lua",     "/atm10/programs/computer/craft_manager.lua" },
  { "/programs/computer/power_grid.lua",        "/atm10/programs/computer/power_grid.lua" },
  { "/programs/computer/resource_tracker.lua",  "/atm10/programs/computer/resource_tracker.lua" },
  { "/programs/computer/farm_controller.lua",   "/atm10/programs/computer/farm_controller.lua" },
  { "/programs/computer/security_system.lua",   "/atm10/programs/computer/security_system.lua" },

  -- Turtle programs
  { "/programs/turtle/smart_miner.lua",         "/atm10/programs/turtle/smart_miner.lua" },
  { "/programs/turtle/quarry_turtle.lua",       "/atm10/programs/turtle/quarry_turtle.lua" },
  { "/programs/turtle/builder_turtle.lua",      "/atm10/programs/turtle/builder_turtle.lua" },
  { "/programs/turtle/tree_farmer.lua",         "/atm10/programs/turtle/tree_farmer.lua" },
  { "/programs/turtle/mob_grinder.lua",         "/atm10/programs/turtle/mob_grinder.lua" },
  { "/programs/turtle/tunnel_bore.lua",         "/atm10/programs/turtle/tunnel_bore.lua" },

  -- Pocket programs
  { "/programs/pocket/remote_dash.lua",         "/atm10/programs/pocket/remote_dash.lua" },
  { "/programs/pocket/gps_nav.lua",             "/atm10/programs/pocket/gps_nav.lua" },
  { "/programs/pocket/remote_craft.lua",        "/atm10/programs/pocket/remote_craft.lua" },
  { "/programs/pocket/ender_link.lua",          "/atm10/programs/pocket/ender_link.lua" },
  { "/programs/pocket/portable_wiki.lua",       "/atm10/programs/pocket/portable_wiki.lua" },
  { "/programs/pocket/player_scanner.lua",      "/atm10/programs/pocket/player_scanner.lua" },
  { "/programs/pocket/geo_scanner.lua",         "/atm10/programs/pocket/geo_scanner.lua" },

  -- Monitor programs
  { "/programs/monitor/big_display.lua",        "/atm10/programs/monitor/big_display.lua" },
  { "/programs/monitor/scoreboard.lua",         "/atm10/programs/monitor/scoreboard.lua" },

  -- Blueprints
  { "/blueprints/mob_farm.blueprint",           "/atm10/blueprints/mob_farm.blueprint" },
  { "/blueprints/mekanism_room.blueprint",      "/atm10/blueprints/mekanism_room.blueprint" },
}

local DIRS = {
  "/atm10",
  "/atm10/lib",
  "/atm10/data",
  "/atm10/blueprints",
  "/atm10/programs",
  "/atm10/programs/computer",
  "/atm10/programs/turtle",
  "/atm10/programs/pocket",
  "/atm10/programs/monitor",
}

-- ─────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────
local isAdv = term.isColor()

local function cls()
  term.clear()
  term.setCursorPos(1, 1)
end

local function col(c)
  if isAdv and c then term.setTextColor(c) end
end

local function resetCol()
  if isAdv then term.setTextColor(colors.white) end
end

local function println(text, color)
  col(color)
  print(text or "")
  resetCol()
end

local function hline(char, color)
  local w = term.getSize()
  col(color)
  print(string.rep(char or "-", w))
  resetCol()
end

local function centerPrint(text, color)
  local w = term.getSize()
  local x = math.max(1, math.floor((w - #text) / 2) + 1)
  term.setCursorPos(x, select(2, term.getCursorPos()))
  col(color)
  print(text)
  resetCol()
end

local function drawBar(current, total)
  local w = term.getSize()
  local barW = w - 10
  local filled = math.floor(barW * current / total)
  col(isAdv and colors.gray or nil)
  io.write("[")
  col(isAdv and colors.lime or nil)
  io.write(string.rep("=", filled))
  col(isAdv and colors.gray or nil)
  io.write(string.rep("-", barW - filled))
  io.write("] ")
  col(isAdv and colors.white or nil)
  io.write(current .. "/" .. total .. "\n")
  resetCol()
end

-- ─────────────────────────────────────────────────────────────
-- Banner
-- ─────────────────────────────────────────────────────────────
local function drawBanner()
  cls()
  hline("=", colors.yellow)
  if isAdv then
    println()
    col(colors.yellow)
    centerPrint(" ___ _____ __  __ _  ___      _   _       _     ")
    centerPrint("/ _ \\_   _|  \\/  / |/ _ \\    | | | |_   _| |__  ")
    centerPrint("|/_\\ | | | |\\/| | | | | |   | |_| | | | | '_ \\ ")
    centerPrint("  _  | | | |  | | | |_| |   |  _  | |_| | |_) |")
    centerPrint(" |_| |_| |_|  |_|_|\\___/    |_| |_|\\__,_|_.__/ ")
    println()
    col(colors.cyan)
    centerPrint("   SUITE INSTALLER  v1.0")
    println()
  else
    centerPrint("  ATM10 HUB SUITE INSTALLER v1.0  ")
  end
  hline("=", colors.yellow)
  println()
end

-- ─────────────────────────────────────────────────────────────
-- Check HTTP
-- ─────────────────────────────────────────────────────────────
local function checkHttp()
  if not http then
    println("ERROR: HTTP API is not enabled!", colors.red)
    println()
    println("Enable it in the server config:")
    println("  computercraft-common.toml:")
    println("    http.enabled = true")
    println()
    println("Or in singleplayer:")
    println("  config/computercraft-server.toml")
    println("    [http]")
    println("    enabled = true")
    println()
    error("HTTP not available - cannot download files", 0)
  end
  println("HTTP: available", colors.lime)
end

-- ─────────────────────────────────────────────────────────────
-- Check BASE_URL is configured
-- ─────────────────────────────────────────────────────────────
local function checkBaseUrl()
  if BASE_URL:find("YOUR_NAME") or BASE_URL:find("YOUR_REPO") then
    println()
    println("ERROR: BASE_URL not configured!", colors.red)
    println()
    println("Edit install.lua and set BASE_URL")
    println("to your GitHub raw URL, e.g.:")
    println()
    col(colors.yellow)
    println("  https://raw.githubusercontent.com/")
    println("    YourUser/YourRepo/main/atm10")
    resetCol()
    println()
    println("Then re-upload to pastebin and retry.")
    error("BASE_URL not configured", 0)
  end
  println("Source: " .. BASE_URL:sub(1, 40) .. "...", colors.gray)
end

-- ─────────────────────────────────────────────────────────────
-- Create directories
-- ─────────────────────────────────────────────────────────────
local function makeDirectories()
  println("Creating directories...", colors.cyan)
  for _, dir in ipairs(DIRS) do
    if not fs.exists(dir) then
      fs.makeDir(dir)
      println("  + " .. dir, colors.lime)
    end
  end
  println()
end

-- ─────────────────────────────────────────────────────────────
-- Download a single file
-- Returns true on success, false + err on failure
-- ─────────────────────────────────────────────────────────────
local function downloadFile(remotePath, localPath)
  local url = BASE_URL .. remotePath
  local ok, resp = pcall(http.get, url)

  if not ok or not resp then
    return false, "request failed"
  end

  local code = resp.getResponseCode and resp.getResponseCode() or 200
  if code ~= 200 then
    resp.close()
    return false, "HTTP " .. code
  end

  local body = resp.readAll()
  resp.close()

  if not body or #body == 0 then
    return false, "empty response"
  end

  local f = fs.open(localPath, "w")
  if not f then
    return false, "cannot write " .. localPath
  end
  f.write(body)
  f.close()
  return true
end

-- ─────────────────────────────────────────────────────────────
-- Download all files
-- ─────────────────────────────────────────────────────────────
local function downloadAll()
  local total   = #FILES
  local success = 0
  local failed  = {}

  println("Downloading " .. total .. " files...", colors.cyan)
  println()

  for i, entry in ipairs(FILES) do
    local remotePath, localPath = entry[1], entry[2]
    local filename = localPath:match("[^/]+$")

    -- Status line
    local w = term.getSize()
    term.setCursorPos(1, select(2, term.getCursorPos()))
    col(colors.gray)
    io.write(string.format("  [%2d/%d] %-28s ", i, total, filename:sub(1, 28)))
    resetCol()

    local ok, err = downloadFile(remotePath, localPath)

    if ok then
      col(colors.lime)
      print("OK")
      resetCol()
      success = success + 1
    else
      col(colors.red)
      print("FAIL: " .. (err or "?"))
      resetCol()
      table.insert(failed, { path = localPath, err = err })
    end
  end

  println()
  drawBar(success, total)
  println()

  if #failed > 0 then
    println(#failed .. " file(s) failed:", colors.orange)
    for _, f in ipairs(failed) do
      println("  - " .. f.path .. " (" .. f.err .. ")", colors.red)
    end
    println()
    println("Tip: Check your BASE_URL is correct", colors.yellow)
    println("     and the repo is public.", colors.yellow)
    println()
  end

  return success, #failed
end

-- ─────────────────────────────────────────────────────────────
-- Optional: write /startup.lua for auto-launch
-- ─────────────────────────────────────────────────────────────
local STARTUP_CONTENT = [[-- startup.lua (auto-generated by ATM10 installer)
if fs.exists("/atm10/hub.lua") then
  shell.run("/atm10/hub.lua")
else
  printError("ATM10 Hub not found. Run: install")
end
]]

local function setupStartup()
  println("Auto-start on boot?", colors.cyan)
  io.write("  Install /startup.lua? [Y/n]: ")
  local ans = read()
  ans = (ans or ""):lower():gsub("%s+", "")

  if ans ~= "n" and ans ~= "no" then
    if fs.exists("/startup.lua") then
      io.write("  /startup.lua exists. Overwrite? [y/N]: ")
      local ow = (read() or ""):lower():gsub("%s+", "")
      if ow ~= "y" and ow ~= "yes" then
        println("  Kept existing /startup.lua.", colors.gray)
        println()
        return
      end
    end
    local f = fs.open("/startup.lua", "w")
    if f then
      f.write(STARTUP_CONTENT)
      f.close()
      println("  /startup.lua written.", colors.lime)
    else
      println("  Could not write /startup.lua.", colors.red)
    end
  else
    println("  Skipped. Run manually: /atm10/hub", colors.gray)
  end
  println()
end

-- ─────────────────────────────────────────────────────────────
-- Done
-- ─────────────────────────────────────────────────────────────
local function printDone(success, failures)
  hline("=", colors.green)
  if failures == 0 then
    println("  All " .. success .. " files installed successfully!", colors.lime)
  else
    println("  " .. success .. " files OK, " .. failures .. " failed.", colors.yellow)
  end
  println()
  println("  To start:  /atm10/hub", colors.cyan)
  println("  Or reboot if startup.lua was installed.", colors.gray)
  println()
  hline("=", colors.green)
end

-- ─────────────────────────────────────────────────────────────
-- Main
-- ─────────────────────────────────────────────────────────────
drawBanner()
println("One-command installer for the ATM10 CC:Tweaked Suite.")
println("Downloads all 30 files and sets up directories.")
println()

checkHttp()
checkBaseUrl()
println()

io.write("Continue? [Y/n]: ")
local go = (read() or ""):lower():gsub("%s+", "")
if go == "n" or go == "no" then
  println("Aborted.", colors.gray)
  return
end
println()

makeDirectories()

local success, failures = downloadAll()

setupStartup()

printDone(success, failures)
