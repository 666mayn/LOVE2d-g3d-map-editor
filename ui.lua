-- Tiny immediate-mode UI for the editor overlay.
--
-- Frame protocol (the editor does this for you):
--   ui:begin()          at the start of love.draw's overlay pass
--   ... widgets ...     buttons, fields, sliders, lists, panels
--   ui:finish()
-- Events are fed in from LÖVE callbacks: press / release / keypressed /
-- textinput / wheel.  `ui:over(x, y)` tells the editor whether the mouse is on
-- a panel (using the previous frame's layout) so clicks don't reach the 3D view.
--
-- Look: flat, square-cornered, 1px borders - it matches the BoldPixels font, which is drawn at its native
-- 16px (crisp) and 32px (headings). Other sizes would blur, so there are only those two.
local UI = {}
UI.__index = UI

local okUtf8, utf8lib = pcall(require, "utf8")

-- The font ships inside this folder (map_editor/fonts/), so the editor works wherever you put the folder.
-- Set UI.FONT_PATH to another love.filesystem path (before the editor opens) to use your own pixel font.
local DIR = ((...) or ""):match("^(.*%.)[^.]+$") or ""     -- "map_editor." when required as map_editor.ui
UI.FONT_PATH = DIR:gsub("%.", "/") .. "fonts/boldpixels.ttf"
UI.HEADER = 22                           -- height of a panel's title strip

UI.theme = {
  panel   = { 0.085, 0.095, 0.125, 0.97 },
  header  = { 0.060, 0.068, 0.090, 1 },
  button  = { 0.145, 0.160, 0.205, 1 },
  panel2  = { 0.145, 0.160, 0.205, 1 },
  pressed = { 0.090, 0.100, 0.135, 1 },
  border  = { 0.215, 0.235, 0.300, 1 },
  borderHi = { 0.360, 0.395, 0.490, 1 },
  text    = { 0.90, 0.92, 0.96, 1 },
  dim     = { 0.55, 0.59, 0.68, 1 },
  hover   = { 0.205, 0.230, 0.300, 1 },
  active  = { 0.150, 0.330, 0.620, 1 },
  accent  = { 0.38, 0.68, 1.00, 1 },
  warn    = { 1.00, 0.76, 0.28, 1 },
  good    = { 0.36, 0.78, 0.50, 1 },
  goodBg  = { 0.14, 0.40, 0.25, 1 },
  danger  = { 0.88, 0.32, 0.32, 1 },
  field   = { 0.050, 0.058, 0.078, 1 },
}

local function inRect(px, py, x, y, w, h)
  return px >= x and px < x + w and py >= y and py < y + h
end
UI.inRect = inRect

-- BoldPixels if the file is there, LÖVE's default font otherwise (so the editor never fails to open over a font).
function UI.loadFont(size)
  local fs = love.filesystem
  if fs and fs.getInfo and fs.getInfo(UI.FONT_PATH) then
    local ok, f = pcall(love.graphics.newFont, UI.FONT_PATH, size)
    if ok and f then
      if f.setFilter then f:setFilter("nearest", "nearest") end
      return f
    end
  end
  return love.graphics.newFont(size)
end

function UI.new()
  local self = setmetatable({}, UI)
  self.font = UI.loadFont(16)
  self.small = self.font        -- the pixel font has one crisp size for text; "small" is told apart by colour
  self.big = UI.loadFont(32)
  self.rects, self.hit = {}, {}
  self.state = {}
  self.mx, self.my = 0, 0
  self.input = true     -- widgets react to the mouse (false while a modal is open)
  self.focus = nil      -- id of the focused text field
  self.buffer = ""
  self.replace = false  -- first keystroke replaces the whole buffer
  self.focusSeen = false
  self.hint = nil
  self.wheelDelta = 0
  self.lastClick = { t = 0, id = nil }
  self.time = 0
  self.clip = nil       -- {x,y,w,h}: widgets outside it ignore the mouse (scrolled-away rows)
  return self
end

------------------------------------------------------------- frame ------

function UI:begin(dt)
  -- Fallback typing: if LÖVE never sends love.textinput (LÖVE 12 can leave text input off), the key itself is typed.
  if self.pendingChar and self.focus and not self.textWorks then
    if self.replace then self.buffer = ""; self.replace = false end
    self.buffer = self.buffer .. self.pendingChar
  end
  self.pendingChar = nil
  self.mx, self.my = love.mouse.getPosition()
  self.down = love.mouse.isDown(1)
  self.rects = {}
  self.hint = nil
  self.focusSeen = false
  self.clip = nil
  self.time = self.time + (dt or 0)
  love.graphics.setFont(self.font)
end

function UI:finish()
  self.hit = self.rects
  self.press, self.pressBtn = nil, nil
  self.wheelDelta = 0
  self.commitReq, self.cancelReq = false, false
  if self.focus and not self.focusSeen then self.focus = nil end
end

function UI:setInput(enabled) self.input = enabled end

-- Restrict mouse interaction to a rectangle (used by scrolled panels); call clearClip() when done.
function UI:setClip(x, y, w, h) self.clip = { x, y, w, h } end
function UI:clearClip() self.clip = nil end
local function clipOk(self, px, py)
  local c = self.clip
  return not c or inRect(px, py, c[1], c[2], c[3], c[4])
end

-- register a rectangle that swallows mouse input
function UI:block(x, y, w, h)
  if self.clip then   -- only the visible part of a scrolled widget swallows the mouse
    local c = self.clip
    local x2, y2 = math.min(x + w, c[1] + c[3]), math.min(y + h, c[2] + c[4])
    x, y = math.max(x, c[1]), math.max(y, c[2])
    w, h = x2 - x, y2 - y
    if w <= 0 or h <= 0 then return end
  end
  self.rects[#self.rects + 1] = { x, y, w, h }
end

function UI:over(px, py)
  if self.modalActive then return true end
  for _, r in ipairs(self.hit) do
    if inRect(px, py, r[1], r[2], r[3], r[4]) then return true end
  end
  return false
end

-------------------------------------------------------------- events -----

function UI:onPress(x, y, button)
  self.press, self.pressBtn = { x, y }, button
end

function UI:onWheel(dy)
  self.wheelDelta = self.wheelDelta + dy
end

-- returns true if the key was consumed by a focused text field
function UI:keypressed(key)
  if not self.focus then return false end
  if key == "backspace" then
    if self.replace then self.buffer = ""; self.replace = false
    elseif okUtf8 then
      local off = utf8lib.offset(self.buffer, -1)
      if off then self.buffer = self.buffer:sub(1, off - 1) end
    else
      self.buffer = self.buffer:sub(1, -2)
    end
  elseif key == "return" or key == "kpenter" or key == "tab" then
    self.commitReq = true
  elseif key == "escape" then
    self.cancelReq = true
  elseif #key == 1 or key == "space" or key:match("^kp%d$") then
    local ctrl = love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")
    if ctrl then
      if key == "v" then
        local clip = love.system.getClipboardText() or ""
        clip = clip:gsub("[\r\n]", " ")
        if self.replace then self.buffer = ""; self.replace = false end
        self.buffer = self.buffer .. clip
      end
    else
      local shift = love.keyboard.isDown("lshift", "rshift")
      local ch
      if key == "space" then ch = " "
      elseif key:match("^kp%d$") then ch = key:sub(3)
      elseif key:match("^%a$") then ch = shift and key:upper() or key
      elseif key == "-" then ch = shift and "_" or "-"
      elseif key == "." or (key:match("^%d$") and not shift) then ch = key end
      self.pendingChar = ch   -- typed next frame unless a real textinput event shows up first
    end
  elseif key == "v" and (love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")) then
    local clip = love.system.getClipboardText() or ""
    clip = clip:gsub("[\r\n]", " ")
    if self.replace then self.buffer = ""; self.replace = false end
    self.buffer = self.buffer .. clip
  end
  return true -- swallow everything while typing
end

function UI:textinput(t)
  self.textWorks = true      -- the real text events arrive: no fallback needed
  self.pendingChar = nil
  if not self.focus then return false end
  if self.replace then self.buffer = ""; self.replace = false end
  self.buffer = self.buffer .. t
  return true
end

------------------------------------------------------------- drawing -----

local function setc(c, a)
  love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1))
end
UI.setc = setc

local function shade(c, k)
  return { c[1] * k, c[2] * k, c[3] * k, c[4] or 1 }
end
UI.shade = shade

function UI:rect(x, y, w, h, color, radius)
  setc(color)
  local r = radius or 0
  love.graphics.rectangle("fill", x, y, w, h, r, r)
end

function UI:outline(x, y, w, h, color, radius)
  setc(color or UI.theme.border)
  local r = radius or 0
  love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, r, r)
