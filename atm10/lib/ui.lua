-- ui.lua
-- UI framework for ATM10 automation suite
-- Handles both color (advanced) and monochrome (normal) devices

local ui = {}

-- ─────────────────────────────────────────────
-- Color theme (populated only on advanced devices)
-- ─────────────────────────────────────────────
ui.colors = {}

if term.isColor() then
  ui.colors.header_bg        = colors.blue
  ui.colors.header_fg        = colors.white
  ui.colors.menu_selected_bg = colors.blue
  ui.colors.menu_selected_fg = colors.white
  ui.colors.alert_warn       = colors.orange
  ui.colors.alert_error      = colors.red
  ui.colors.alert_success    = colors.lime
  ui.colors.progress_fill    = colors.lime
  ui.colors.progress_empty   = colors.gray
end

-- ─────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────

function ui.setColor(fg, bg)
  if term.isColor() then
    if fg then term.setTextColor(fg) end
    if bg then term.setBackgroundColor(bg) end
  end
end

function ui.resetColor()
  if term.isColor() then
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
  end
end

function ui.clear(bgColor)
  if term.isColor() and bgColor then
    term.setBackgroundColor(bgColor)
  else
    if term.isColor() then
      term.setBackgroundColor(colors.black)
    end
  end
  term.clear()
  term.setCursorPos(1, 1)
end

-- Draw a full-width line of `char` at row y
function ui.hLine(y, char, fg, bg)
  local w, _ = term.getSize()
  char = char or "-"
  if term.isColor() then
    if bg then term.setBackgroundColor(bg) end
    if fg then term.setTextColor(fg) end
  end
  term.setCursorPos(1, y)
  term.write(string.rep(char, w))
  ui.resetColor()
end

-- Fill a rectangle with bgColor
function ui.fillRect(x, y, w, h, bgColor)
  if term.isColor() and bgColor then
    term.setBackgroundColor(bgColor)
  end
  local row = string.rep(" ", w)
  for dy = 0, h - 1 do
    term.setCursorPos(x, y + dy)
    term.write(row)
  end
  ui.resetColor()
end

-- Draw header bar on row 1
-- Format: " ATM10 Hub | {title}" left, subtitle right-aligned
function ui.drawHeader(title, subtitle)
  local w, _ = term.getSize()
  local left = " ATM10 Hub | " .. (title or "")
  local right = subtitle and tostring(subtitle) or ""

  ui.setColor(
    ui.colors.header_fg or nil,
    ui.colors.header_bg or nil
  )

  term.setCursorPos(1, 1)
  -- Fill entire row
  term.write(string.rep(" ", w))

  -- Write left text
  term.setCursorPos(1, 1)
  local truncLeft = left:sub(1, w)
  term.write(truncLeft)

  -- Write right text if it fits
  if right ~= "" then
    local rightStart = w - #right + 1
    if rightStart > #truncLeft + 1 then
      term.setCursorPos(rightStart, 1)
      term.write(right)
    end
  end

  ui.resetColor()
end

-- Draw footer on last row with keyboard hints
function ui.drawFooter(hints)
  local w, h = term.getSize()
  hints = hints or ""
  local text = tostring(hints):sub(1, w)

  if term.isColor() then
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
  end

  term.setCursorPos(1, h)
  term.write(string.rep(" ", w))
  term.setCursorPos(1, h)
  term.write(text)

  ui.resetColor()
end

