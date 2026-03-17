-- Pocket Ore Scanner for ATM10
-- Requires: Advanced Pocket Computer + Geo Scanner upgrade (Advanced Peripherals)
-- Screen: 26x20

-- ============================================================================
-- CONFIG & CONSTANTS
-- ============================================================================

local CONFIG = {
    defaultRadius = 8,
    minRadius = 1,
    maxRadius = 16,
}

local COLORS = {
    header = colors.blue,
    headerText = colors.white,
    status = colors.gray,
    statusText = colors.lightGray,
    selected = colors.yellow,
    normal = colors.white,
    oreName = colors.yellow,
    coords = colors.cyan,
    distance = colors.lightGray,
    footer = colors.gray,
    footerText = colors.white,
    error = colors.red,
    success = colors.green,
    action = colors.lime,
    separator = colors.gray,
}

local ORE_PRESETS = {
    -- Vanilla (matches both normal + deepslate)
    "coal", "iron", "copper", "gold", "diamond", "emerald", "lapis", "redstone",
    -- Deepslate only
    "deepslate_coal", "deepslate_iron", "deepslate_copper", "deepslate_gold",
    "deepslate_diamond", "deepslate_emerald", "deepslate_lapis", "deepslate_redstone",
    -- Modded
    "tin", "lead", "silver", "nickel", "osmium", "uranium", "zinc", "aluminum",
    "fluorite", "iridium", "platinum", "tungsten",
    -- ATM exclusive
    "allthemodium", "vibranium", "unobtainium",
    "suspicious_clay", "suspicious_soul_sand",
    -- Other
    "certus", "quartz", "sulfur", "arcane", "ancient_debris", "source_gem",
}

local YLEVEL_DATA = {
    {layer = "Stone (Y129-247)", ores = "Coal, Copper, Iron, Diamond, Emerald, Gold, Redstone, Lapis, Allthemodium, Tin, Zinc, Aluminum, Fluorite, Certus Quartz"},
    {layer = "Deepslate (Y65-128)", ores = "Allthemodium, Zinc, Iridium, Arcane Crystal, Tungsten"},
    {layer = "Netherrack (Y1-64)", ores = "Quartz, Ancient Debris, Nether Gold, Osmium, Sulfur"},
    {layer = "End Stone (Y-62 to 0)", ores = "Lead, Platinum, Silver, Nickel, Uranium, Enderium, Stellarite"},
}