end

function UI:text(str, x, y, color, font)
  love.graphics.setFont(font or self.font)
  setc(color or UI.theme.text)
  love.graphics.print(str, math.floor(x), math.floor(y))
  love.graphics.setFont(self.font)
end

-- shorten `str` with an ellipsis so it fits in w pixels
function UI:fit(str, w, font)
  font = font or self.font
  str = tostring(str)
  if font:getWidth(str) <= w then return str end
  while #str > 1 and font:getWidth(str .. "…") > w do
    -- step back one whole UTF-8 character
    local off = okUtf8 and utf8lib.offset(str, -1)
    str = off and str:sub(1, off - 1) or str:sub(1, -2)
  end
  return str .. "…"
end

function UI:textCentered(str, x, y, w, h, color, font)
  font = font or self.font
  str = self:fit(str, w - 6, font)
  self:text(str, x + (w - font:getWidth(str)) / 2, y + (h - font:getHeight()) / 2, color, font)
end

-- Panel with an optional title strip.  Returns the y where content can start.
function UI:panel(x, y, w, h, title)
  local T = UI.theme
  self:block(x, y, w, h)
  love.graphics.setColor(0, 0, 0, 0.35)                       -- soft drop shadow
  love.graphics.rectangle("fill", x + 2, y + 3, w, h)
  self:rect(x, y, w, h, T.panel)
  local top = y
  if title then
    self:rect(x + 1, y + 1, w - 2, UI.HEADER - 1, T.header)
    self:rect(x + 1, y + UI.HEADER, w - 2, 1, T.border)
    self:rect(x + 1, y + 1, 3, UI.HEADER - 1, T.accent)       -- accent tab
    self:text(string.upper(title), x + 12, y + 4, T.dim)
    top = y + UI.HEADER
  end
  self:outline(x, y, w, h, T.border)
  return top