-- Write text centered at row y
function ui.writeCentered(y, text, fg, bg)
  local w, _ = term.getSize()
  text = tostring(text)
  local x = math.floor((w - #text) / 2) + 1
  if x < 1 then x = 1 end

  if term.isColor() then
    if bg then term.setBackgroundColor(bg) end
    if fg then term.setTextColor(fg) end
  end

  term.setCursorPos(x, y)
  term.write(text:sub(1, w))
  ui.resetColor()
end

-- ─────────────────────────────────────────────
-- Interactive scrollable menu
-- items: list of strings or {label, description, enabled}
-- Returns selected index (1-based) or nil if quit
-- ─────────────────────────────────────────────
function ui.drawMenu(items, title, startSelected)
  local w, h = term.getSize()

  -- Normalize items
  local normalized = {}
  for i, item in ipairs(items) do
    if type(item) == "string" then
      normalized[i] = { label = item, description = "", enabled = true }
    else
      normalized[i] = {
        label       = item[1] or item.label or "",
        description = item[2] or item.description or "",
        enabled     = (item[3] ~= nil) and item[3] or
                      (item.enabled ~= nil) and item.enabled or true,
      }
    end
  end

  -- Layout: row 1 = header, row 2 = title bar, last row = footer
  -- Menu rows: 3 .. h-1
  local menuTop    = title and 3 or 2
  local menuBottom = h - 1
  local visible    = menuBottom - menuTop + 1

  local selected = startSelected or 1
  if selected < 1 then selected = 1 end
  if selected > #normalized then selected = #normalized end
  local scrollOffset = 0  -- index of first visible item (0-based)

  local function clampScroll()
    if selected - 1 < scrollOffset then
      scrollOffset = selected - 1
    end
    if selected - 1 >= scrollOffset + visible then
      scrollOffset = selected - visible
    end
    if scrollOffset < 0 then scrollOffset = 0 end
  end

  local function redraw()
    clampScroll()

    -- Header
    ui.drawHeader("Menu", title)

    -- Optional title bar on row 2
    if title then
      if term.isColor() then
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
      end
      term.setCursorPos(1, 2)
      term.write(string.rep(" ", w))
      ui.writeCentered(2, title,
        term.isColor() and colors.white or nil,
        term.isColor() and colors.gray or nil)
    end

    -- Clear menu area
    if term.isColor() then
      term.setBackgroundColor(colors.black)
      term.setTextColor(colors.white)
    end
    for row = menuTop, menuBottom do
      term.setCursorPos(1, row)
      term.write(string.rep(" ", w))
    end

    -- Draw scroll arrow up
    if scrollOffset > 0 then
      ui.setColor(term.isColor() and colors.yellow or nil, nil)
      term.setCursorPos(w, menuTop)
      term.write("^")
      ui.resetColor()
    end

    -- Draw scroll arrow down
    if scrollOffset + visible < #normalized then
      ui.setColor(term.isColor() and colors.yellow or nil, nil)
      term.setCursorPos(w, menuBottom)
      term.write("v")
      ui.resetColor()
    end

    -- Draw visible items
    for vi = 1, visible do
      local itemIdx = scrollOffset + vi
      if itemIdx > #normalized then break end
      local item = normalized[itemIdx]
      local row  = menuTop + vi - 1
      local isSel = (itemIdx == selected)

      local prefix = isSel and "> " or "  "
      local label  = item.label
      local desc   = item.description or ""

      -- Color for selected vs disabled
      if isSel then
        ui.setColor(
          ui.colors.menu_selected_fg or nil,
          ui.colors.menu_selected_bg or nil
        )
        term.setCursorPos(1, row)
        term.write(string.rep(" ", w))
      elseif not item.enabled then
        ui.setColor(term.isColor() and colors.gray or nil, nil)
      else
        ui.resetColor()
      end

      term.setCursorPos(1, row)
      term.write(prefix .. label)

      -- Right-aligned description if space allows
      if desc ~= "" then
        local descStart = w - #desc - 1
        if descStart > #prefix + #label + 1 then
          term.setCursorPos(descStart, row)
          term.write(desc)
        end
      end

      ui.resetColor()
    end

    -- Footer hints
    ui.drawFooter("[Up/Down] Navigate  [Enter] Select  [Q] Quit")
  end

  redraw()

  while true do
    local evt, p1, p2, p3 = os.pullEvent()

    if evt == "key" then
      local k = p1
      if k == keys.up then
        if selected > 1 then
          selected = selected - 1
          redraw()
        end
      elseif k == keys.down then
        if selected < #normalized then
          selected = selected + 1
          redraw()
        end
      elseif k == keys.enter then
        return selected
      elseif k == keys.q then
        return nil
      end

    elseif evt == "mouse_click" and term.isColor() then
      local button, mx, my = p1, p2, p3
      if button == 1 then
        if my >= menuTop and my <= menuBottom then
          local clickedIdx = scrollOffset + (my - menuTop + 1)
          if clickedIdx >= 1 and clickedIdx <= #normalized then
            if clickedIdx == selected then
              return selected
            else
              selected = clickedIdx
              redraw()
            end
          end
        end
      end

    elseif evt == "mouse_scroll" and term.isColor() then
      local dir = p1
      if dir > 0 and selected < #normalized then
        selected = selected + 1
        redraw()
      elseif dir < 0 and selected > 1 then
        selected = selected - 1
        redraw()
      end

    elseif evt == "terminate" then
      return nil
    end
  end
end

-- ─────────────────────────────────────────────
-- Progress bar
-- ─────────────────────────────────────────────
function ui.drawProgressBar(x, y, width, percent, fillColor, emptyColor, label)
  percent = math.max(0, math.min(100, percent or 0))
  fillColor  = fillColor  or ui.colors.progress_fill  or nil
  emptyColor = emptyColor or ui.colors.progress_empty or nil

  local filled = math.floor(width * percent / 100)
  local empty  = width - filled

  -- Draw filled portion
  if term.isColor() and fillColor then
    term.setBackgroundColor(fillColor)
    term.setTextColor(fillColor)
  end
  term.setCursorPos(x, y)
  term.write(string.rep(" ", filled))

  -- Draw empty portion
  if term.isColor() and emptyColor then
    term.setBackgroundColor(emptyColor)
    term.setTextColor(emptyColor)
  end
  term.write(string.rep(" ", empty))

  -- Overlay label centered
  if label and label ~= "" then
    local lbl   = tostring(label):sub(1, width)
    local lx    = x + math.floor((width - #lbl) / 2)
    ui.resetColor()
    term.setCursorPos(lx, y)
    term.write(lbl)
  end

  ui.resetColor()
end

-- ─────────────────────────────────────────────
-- Table renderer
-- headers: list of strings
-- rows: list of lists
-- colWidths: list of numbers (if nil, auto-sized)
-- Returns next Y position after table
-- ─────────────────────────────────────────────
function ui.drawTable(headers, rows, startX, startY, colWidths)
  local w, _ = term.getSize()
  startX = startX or 1
  startY = startY or 1

  -- Auto-size columns if not provided
  if not colWidths then
    colWidths = {}
    for i, h in ipairs(headers) do
      colWidths[i] = #tostring(h)
    end
    for _, row in ipairs(rows) do
      for i, cell in ipairs(row) do
        local len = #tostring(cell or "")
        if colWidths[i] then
          colWidths[i] = math.max(colWidths[i], len)
        else
          colWidths[i] = len
        end
      end
    end
    -- Add padding
    for i = 1, #colWidths do
      colWidths[i] = colWidths[i] + 2
    end
  end

  local function drawRow(y, cells, isHeader, isEven)
    local bgColor = nil
    if term.isColor() then
      if isHeader then
        bgColor = colors.gray
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
      elseif isEven then
        bgColor = colors.black
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
      else
        bgColor = colors.black
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.lightGray)
      end
    end

    term.setCursorPos(startX, y)
    local line = ""
    for i, col in ipairs(colWidths) do
      local cell = tostring(cells[i] or "")
      -- Pad/truncate to column width
      if #cell > col - 1 then
        cell = cell:sub(1, col - 1)
      end
      line = line .. cell .. string.rep(" ", col - #cell)
    end
    -- Truncate to screen width
    line = line:sub(1, w - startX + 1)
    term.write(line)
    ui.resetColor()
  end

  local y = startY
  drawRow(y, headers, true, false)
  y = y + 1

  for i, row in ipairs(rows) do
    drawRow(y, row, false, i % 2 == 0)
    y = y + 1
  end

  return y
end

-- ─────────────────────────────────────────────
-- Modal alert box
-- level: "info", "warn", "error", "success"
-- ─────────────────────────────────────────────
function ui.alert(message, level)
  level = level or "info"
  local w, h = term.getSize()

  local levelColors = {
    info    = { bg = term.isColor() and colors.blue   or nil, fg = term.isColor() and colors.white or nil, title = "Info"    },
    warn    = { bg = term.isColor() and colors.orange or nil, fg = term.isColor() and colors.white or nil, title = "Warning" },
    error   = { bg = term.isColor() and colors.red    or nil, fg = term.isColor() and colors.white or nil, title = "Error"   },
    success = { bg = term.isColor() and colors.green  or nil, fg = term.isColor() and colors.white or nil, title = "Success" },
  }
  local lc = levelColors[level] or levelColors.info

  -- Word wrap message
  local boxW  = math.min(w - 4, 40)
  local lines = ui.wordWrap(tostring(message), boxW - 2)
  local boxH  = #lines + 4  -- title + blank + lines + prompt
  local boxX  = math.floor((w - boxW) / 2) + 1
  local boxY  = math.floor((h - boxH) / 2) + 1

  -- Save terminal state by redrawing after
  -- Draw box background
  ui.fillRect(boxX, boxY, boxW, boxH, lc.bg)

  -- Border (simple line characters)
  if term.isColor() and lc.bg then
    term.setBackgroundColor(lc.bg)
    term.setTextColor(lc.fg or colors.white)
  end

  -- Title row
  term.setCursorPos(boxX, boxY)
  term.write("+" .. string.rep("-", boxW - 2) .. "+")

  term.setCursorPos(boxX, boxY + 1)
  local titleStr = " " .. lc.title .. " "
  local titlePad = string.rep(" ", math.max(0, boxW - 2 - #titleStr))
  term.write("|" .. titleStr .. titlePad .. "|")

  term.setCursorPos(boxX, boxY + 2)
  term.write("+" .. string.rep("-", boxW - 2) .. "+")

  -- Message lines
  for i, line in ipairs(lines) do
    term.setCursorPos(boxX, boxY + 2 + i)
    local padded = " " .. line .. string.rep(" ", math.max(0, boxW - 2 - #line - 1))
    term.write("|" .. padded:sub(1, boxW - 2) .. "|")
  end

  -- Prompt row
  local promptY = boxY + 2 + #lines + 1
  term.setCursorPos(boxX, promptY)
  local promptStr = " Press any key "
  local promptPad = string.rep(" ", math.max(0, boxW - 2 - #promptStr))
  term.write("|" .. promptStr .. promptPad .. "|")

  term.setCursorPos(boxX, promptY + 1)
  term.write("+" .. string.rep("-", boxW - 2) .. "+")

  ui.resetColor()

  -- Wait for keypress
  os.pullEvent("key")
end

-- ─────────────────────────────────────────────
-- Scrollable text pager
-- ─────────────────────────────────────────────
function ui.pager(lines, title)
  local w, h = term.getSize()
  local contentH = h - 3  -- header + footer
  local scroll   = 0
  local total    = #lines

  local function redraw()
    ui.drawHeader(title or "Viewer", "")

    if term.isColor() then
      term.setBackgroundColor(colors.black)
      term.setTextColor(colors.white)
    end

    for row = 1, contentH do
      term.setCursorPos(1, row + 1)
      term.write(string.rep(" ", w))
      local li = scroll + row
      if li <= total then
        term.setCursorPos(1, row + 1)
        term.write(tostring(lines[li]):sub(1, w))
      end
    end

    -- Scroll position indicator
    local posStr = tostring(scroll + 1) .. "-" ..
                   tostring(math.min(scroll + contentH, total)) ..
                   "/" .. tostring(total)
    ui.drawFooter("[Up/Down/PgUp/PgDn] Scroll  [Q] Quit  " .. posStr)
  end

  redraw()

  while true do
    local evt, key = os.pullEvent("key")
    if key == keys.up then
      if scroll > 0 then scroll = scroll - 1; redraw() end
    elseif key == keys.down then
      if scroll + contentH < total then scroll = scroll + 1; redraw() end
    elseif key == keys.pageUp then
      scroll = math.max(0, scroll - contentH)
      redraw()
    elseif key == keys.pageDown then
      scroll = math.min(math.max(0, total - contentH), scroll + contentH)
      redraw()
    elseif key == keys.home then
      scroll = 0; redraw()
    elseif key == keys["end"] then
      scroll = math.max(0, total - contentH); redraw()
    elseif key == keys.q then
      return
    elseif key == keys.terminate then
      return
    end
  end
end

-- ─────────────────────────────────────────────
-- Text input at bottom of screen
-- ─────────────────────────────────────────────
function ui.inputText(prompt, default)
  local w, h = term.getSize()
  prompt = prompt or "> "

  if term.isColor() then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
  end

  term.setCursorPos(1, h - 1)
  term.write(string.rep(" ", w))
  term.setCursorPos(1, h - 1)
  term.write(tostring(prompt))

  ui.resetColor()

  term.setCursorPos(1, h)
  term.write(string.rep(" ", w))
  term.setCursorPos(1, h)

  return read(nil, nil, nil, default)
end

-- ─────────────────────────────────────────────
-- Yes/No confirmation
-- ─────────────────────────────────────────────
function ui.confirm(question)
  local w, h = term.getSize()
  question = tostring(question or "Are you sure?")

  if term.isColor() then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
  end

  term.setCursorPos(1, h - 1)
  term.write(string.rep(" ", w))
  term.setCursorPos(1, h - 1)
  term.write((question .. " [y/N] "):sub(1, w))

  ui.resetColor()

  term.setCursorPos(1, h)
  term.write(string.rep(" ", w))
  term.setCursorPos(1, h)

  local answer = read()
  return answer:lower() == "y" or answer:lower() == "yes"
end

-- ─────────────────────────────────────────────
-- Formatting utilities
-- ─────────────────────────────────────────────

function ui.formatNumber(n)
  n = math.floor(tonumber(n) or 0)
  local s = tostring(math.abs(n))
  local result = ""
  local len = #s
  for i = 1, len do
    if i > 1 and (len - i + 1) % 3 == 0 then
      result = result .. ","
    end
    result = result .. s:sub(i, i)
  end
  if n < 0 then result = "-" .. result end
  return result
end

function ui.formatEnergy(fe)
  fe = tonumber(fe) or 0
  if fe >= 1e9 then
    return string.format("%.2fGFE", fe / 1e9)
  elseif fe >= 1e6 then
    return string.format("%.2fMFE", fe / 1e6)
  elseif fe >= 1e3 then
    return string.format("%.1fKFE", fe / 1e3)
  else
    return string.format("%dFE", math.floor(fe))
  end
end

function ui.formatTime(seconds)
  seconds = math.floor(tonumber(seconds) or 0)
  if seconds <= 0 then return "0s" end
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if h > 0 then
    return string.format("%dh %02dm", h, m)
  elseif m > 0 then
    return string.format("%dm %02ds", m, s)
  else
    return string.format("%ds", s)
  end
end

local _spinIdx = 0
local _spinChars = { "|", "/", "-", "\\" }
function ui.spinStep()
  _spinIdx = (_spinIdx % #_spinChars) + 1
  return _spinChars[_spinIdx]
end

function ui.wordWrap(text, width)
  text  = tostring(text or "")
  width = tonumber(width) or 40
  local lines  = {}
  local current = ""

  -- Split on existing newlines first
  for paragraph in (text .. "\n"):gmatch("(.-)\n") do
    if #paragraph == 0 then
      table.insert(lines, "")
    else
      -- Word-wrap the paragraph
      current = ""
      for word in paragraph:gmatch("%S+") do
        if #current == 0 then
          current = word
        elseif #current + 1 + #word <= width then
          current = current .. " " .. word
        else
          -- Flush current line
          table.insert(lines, current)
          current = word
        end
        -- Handle words longer than width
        while #current > width do
          table.insert(lines, current:sub(1, width))
          current = current:sub(width + 1)
        end
      end
      if #current > 0 then
        table.insert(lines, current)
      end
    end
  end

  return lines
end

return ui