local scanner = nil
local currentRadius = CONFIG.defaultRadius
local focusedOres = {}
local FOCUS_FILE = "orescan_focus.dat"
local CACHE_FILE = "orescan_cache.dat"
local playerX, playerY, playerZ = nil, nil, nil
local waypoint = nil
local lastScanBlocks = nil
local lastScanCtx = nil

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function centerText(text, y, fgColor, bgColor)
    local w, h = term.getSize()
    local x = math.floor((w - #text) / 2) + 1
    term.setCursorPos(x, y)
    term.setTextColor(fgColor or colors.white)
    term.setBackgroundColor(bgColor or colors.black)
    term.write(text)
end

local function formatOreName(blockName)
    local name = blockName:match(":(.+)") or blockName
    name = name:gsub("_ore$", ""):gsub("_", " ")
    return name:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

local function calculateDistance(x, y, z)
    return math.floor(math.sqrt(x*x + y*y + z*z) + 0.5)
end

local function updatePlayerPos()
    local x, y, z = gps.locate(2)
    if x then
        playerX = math.floor(x + 0.5)
        playerY = math.floor(y + 0.5)
        playerZ = math.floor(z + 0.5)
        return true
    end
    return false
end

local function toWorldCoords(relX, relY, relZ)
    if playerX then
        return playerX + relX, playerY + relY, playerZ + relZ
    end
    return relX, relY, relZ
end

-- ============================================================================
-- PERSISTENCE
-- ============================================================================

local function saveFocusList()
    local f = fs.open(FOCUS_FILE, "w")
    if f then
        f.write(textutils.serialise(focusedOres))
        f.close()
    end
end

local function loadFocusList()
    if fs.exists(FOCUS_FILE) then
        local f = fs.open(FOCUS_FILE, "r")
        if f then
            local data = f.readAll()
            f.close()
            local parsed = textutils.unserialise(data)
            if type(parsed) == "table" then
                focusedOres = parsed
            end
        end
    end
end

local function isFocused(oreName)
    for _, v in ipairs(focusedOres) do
        if v == oreName then return true end
    end
    return false
end

local function addFocused(oreName)
    if not isFocused(oreName) then
        table.insert(focusedOres, oreName)
        saveFocusList()
    end
end

local function removeFocused(oreName)
    for i, v in ipairs(focusedOres) do
        if v == oreName then
            table.remove(focusedOres, i)
            saveFocusList()
            return
        end
    end
end

local function saveScanCache(blocks, scanCtx)
    local f = fs.open(CACHE_FILE, "w")
    if f then
        f.write(textutils.serialise({blocks = blocks, ctx = scanCtx}))
        f.close()
    end
end

local function loadScanCache()
    if fs.exists(CACHE_FILE) then
        local f = fs.open(CACHE_FILE, "r")
        if f then
            local data = f.readAll()
            f.close()
            local parsed = textutils.unserialise(data)
            if type(parsed) == "table" and parsed.blocks then
                return parsed.blocks, parsed.ctx
            end
        end
    end
    return nil, nil
end

-- ============================================================================
-- UI DRAWING HELPERS
-- ============================================================================

local function drawHeader(title)
    term.setCursorPos(1, 1)
    term.setBackgroundColor(COLORS.header)
    term.setTextColor(COLORS.headerText)
    term.clearLine()
    centerText(title, 1, COLORS.headerText, COLORS.header)
end

local function safeFuel()
    if scanner and scanner.getFuelLevel then
        local ok, val = pcall(scanner.getFuelLevel)
        if ok then return val end
    end
    return nil
end

local function safeMaxFuel()
    if scanner and scanner.getMaxFuelLevel then
        local ok, val = pcall(scanner.getMaxFuelLevel)
        if ok then return val end
    end
    return nil
end

local function safeCooldown()
    if scanner and scanner.getScanCooldown then
        local ok, val = pcall(scanner.getScanCooldown)
        if ok then return val end
    end
    return 0
end

local function safeCost(radius)
    if scanner and scanner.cost then
        local ok, val = pcall(scanner.cost, radius)
        if ok then return val end
    end
    return nil
end

local function formatShortDir(relX, relY, relZ)
    local parts = {}
    if relZ ~= 0 then
        parts[#parts+1] = math.abs(relZ) .. (relZ < 0 and "N" or "S")
    end
    if relX ~= 0 then
        parts[#parts+1] = math.abs(relX) .. (relX > 0 and "E" or "W")
    end
    if relY ~= 0 then
        parts[#parts+1] = math.abs(relY) .. (relY > 0 and "U" or "D")
    end
    if #parts == 0 then return "Here!" end
    return table.concat(parts, " ")
end

local function drawStatus()
    term.setCursorPos(1, 2)
    term.setBackgroundColor(COLORS.status)
    term.setTextColor(COLORS.statusText)
    term.clearLine()

    if scanner then
        local fuel = safeFuel()
        local maxFuel = safeMaxFuel()
        local cooldown = safeCooldown()

        local gpsTag = playerX and "GPS" or "REL"
        local statusText = gpsTag .. " R:" .. currentRadius
        if fuel and maxFuel then
            statusText = string.format("F:%d/%d ", fuel, maxFuel) .. statusText
        end
        if cooldown > 0 then
            statusText = statusText .. string.format(" CD:%.1fs", cooldown / 1000)
        end

        term.setCursorPos(2, 2)
        term.write(statusText)

        if waypoint then
            local w = term.getSize()
            local wpStr = ">" .. formatShortDir(waypoint.relX, waypoint.relY, waypoint.relZ)
            term.setCursorPos(w - #wpStr, 2)
            term.setTextColor(COLORS.oreName)
            term.write(wpStr)
        end
    else
        term.setCursorPos(2, 2)
        term.write("No Scanner")
    end
end

local function drawFooter(keybinds)
    local w, h = term.getSize()
    term.setCursorPos(1, h - 1)
    term.setBackgroundColor(COLORS.footer)
    term.setTextColor(COLORS.footerText)
    term.clearLine()

    term.setCursorPos(1, h)
    term.clearLine()

    term.setCursorPos(2, h - 1)
    term.write(keybinds[1] or "")
    term.setCursorPos(2, h)
    term.write(keybinds[2] or "")
end

local function drawList(items, startY, maxLines, selected, scroll)
    local w, h = term.getSize()
    scroll = scroll or 0

    term.setBackgroundColor(colors.black)

    for i = 1, maxLines do
        local itemIndex = i + scroll
        term.setCursorPos(1, startY + i - 1)
        term.clearLine()

        if items[itemIndex] then
            local item = items[itemIndex]
            local isSelected = (itemIndex == selected)

            if item.color then
                term.setTextColor(isSelected and COLORS.selected or item.color)
            else
                term.setTextColor(isSelected and COLORS.selected or COLORS.normal)
            end

            local prefix = isSelected and "> " or "  "
            local text = item.display or item
            local maxWidth = w - 2
            if #text > maxWidth then
                text = text:sub(1, maxWidth - 3) .. "..."
            end
            term.write(prefix .. text)
        end
    end

    if #items > maxLines + scroll then
        term.setCursorPos(w - 5, startY + maxLines - 1)
        term.setTextColor(COLORS.statusText)
        term.write("v more")
    end
    if scroll > 0 then
        term.setCursorPos(w - 5, startY)
        term.setTextColor(COLORS.statusText)
        term.write("^ more")
    end
end

local function showMessage(title, message, isError)
    term.setBackgroundColor(colors.black)
    term.clear()
    drawHeader(title)

    local color = isError and COLORS.error or COLORS.success
    local w, h = term.getSize()
    local lines = {}
    for line in message:gmatch("[^\n]+") do
        table.insert(lines, line)
    end

    local startY = math.floor((h - #lines) / 2)
    for i, line in ipairs(lines) do
        centerText(line, startY + i - 1, color, colors.black)
    end

    centerText("Press any key", h - 2, COLORS.statusText, colors.black)
    os.pullEvent("key")
end

-- ============================================================================
-- SCANNER FUNCTIONS
-- ============================================================================

local function isOreBlock(block)
    if block.tags then
        for _, tag in ipairs(block.tags) do
            if tag:match("forge:ores") or tag:match("minecraft:.*_ores") then
                return true
            end
        end
    end
    if block.name:match("_ore") then
        return true
    end
    return false
end

local function matchesFilter(blockName, filter)
    return blockName:lower():match(filter:lower())
end

local function doScan(radius, filter)
    if not scanner then
        return nil, "No scanner found"
    end

    local cooldown = safeCooldown()
    if cooldown > 0 then
        return nil, string.format("Cooldown: %.1fs", cooldown / 1000)
    end

    updatePlayerPos()

    local results, err = scanner.scan(radius)
    if not results then
        return nil, err or "Scan failed"
    end

    local blocks = {}
    for _, block in ipairs(results) do
        local match = false
        if filter then
            match = matchesFilter(block.name, filter)
        else
            match = isOreBlock(block)
        end

        if match then
            local wx, wy, wz = toWorldCoords(block.x, block.y, block.z)
            table.insert(blocks, {
                name = block.name,
                x = wx, y = wy, z = wz,
                relX = block.x, relY = block.y, relZ = block.z,
                distance = calculateDistance(block.x, block.y, block.z)
            })
        end
    end

    return blocks
end

local function doFocusedScan(radius)
    if not scanner then
        return nil, "No scanner found"
    end
    if #focusedOres == 0 then
        return nil, "Focus list is empty!\nAdd ores first"
    end

    local cooldown = safeCooldown()
    if cooldown > 0 then
        return nil, string.format("Cooldown: %.1fs", cooldown / 1000)
    end

    updatePlayerPos()

    local results, err = scanner.scan(radius)
    if not results then
        return nil, err or "Scan failed"
    end

    local blocks = {}
    for _, block in ipairs(results) do
        local lowerName = block.name:lower()
        for _, focus in ipairs(focusedOres) do
            if lowerName:match(focus:lower()) then
                local wx, wy, wz = toWorldCoords(block.x, block.y, block.z)
                table.insert(blocks, {
                    name = block.name,
                    x = wx, y = wy, z = wz,
                    relX = block.x, relY = block.y, relZ = block.z,
                    distance = calculateDistance(block.x, block.y, block.z)
                })
                break
            end
        end
    end

    return blocks
end

local function groupByOre(blocks)
    local groups = {}
    local groupNames = {}

    for _, block in ipairs(blocks) do
        if not groups[block.name] then
            groups[block.name] = {}
            table.insert(groupNames, block.name)
        end
        table.insert(groups[block.name], block)
    end

    table.sort(groupNames, function(a, b)
        return #groups[a] > #groups[b]
    end)

    return groups, groupNames
end

local function doChunkAnalyze()
    if not scanner then
        return nil, "No scanner found"
    end

    local cooldown = safeCooldown()
    if cooldown > 0 then
        return nil, string.format("Cooldown: %.1fs", cooldown / 1000)
    end

    local results, err = scanner.chunkAnalyze()
    if not results then
        return nil, err or "Analysis failed"
    end

    return results
end

local function discoverOres()
    if not scanner then return {} end
    local cooldown = safeCooldown()
    if cooldown > 0 then return {} end

    local results, err = scanner.scan(currentRadius)
    if not results then return {} end

    local found = {}
    local seen = {}
    for _, block in ipairs(results) do
        if isOreBlock(block) and not seen[block.name] then
            seen[block.name] = true
            table.insert(found, block.name)
        end
    end

    table.sort(found)
    return found
end

-- ============================================================================
-- RESCAN HELPERS
-- ============================================================================

local function performRescan(scanCtx)
    local blocks, err
    if scanCtx.mode == "focused" then
        blocks, err = doFocusedScan(currentRadius)
    elseif scanCtx.mode == "filter" then
        blocks, err = doScan(currentRadius, scanCtx.filter)
    else
        blocks, err = doScan(currentRadius, nil)
    end
    return blocks, err
end

local function rescanForOre(scanCtx, oreRawName)
    local blocks, err = performRescan(scanCtx)
    if err or not blocks then
        return nil, err
    end
    local filtered = {}
    for _, b in ipairs(blocks) do
        if b.name == oreRawName then
            table.insert(filtered, b)
        end
    end
    return filtered
end

-- ============================================================================
-- SCREEN: MAIN MENU
-- ============================================================================

local function mainMenu()
    local menuItems = {
        {display = "Scan All Ores", action = "scan_all"},
        {display = "Focus", action = "focus"},
        {display = "Find Nearest", action = "find_nearest"},
        {display = "Chunk Analysis", action = "chunk"},
        {display = "Y-Level Guide", action = "ylevel"},
        {display = "Settings", action = "settings"},
    }

    if lastScanBlocks and #lastScanBlocks > 0 then
        table.insert(menuItems, #menuItems, {display = "Last Scan Results", action = "last_scan"})
    end

    table.insert(menuItems, {display = "Quit", action = "quit"})

    local selected = 1

    while true do
        term.setBackgroundColor(colors.black)
        term.clear()
        drawHeader("ORE SCANNER")
        drawStatus()
        drawFooter({"Up/Down: Navigate", "Enter: Select | Q: Quit"})

        drawList(menuItems, 4, 14, selected, 0)

        local event, key = os.pullEvent("key")

        if key == keys.up and selected > 1 then
            selected = selected - 1
        elseif key == keys.down and selected < #menuItems then
            selected = selected + 1
        elseif key == keys.enter then
            return menuItems[selected].action
        elseif key == keys.q then
            return "quit"
        end
    end
end

-- ============================================================================
-- SCREEN: BLOCK DETAIL (single ore location)
-- ============================================================================

local function blockDetail(block, oreName, scanCtx, oreRawName)
    while true do
        term.setBackgroundColor(colors.black)
        term.clear()
        drawHeader(oreName)
        drawStatus()

        term.setCursorPos(2, 4)
        term.setTextColor(COLORS.normal)
        term.write("Distance: ")
        term.setTextColor(COLORS.oreName)
        term.write(block.distance .. " blocks")

        term.setCursorPos(2, 6)
        term.setTextColor(COLORS.normal)
        term.write("Direction:")

        local dirParts = {}
        if block.relZ < 0 then
            table.insert(dirParts, {math.abs(block.relZ) .. " North", colors.cyan})
        elseif block.relZ > 0 then
            table.insert(dirParts, {block.relZ .. " South", colors.cyan})
        end
        if block.relX > 0 then
            table.insert(dirParts, {block.relX .. " East", colors.lime})
        elseif block.relX < 0 then
            table.insert(dirParts, {math.abs(block.relX) .. " West", colors.lime})
        end
        if block.relY > 0 then
            table.insert(dirParts, {block.relY .. " Up", colors.yellow})
        elseif block.relY < 0 then
            table.insert(dirParts, {math.abs(block.relY) .. " Down", colors.orange})
        end

        if #dirParts == 0 then
            term.setCursorPos(3, 8)
            term.setTextColor(COLORS.success)
            term.write("Right here!")
        else
            for i, part in ipairs(dirParts) do
                term.setCursorPos(3, 7 + i)
                term.setTextColor(part[2])
                term.write(part[1])
            end
        end

        local coordY = 8 + #dirParts + 1
        if playerX then
            term.setCursorPos(2, coordY)
            term.setTextColor(COLORS.statusText)
            term.write("World: ")
            term.setTextColor(COLORS.normal)
            term.write(block.x .. ", " .. block.y .. ", " .. block.z)
            coordY = coordY + 1
        end

        local isWP = waypoint and waypoint.x == block.x and waypoint.y == block.y and waypoint.z == block.z
        term.setCursorPos(2, coordY + 1)
        term.setTextColor(isWP and COLORS.success or COLORS.statusText)
        term.write(isWP and "* WAYPOINT SET *" or "W: Set as waypoint")

        drawFooter({"R:Rescan W:Waypoint", "Back: Return"})

        local event, key = os.pullEvent("key")
        if key == keys.backspace or key == keys.enter then
            return "back"
        elseif key == keys.w then
            if isWP then
                waypoint = nil
            else
                waypoint = {
                    x = block.x, y = block.y, z = block.z,
                    relX = block.relX, relY = block.relY, relZ = block.relZ,
                    name = oreName
                }
            end
        elseif key == keys.r then
            term.setBackgroundColor(colors.black)
            term.clear()
            drawHeader("RESCANNING...")
            centerText("Updating...", 10, COLORS.statusText, colors.black)

            local newBlocks, err = rescanForOre(scanCtx, oreRawName)
            if err then
                showMessage("Rescan", err, true)
            elseif not newBlocks or #newBlocks == 0 then
                showMessage("Rescan", "No more nearby!\nOre may be mined out.", false)
                return "rescan_empty"
            else
                return "rescan", newBlocks
            end
        end
    end
end

-- ============================================================================
-- SCREEN: ORE DETAIL (list of locations)
-- ============================================================================

local function oreDetail(blocks, oreName, scanCtx, oreRawName)
    local function rebuildItems(blks)
        table.sort(blks, function(a, b) return a.distance < b.distance end)
        local itms = {}
        for _, block in ipairs(blks) do
            local dir = formatShortDir(block.relX, block.relY, block.relZ)
            table.insert(itms, {
                display = string.format("%dblk %s", block.distance, dir),
                block = block
            })
        end
        return itms
    end

    local items = rebuildItems(blocks)
    local selected = 1
    local scroll = 0
    local maxLines = 13

    while true do
        term.setBackgroundColor(colors.black)
        term.clear()
        drawHeader(oreName)
        drawStatus()
        drawFooter({"Up/Dn:Nav Enter:Detail", "R:Rescan | Back:Return"})

        if selected > #items then selected = #items end
        if selected < 1 then selected = 1 end

        if selected > scroll + maxLines then
            scroll = selected - maxLines
        elseif selected <= scroll then
            scroll = math.max(0, selected - 1)
        end

        drawList(items, 4, maxLines, selected, scroll)

        local event, key = os.pullEvent("key")

        if key == keys.up and selected > 1 then
            selected = selected - 1
        elseif key == keys.down and selected < #items then
            selected = selected + 1
        elseif key == keys.enter and #items > 0 then
            local result, newBlocks = blockDetail(items[selected].block, oreName, scanCtx, oreRawName)
            if result == "rescan" and newBlocks then
                blocks = newBlocks
                items = rebuildItems(blocks)
                selected = 1
                scroll = 0
            elseif result == "rescan_empty" then
                return "rescan_empty"
            end
        elseif key == keys.r then
            term.setBackgroundColor(colors.black)
            term.clear()
            drawHeader("RESCANNING...")
            centerText("Updating...", 10, COLORS.statusText, colors.black)

            local newBlocks, err = rescanForOre(scanCtx, oreRawName)
            if err then
                showMessage("Rescan", err, true)
            elseif not newBlocks or #newBlocks == 0 then
                showMessage("Rescan", "No more nearby!\nOre may be mined out.", false)
                return "rescan_empty"
            else
                blocks = newBlocks
                items = rebuildItems(blocks)
                selected = 1
                scroll = 0
            end
        elseif key == keys.backspace then
            return "back"
        end
    end
end

-- ============================================================================
-- SCREEN: SCAN RESULTS
-- ============================================================================

local function scanResults(blocks, filterName, scanCtx)
    scanCtx = scanCtx or {mode = "all"}

    local function rebuildGroups(blks)
        local groups, groupNames = groupByOre(blks)
        local itms = {}
        for _, name in ipairs(groupNames) do
            local count = #groups[name]
            local displayName = formatOreName(name)
            table.insert(itms, {
                display = string.format("%s (%d)", displayName, count),
                name = name,
                blocks = groups[name]
            })
        end
        return itms
    end

    if #blocks == 0 then
        showMessage("Scan Results", "No ores found!", false)
        return
    end

    lastScanBlocks = blocks
    lastScanCtx = scanCtx
    saveScanCache(blocks, scanCtx)

    local items = rebuildGroups(blocks)
    local selected = 1
    local scroll = 0
    local maxLines = 12

    while true do
        if selected > #items then selected = #items end
        if selected < 1 then selected = 1 end

        term.setBackgroundColor(colors.black)
        term.clear()

        local title = filterName and (filterName) or "SCAN RESULTS"
        drawHeader(title)
        drawStatus()
        local focusTag = isFocused(items[selected].name) and " [F]" or ""
        drawFooter({"Up/Dn:Nav Enter:Detail" .. focusTag, "R:Rescan F:Foc Back:Ret"})

        if selected > scroll + maxLines then
            scroll = selected - maxLines
        elseif selected <= scroll then
            scroll = math.max(0, selected - 1)
        end

        drawList(items, 4, maxLines, selected, scroll)

        local event, key = os.pullEvent("key")

        if key == keys.up and selected > 1 then
            selected = selected - 1
        elseif key == keys.down and selected < #items then
            selected = selected + 1
        elseif key == keys.enter and #items > 0 then
            local result = oreDetail(items[selected].blocks, items[selected].display, scanCtx, items[selected].name)
            if result == "rescan_empty" then
                term.setBackgroundColor(colors.black)
                term.clear()
                drawHeader("RESCANNING...")
                centerText("Full rescan...", 10, COLORS.statusText, colors.black)
                local newBlocks, err = performRescan(scanCtx)
                if err then
                    showMessage("Rescan", err, true)
                elseif not newBlocks or #newBlocks == 0 then
                    showMessage("Scan Results", "No ores found!", false)
                    return
                else
                    blocks = newBlocks
                    lastScanBlocks = blocks
                    lastScanCtx = scanCtx
                    saveScanCache(blocks, scanCtx)
                    items = rebuildGroups(blocks)
                    selected = 1
                    scroll = 0
                end
            end
        elseif key == keys.r then
            term.setBackgroundColor(colors.black)
            term.clear()
            drawHeader("RESCANNING...")
            centerText("Updating...", 10, COLORS.statusText, colors.black)

            local newBlocks, err = performRescan(scanCtx)
            if err then
                showMessage("Rescan", err, true)
            elseif not newBlocks or #newBlocks == 0 then
                showMessage("Scan Results", "No ores found!", false)
                return
            else
                blocks = newBlocks
                lastScanBlocks = blocks
                lastScanCtx = scanCtx
                saveScanCache(blocks, scanCtx)
                items = rebuildGroups(blocks)
                selected = 1
                scroll = 0
            end
        elseif key == keys.f then
            local ore = items[selected].name
            if isFocused(ore) then
                removeFocused(ore)
            else
                addFocused(ore)
            end
        elseif key == keys.backspace then
            return
        end
    end
end

-- ============================================================================
-- SCREEN: FOCUS (merged focus list + scan)
-- ============================================================================

local function focusPresetPicker()
    local input = ""
    local selected = 1
    local scroll = 0

    while true do
        term.setBackgroundColor(colors.black)
        term.clear()
        drawHeader("ADD: PRESETS")
        drawStatus()

        term.setCursorPos(2, 4)
        term.setTextColor(COLORS.normal)
        term.write("Search: ")
        term.setTextColor(COLORS.oreName)

        local w = term.getSize()
        local maxInput = w - 10
        local dispInput = input
        if #dispInput > maxInput then
            dispInput = dispInput:sub(#dispInput - maxInput + 1)
        end
        term.write(dispInput)
        term.write("_")

        local items = {}
        for _, ore in ipairs(ORE_PRESETS) do
            if input == "" or ore:lower():match(input:lower()) then
                local marker = isFocused(ore) and " [+]" or ""
                table.insert(items, {
                    display = formatOreName(ore) .. marker,
                    value = ore
                })
            end
        end

        if input ~= "" then
            local alreadyListed = false
            for _, item in ipairs(items) do
                if item.value == input then alreadyListed = true; break end
            end
            if not alreadyListed then
                local marker = isFocused(input) and " [+]" or ""
                table.insert(items, 1, {
                    display = "\"" .. input .. "\"" .. marker,
                    value = input
                })
            end
        end

        local maxLines = 8
        if selected > #items then selected = #items end
        if selected < 1 then selected = 1 end
        if selected > scroll + maxLines then scroll = selected - maxLines end
        if selected <= scroll then scroll = math.max(0, selected - 1) end

        drawList(items, 6, maxLines, selected, scroll)
        drawFooter({"Enter: Toggle ore", "Type to filter | Back:Ret"})

        local event, param = os.pullEvent()
        if event == "key" then
            if param == keys.up and selected > 1 then
                selected = selected - 1
            elseif param == keys.down and selected < #items then
                selected = selected + 1
            elseif param == keys.enter and #items > 0 then
                local ore = items[selected].value
                if isFocused(ore) then removeFocused(ore)
                else addFocused(ore) end
            elseif param == keys.backspace then
                if #input > 0 then
                    input = input:sub(1, -2)
                    selected = 1; scroll = 0
                else
                    return
                end
            end
        elseif event == "char" then
            input = input .. param
            selected = 1; scroll = 0
        end
    end
end

local function focusDiscoverPicker()
    term.setBackgroundColor(colors.black)
    term.clear()
    drawHeader("DISCOVERING...")
    centerText("Scanning area...", 10, COLORS.statusText, colors.black)

    local discovered = discoverOres()
    local selected = 1
    local scroll = 0

    while true do
        term.setBackgroundColor(colors.black)
        term.clear()
        drawHeader("ADD: DISCOVERED")
        drawStatus()

        if #discovered == 0 then
            term.setCursorPos(2, 4)
            term.setTextColor(COLORS.statusText)
            term.write("No ores found nearby.")
            term.setCursorPos(2, 5)
            term.write("Try moving or increase")
            term.setCursorPos(2, 6)
            term.write("radius in Settings.")
            drawFooter({"R: Rescan", "Back: Return"})
        else
            term.setCursorPos(2, 4)
            term.setTextColor(COLORS.normal)
            term.write("Found " .. #discovered .. " ore types:")

            local items = {}
            for _, ore in ipairs(discovered) do
                local marker = isFocused(ore) and " [+]" or ""
                table.insert(items, {
                    display = formatOreName(ore) .. marker,
                    value = ore
                })
            end

            local maxLines = 10
            if selected > #items then selected = #items end
            if selected < 1 then selected = 1 end
            if selected > scroll + maxLines then scroll = selected - maxLines end
            if selected <= scroll then scroll = math.max(0, selected - 1) end

            drawList(items, 6, maxLines, selected, scroll)
            drawFooter({"Enter: Toggle | R: Rescan", "Back: Return"})
        end

        local event, key = os.pullEvent("key")

        if key == keys.up and selected > 1 then
            selected = selected - 1
        elseif key == keys.down and selected < #discovered then
            selected = selected + 1
        elseif key == keys.enter and #discovered > 0 then
            local ore = discovered[selected]
            if isFocused(ore) then removeFocused(ore)
            else addFocused(ore) end
        elseif key == keys.r then
            term.setBackgroundColor(colors.black)
            term.clear()
            drawHeader("DISCOVERING...")
            centerText("Scanning area...", 10, COLORS.statusText, colors.black)
            discovered = discoverOres()
            selected = 1; scroll = 0
        elseif key == keys.backspace then
            return
        end
    end
end

local function focusScreen()
    local selected = 1
    local scroll = 0

    while true do
        term.setBackgroundColor(colors.black)
        term.clear()
        drawHeader("FOCUS")
        drawStatus()

        local items = {}

        if #focusedOres > 0 then
            table.insert(items, {display = "[SCAN FOCUSED ORES]", action = "scan", color = COLORS.action})
        else
            table.insert(items, {display = "[Add ores to scan]", action = "none", color = COLORS.statusText})
        end

        for _, ore in ipairs(focusedOres) do
            table.insert(items, {display = formatOreName(ore), action = "ore", value = ore})
        end

        table.insert(items, {display = "---", action = "sep", color = COLORS.separator})
        table.insert(items, {display = "Browse Presets...", action = "presets", color = COLORS.coords})
        table.insert(items, {display = "Discover Nearby...", action = "discover", color = COLORS.coords})

        local maxLines = 13
        if selected > #items then selected = #items end
        if selected < 1 then selected = 1 end

        if items[selected].action == "sep" then
            if selected < #items then selected = selected + 1
            elseif selected > 1 then selected = selected - 1 end
        end

        if selected > scroll + maxLines then scroll = selected - maxLines end
        if selected <= scroll then scroll = math.max(0, selected - 1) end

        drawList(items, 4, maxLines, selected, scroll)

        local cur = items[selected]
        if cur.action == "ore" then
            drawFooter({"Enter/Del: Remove ore", "Back: Return"})
        elseif cur.action == "scan" then
            drawFooter({"Enter: Scan focused ores", "Back: Return"})
        else
            drawFooter({"Enter: Select", "Back: Return"})
        end

        local event, key = os.pullEvent("key")

        if key == keys.up then
            if selected > 1 then
                selected = selected - 1
                if items[selected].action == "sep" and selected > 1 then
                    selected = selected - 1
                end
            end
        elseif key == keys.down then
            if selected < #items then
                selected = selected + 1
                if items[selected].action == "sep" and selected < #items then
                    selected = selected + 1
                end
            end
        elseif key == keys.enter then
            if cur.action == "scan" then
                term.setBackgroundColor(colors.black)
                term.clear()
                drawHeader("FOCUSED SCAN")
                drawStatus()
                centerText("Scanning...", 10, COLORS.statusText, colors.black)

                local blocks, err = doFocusedScan(currentRadius)
                if err then
                    showMessage("Error", err, true)
                else
                    scanResults(blocks, "FOCUSED", {mode = "focused"})
                end
            elseif cur.action == "ore" then
                removeFocused(cur.value)
                if selected > 1 + #focusedOres and selected > 1 then
                    selected = selected - 1
                end
            elseif cur.action == "presets" then
                focusPresetPicker()
                selected = 1; scroll = 0
            elseif cur.action == "discover" then
                focusDiscoverPicker()
                selected = 1; scroll = 0
            end
        elseif (key == keys.delete) and cur.action == "ore" then
            removeFocused(cur.value)
            if selected > 1 + #focusedOres and selected > 1 then
                selected = selected - 1
            end
        elseif key == keys.backspace then
            return
        end
    end
end

-- ============================================================================
-- SCREEN: FIND NEAREST
-- ============================================================================

local function findNearest()
    term.setBackgroundColor(colors.black)
    term.clear()
    drawHeader("FIND NEAREST")
    drawStatus()
    centerText("Scanning...", 10, COLORS.statusText, colors.black)

    local blocks, err = doScan(currentRadius, nil)
    if err then
        showMessage("Error", err, true)
        return
    end

    if not blocks or #blocks == 0 then
        showMessage("Find Nearest", "No ores nearby!", false)
        return
    end

    table.sort(blocks, function(a, b) return a.distance < b.distance end)

    local nearest = blocks[1]
    local oreName = formatOreName(nearest.name)

    lastScanBlocks = blocks
    lastScanCtx = {mode = "all"}
    saveScanCache(blocks, lastScanCtx)

    blockDetail(nearest, oreName, {mode = "all"}, nearest.name)
end

-- ============================================================================
-- SCREEN: Y-LEVEL GUIDE
-- ============================================================================

local function ylevelGuide()
    local scroll = 0

    local lines = {}
    table.insert(lines, {text = "ATM10 Mining Dimension", color = COLORS.oreName})
    table.insert(lines, {text = "Ore Distribution Guide", color = COLORS.oreName})
    table.insert(lines, {text = "", color = COLORS.normal})

    for _, layer in ipairs(YLEVEL_DATA) do
        table.insert(lines, {text = layer.layer, color = colors.cyan})

        local oreList = layer.ores
        while #oreList > 0 do
            local chunk
            if #oreList <= 24 then
                chunk = oreList
                oreList = ""
            else
                local cut = oreList:sub(1, 24)
                local lastComma = cut:find(",([^,]*)$")
                if lastComma then
                    chunk = oreList:sub(1, lastComma - 1)
                    oreList = oreList:sub(lastComma + 2)
                else
                    chunk = cut
                    oreList = oreList:sub(25)
                end
            end
            table.insert(lines, {text = " " .. chunk, color = COLORS.normal})
        end

        table.insert(lines, {text = "", color = COLORS.normal})
    end

    table.insert(lines, {text = "Progression Ores:", color = COLORS.oreName})
    table.insert(lines, {text = " Allthemodium (Netherite+)", color = colors.yellow})
    table.insert(lines, {text = " Vibranium (Allthemod+)", color = colors.purple})
    table.insert(lines, {text = " Unobtainium (Vibranium+)", color = colors.red})

    while true do
        term.setBackgroundColor(colors.black)
        term.clear()
        drawHeader("Y-LEVEL GUIDE")

        local w, h = term.getSize()
        local maxLines = h - 4
        local startY = 3

        for i = 1, maxLines do
            local idx = i + scroll
            if lines[idx] then
                term.setCursorPos(2, startY + i - 1)
                term.setTextColor(lines[idx].color)
                local text = lines[idx].text
                if #text > w - 2 then text = text:sub(1, w - 5) .. "..." end
                term.write(text)
            end
        end

        if scroll + maxLines < #lines then
            term.setCursorPos(w - 5, startY + maxLines - 1)
            term.setTextColor(COLORS.statusText)
            term.write("v more")
        end
        if scroll > 0 then
            term.setCursorPos(w - 5, startY)
            term.setTextColor(COLORS.statusText)
            term.write("^ more")
        end

        drawFooter({"Up/Down: Scroll", "Back: Return"})

        local event, key = os.pullEvent("key")
        if key == keys.up and scroll > 0 then
            scroll = scroll - 1
        elseif key == keys.down and scroll + maxLines < #lines then
            scroll = scroll + 1
        elseif key == keys.backspace then
            return
        end
    end
end

-- ============================================================================
-- SCREEN: CHUNK ANALYSIS
-- ============================================================================

local function chunkAnalysis()
    term.setBackgroundColor(colors.black)
    term.clear()
    drawHeader("ANALYZING...")
    drawStatus()
    centerText("Please wait...", 10, COLORS.statusText, colors.black)

    local results, err = doChunkAnalyze()
    if err then
        showMessage("Error", err, true)
        return
    end

    if not results or type(results) ~= "table" then
        showMessage("Error", "Invalid analysis results", true)
        return
    end

    local items = {}
    for oreName, count in pairs(results) do
        table.insert(items, {
            name = oreName,
            count = count,
            display = string.format("%s: %d", formatOreName(oreName), count)
        })
    end

    table.sort(items, function(a, b) return a.count > b.count end)

    if #items == 0 then
        showMessage("Chunk Analysis", "No ores in this chunk", false)
        return
    end

    local selected = 1
    local scroll = 0
    local maxLines = 12

    while true do
        term.setBackgroundColor(colors.black)
        term.clear()
        drawHeader("CHUNK ANALYSIS")
        drawStatus()
        drawFooter({"Up/Down: Scroll | F: Focus", "Back: Return"})

        if selected > scroll + maxLines then scroll = selected - maxLines end
        if selected <= scroll then scroll = math.max(0, selected - 1) end

        drawList(items, 4, maxLines, selected, scroll)

        local event, key = os.pullEvent("key")

        if key == keys.up and selected > 1 then
            selected = selected - 1
        elseif key == keys.down and selected < #items then
            selected = selected + 1
        elseif key == keys.f and #items > 0 then
            local ore = items[selected].name
            if isFocused(ore) then removeFocused(ore)
            else addFocused(ore) end
        elseif key == keys.backspace then
            return
        end
    end
end

-- ============================================================================
-- SCREEN: SETTINGS
-- ============================================================================

local function settingsScreen()
    while true do
        term.setBackgroundColor(colors.black)
        term.clear()
        drawHeader("SETTINGS")
        drawStatus()
        drawFooter({"Left/Right: Adjust", "C:Clear Waypoint | Back"})

        term.setCursorPos(2, 5)
        term.setTextColor(COLORS.normal)
        term.write("Scan Radius:")

        term.setCursorPos(2, 6)
        term.setTextColor(COLORS.oreName)
        term.write(string.format("< %d >", currentRadius))

        local cost = safeCost(currentRadius)
        if cost then
            term.setCursorPos(2, 8)
            term.setTextColor(COLORS.statusText)
            term.write(string.format("Fuel cost: %d FE", cost))
        end

        term.setCursorPos(2, 10)
        term.setTextColor(COLORS.statusText)
        term.write("Range: " .. CONFIG.minRadius .. "-" .. CONFIG.maxRadius)

        if waypoint then
            term.setCursorPos(2, 12)
            term.setTextColor(COLORS.normal)
            term.write("Waypoint: " .. waypoint.name)
            term.setCursorPos(2, 13)
            term.setTextColor(COLORS.statusText)
            term.write(formatShortDir(waypoint.relX, waypoint.relY, waypoint.relZ))
        end

        local event, key = os.pullEvent("key")

        if key == keys.left and currentRadius > CONFIG.minRadius then
            currentRadius = currentRadius - 1
        elseif key == keys.right and currentRadius < CONFIG.maxRadius then
            currentRadius = currentRadius + 1
        elseif key == keys.c then
            waypoint = nil
        elseif key == keys.backspace then
            return
        end
    end
end

-- ============================================================================
-- MAIN LOOP
-- ============================================================================

local function findScanner()
    local tryNames = {"geoScanner", "geo_scanner", "GeoScanner", "geoscanner"}

    for _, name in ipairs(tryNames) do
        local s = peripheral.find(name)
        if s then return s end
    end

    local back = peripheral.wrap("back")
    if back and back.scan then return back end

    local allPeriphs = peripheral.getNames()
    for _, name in ipairs(allPeriphs) do
        local p = peripheral.wrap(name)
        if p and type(p.scan) == "function" and type(p.chunkAnalyze) == "function" then
            return p
        end
    end

    return nil
end

local function main()
    term.setBackgroundColor(colors.black)
    term.clear()

    loadFocusList()
    lastScanBlocks, lastScanCtx = loadScanCache()
    scanner = findScanner()

    if not scanner then
        local w, h = term.getSize()
        term.setBackgroundColor(colors.black)
        term.clear()
        drawHeader("NO SCANNER")

        term.setTextColor(COLORS.error)
        centerText("Geo Scanner not found!", 4, COLORS.error, colors.black)

        term.setTextColor(COLORS.normal)
        centerText("1) Put Geo Scanner in", 6, COLORS.normal, colors.black)
        centerText("   your hotbar slot", 7, COLORS.normal, colors.black)
        centerText("2) Open this pocket PC", 8, COLORS.normal, colors.black)
        centerText("3) Run:", 9, COLORS.normal, colors.black)
        term.setCursorPos(2, 10)
        term.setTextColor(COLORS.oreName)
        term.write("  pocket.equipBack()")

        term.setTextColor(COLORS.statusText)
        centerText("Detected peripherals:", 12, COLORS.statusText, colors.black)

        local allPeriphs = peripheral.getNames()
        if #allPeriphs == 0 then
            centerText("(none)", 13, COLORS.error, colors.black)
        else
            for i, name in ipairs(allPeriphs) do
                if 12 + i < h - 2 then
                    local pType = peripheral.getType(name)
                    term.setCursorPos(2, 12 + i)
                    term.setTextColor(COLORS.oreName)
                    term.write(name .. ": ")
                    term.setTextColor(COLORS.statusText)
                    term.write(pType)
                end
            end
        end

        centerText("Press any key to exit", h - 1, COLORS.statusText, colors.black)
        os.pullEvent("key")
        return
    end

    while true do
        local action = mainMenu()

        if action == "scan_all" then
            term.setBackgroundColor(colors.black)
            term.clear()
            drawHeader("SCANNING...")
            drawStatus()
            centerText("Please wait...", 10, COLORS.statusText, colors.black)

            local blocks, err = doScan(currentRadius, nil)
            if err then
                showMessage("Error", err, true)
            else
                scanResults(blocks, nil, {mode = "all"})
            end

        elseif action == "focus" then
            focusScreen()

        elseif action == "find_nearest" then
            findNearest()

        elseif action == "chunk" then
            chunkAnalysis()

        elseif action == "ylevel" then
            ylevelGuide()

        elseif action == "last_scan" then
            if lastScanBlocks and #lastScanBlocks > 0 then
                scanResults(lastScanBlocks, "LAST SCAN", lastScanCtx or {mode = "all"})
            else
                showMessage("Last Scan", "No cached results", false)
            end

        elseif action == "settings" then
            settingsScreen()

        elseif action == "quit" then
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            term.clear()
            term.setCursorPos(1, 1)
            print("Thanks for using Ore Scanner!")
            break
        end
    end
end

main()