end

function UI:separator(x, y, w)
  setc(UI.theme.border)
  love.graphics.rectangle("fill", x, y, w, 1)
end

-- Section heading: DIM CAPS TEXT then a rule to the right edge.  Returns its height.
function UI:section(x, y, w, label, color)
  local T = UI.theme
  label = string.upper(label)
  self:text(label, x, y, color or T.dim)
  local tw = self.font:getWidth(label)
  setc(T.border)
  love.graphics.rectangle("fill", x + tw + 8, y + 7, math.max(0, w - tw - 8), 1)
  return 20
end

-- Little keycap badge (shortcut hint). Returns its width.
function UI:keycap(str, x, y, active)
  local T = UI.theme
  local w = math.max(16, self.font:getWidth(str) + 8)
  self:rect(x, y, w, 18, active and shade(T.active, 0.7) or T.field)
  self:outline(x, y, w, 18, active and T.accent or T.border)
  self:text(str, x + (w - self.font:getWidth(str)) / 2, y + 1, active and T.text or T.dim)
  return w
end

-- 8x8 pixel icons, drawn as little squares (so they stay crisp at any integer scale).
local ICONS = {
  pencil = { "......##", ".....###", "....###.", "...###..", "..###...", ".###....", "###.....", "##......" },
  box    = { "########", "#......#", "#.####.#", "#.####.#", "#.####.#", "#.####.#", "#......#", "########" },
  paint  = { "..####..", ".######.", ".######.", "..####..", "...##...", "...##...", "...##...", "...##..." },
  pick   = { "...##...", "...##...", "..#..#..", "##....##", "##....##", "..#..#..", "...##...", "...##..." },
  entity = { "..####..", ".######.", ".##..##.", ".######.", "..####..", "...##...", "...##...", "....#..." },
  select = { "#.......", "##......", "###.....", "####....", "#####...", "######..", "###.....", "..##...." },
  check  = { "........", ".......#", "......##", "#....##.", "##..##..", ".####...", "..##....", "........" },
  plus   = { "...##...", "...##...", "...##...", "########", "########", "...##...", "...##...", "...##..." },
  minus  = { "........", "........", "........", "########", "########", "........", "........", "........" },
  close  = { "##....##", "###..###", ".######.", "..####..", "..####..", ".######.", "###..###", "##....##" },
}
UI.ICONS = ICONS

function UI:icon(name, x, y, scale, color)
  local rows = ICONS[name]
  if not rows then return end
  scale = scale or 2
  setc(color or UI.theme.text)
  for r = 1, 8 do
    local row, c = rows[r], 1
    while c <= 8 do
      if row:sub(c, c) == "#" then
        local c2 = c
        while c2 < 8 and row:sub(c2 + 1, c2 + 1) == "#" do c2 = c2 + 1 end
        love.graphics.rectangle("fill", x + (c - 1) * scale, y + (r - 1) * scale, (c2 - c + 1) * scale, scale)
        c = c2 + 1
      else
        c = c + 1
      end
    end
  end
end

-- Tooltip-ish hint shown in the status bar while hovered
local function hover(self, x, y, w, h, hint)
  local on = self.input and inRect(self.mx, self.my, x, y, w, h) and clipOk(self, self.mx, self.my)
  if on and hint then self.hint = hint end
  return on
end

local function clicked(self, x, y, w, h, btn)
  if not self.input or not self.press then return false end
  if self.pressBtn ~= (btn or 1) then return false end
  if not clipOk(self, self.press[1], self.press[2]) then return false end
  if inRect(self.press[1], self.press[2], x, y, w, h) then
    self.press = nil
    return true
  end
  return false
end

----------------------------------------------------------- widgets -------

-- opts: active, disabled, hint, color (swatch fill), danger, primary
function UI:button(x, y, w, h, label, opts)
  opts = opts or {}
  local T = UI.theme
  local on = hover(self, x, y, w, h, opts.hint) and not opts.disabled
  local down = on and self.down
  local base = T.button
  if opts.primary then base = T.goodBg end
  if opts.danger then base = { 0.30, 0.13, 0.14, 1 } end
  local bg = base
  if opts.active then bg = T.active
  elseif down then bg = T.pressed
  elseif on then bg = opts.primary and shade(T.goodBg, 1.3) or T.hover end
  if opts.danger and on then bg = T.danger end
  self:block(x, y, w, h)
  self:rect(x, y, w, h, bg)
  if not down and not opts.disabled then
    love.graphics.setColor(1, 1, 1, 0.07)                       -- bevel: light top edge, dark bottom edge
    love.graphics.rectangle("fill", x + 1, y + 1, w - 2, 1)
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.rectangle("fill", x + 1, y + h - 2, w - 2, 1)
  end
  if opts.color then
    self:rect(x + 3, y + 3, w - 6, h - 6, opts.color)
  end
  local edge = T.border
  if opts.active then edge = T.accent
  elseif opts.primary then edge = T.good
  elseif opts.danger then edge = on and T.danger or { 0.55, 0.22, 0.22, 1 }
  elseif on then edge = T.borderHi end
  self:outline(x, y, w, h, edge)
  if label and label ~= "" then
    local col = T.text
    if opts.disabled then col = shade(T.dim, 0.75) end
    self:textCentered(label, x, y + (down and 1 or 0), w, h, col)
  end
  if opts.disabled then return false end
  return clicked(self, x, y, w, h, opts.button)
end

function UI:swatch(x, y, s, color, active, hint)
  local T = UI.theme
  local on = hover(self, x, y, s, s, hint)
  self:block(x, y, s, s)
  if active then
    self:rect(x - 3, y - 3, s + 6, s + 6, T.accent)             -- chunky selection frame
    self:rect(x - 2, y - 2, s + 4, s + 4, T.header)
  end
  self:rect(x, y, s, s, color)
  self:outline(x, y, s, s, active and { 1, 1, 1, 1 } or (on and T.accent or { 0, 0, 0, 0.55 }))
  return clicked(self, x, y, s, s)
end

function UI:checkbox(x, y, label, value, hint)
  local T = UI.theme
  local box = 20
  local w = box + 8 + self.font:getWidth(label)
  local on = hover(self, x, y, w, box, hint)
  self:block(x, y, w, box)
  self:rect(x, y, box, box, on and T.hover or T.field)
  self:outline(x, y, box, box, value and T.accent or (on and T.borderHi or T.border))
  if value then self:icon("check", x + 2, y + 2, 2, T.accent) end
  self:text(label, x + box + 8, y + 3)
  if clicked(self, x, y, w, box) then return not value end
  return value
end

-- Single-line text field. Returns (value, committed). `value` is the live
-- buffer while editing, and `committed` is true on Enter / Tab / click-away.
function UI:textfield(id, x, y, w, h, value, opts)
  opts = opts or {}
  local T = UI.theme
  value = tostring(value)
  self:block(x, y, w, h)
  local focused = self.focus == id
  if focused then self.focusSeen = true end

  -- press handling
  if self.input and self.press and self.pressBtn == 1 then
    local inside = inRect(self.press[1], self.press[2], x, y, w, h) and clipOk(self, self.press[1], self.press[2])
    if inside then
      if not focused then
        self.focus, self.buffer, self.replace = id, value, true
        self.focusSeen, focused = true, true
      end
      self.press = nil
    elseif focused then
      -- click elsewhere: commit and let the click carry on
      self.focus = nil
      return self.buffer, true
    end
  end

  local committed = false
  if focused then
    if self.commitReq then
      self.commitReq = false
      self.focus = nil
      return self.buffer, true
    elseif self.cancelReq then
      self.cancelReq = false
      self.focus = nil
      return value, false
    end
    value = self.buffer
  end

  local on = hover(self, x, y, w, h, opts.hint)
  self:rect(x, y, w, h, T.field)
  love.graphics.setColor(0, 0, 0, 0.35)                           -- inset top shadow
  love.graphics.rectangle("fill", x + 1, y + 1, w - 2, 2)
  self:outline(x, y, w, h, focused and T.accent or (on and T.borderHi or T.border))
  local shown = self:fit(value, w - 12)
  local fh = self.font:getHeight()
  local ty = y + (h - fh) / 2
  if focused and self.replace then
    local tw = self.font:getWidth(shown)
    self:rect(x + 5, ty, tw + 1, fh, { T.accent[1], T.accent[2], T.accent[3], 0.4 })
  end
  self:text(shown, x + 6, ty, focused and T.text or (opts.dimmed and T.dim or T.text))
  if focused and (math.floor(self.time * 2) % 2 == 0) and not self.replace then
    local cx = x + 6 + self.font:getWidth(shown)
    setc(T.accent)
    love.graphics.rectangle("fill", cx + 1, ty + 1, 2, fh - 2)
  end
  return value, committed
end

function UI:slider(id, x, y, w, h, value, lo, hi, hint)
  local T = UI.theme
  local st = self.state
  local on = hover(self, x, y, w, h, hint)
  self:block(x, y, w, h)
  if self.input and self.press and self.pressBtn == 1 and inRect(self.press[1], self.press[2], x, y, w, h)
      and clipOk(self, self.press[1], self.press[2]) then
    st.sliding = id
    self.press = nil
  end
  if st.sliding == id then
    if self.down then
      local t = math.max(0, math.min(1, (self.mx - x) / w))
      value = lo + (hi - lo) * t
    else
      st.sliding = nil
    end
  end
  local t = (value - lo) / (hi - lo)
  local active = on or st.sliding == id
  local ty = y + math.floor(h / 2) - 2
  self:rect(x, ty, w, 4, T.field)
  self:outline(x, ty, w, 4, T.border)
  self:rect(x + 1, ty + 1, math.max(0, (w - 2) * t), 2, T.accent)
  local hx = math.floor(x + (w - 8) * t)
  self:rect(hx, y + 1, 8, h - 2, active and { 1, 1, 1, 1 } or T.text)
  self:outline(hx, y + 1, 8, h - 2, { 0, 0, 0, 0.5 })
  return value
end

-- Scrollable list of strings. Returns (clickedIndex, doubleClicked).
function UI:list(id, x, y, w, h, items, selected)
  local T = UI.theme
  local rowH = 22
  local st = self.state[id] or { scroll = 0 }
  self.state[id] = st
  self:block(x, y, w, h)
  self:rect(x, y, w, h, T.field)
  self:outline(x, y, w, h, T.border)

  local maxScroll = math.max(0, #items * rowH - h)
  if self.input and self.wheelDelta ~= 0 and inRect(self.mx, self.my, x, y, w, h) then
    st.scroll = st.scroll - self.wheelDelta * rowH * 2
    self.wheelDelta = 0
  end
  st.scroll = math.max(0, math.min(maxScroll, st.scroll))

  love.graphics.setScissor(x + 1, y + 1, w - 2, h - 2)
  local clickedIdx, dbl
  for i, item in ipairs(items) do
    local ry = y + (i - 1) * rowH - st.scroll
    if ry + rowH > y and ry < y + h then
      local on = self.input and inRect(self.mx, self.my, x, ry, w, rowH) and inRect(self.mx, self.my, x, y, w, h)
      if i == selected then
        self:rect(x + 1, ry, w - 2, rowH, T.active)
        self:rect(x + 1, ry, 3, rowH, T.accent)
      elseif on then self:rect(x + 1, ry, w - 2, rowH, T.hover)
      elseif i % 2 == 0 then self:rect(x + 1, ry, w - 2, rowH, { 1, 1, 1, 0.025 }) end
      self:text(self:fit(item, w - 24), x + 12, ry + 3)
      if self.input and self.press and self.pressBtn == 1
          and inRect(self.press[1], self.press[2], x, ry, w, rowH)
          and inRect(self.press[1], self.press[2], x, y, w, h) then
        clickedIdx = i
        local now = self.time
        dbl = (self.lastClick.id == id .. i) and (now - self.lastClick.t < 0.4)
        self.lastClick = { t = now, id = id .. i }
        self.press = nil
      end
    end
  end
  love.graphics.setScissor()
  if maxScroll > 0 then self:scrollbar(x + w - 6, y + 2, 4, h - 4, st.scroll, maxScroll, h) end
  if #items == 0 then self:text("(empty)", x + 10, y + 4, T.dim) end
  return clickedIdx, dbl
end

-- Thin scrollbar thumb. `view` = visible height, `maxScroll` = content height - view.
function UI:scrollbar(x, y, w, h, scroll, maxScroll, view)
  local T = UI.theme
  if maxScroll <= 0 then return end
  local total = maxScroll + view
  local th = math.max(18, h * view / total)
  local ty = y + (h - th) * (scroll / maxScroll)
  self:rect(x, y, w, h, { 0, 0, 0, 0.25 })
  self:rect(x, ty, w, th, T.borderHi)
end

return UI
