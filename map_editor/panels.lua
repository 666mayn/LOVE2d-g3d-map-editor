-- 2D overlay: toolbar, tool column, palette bar, inspector, status bar, dialogs.
-- Called as  require("map_editor.panels")(Editor)  to add methods to the class.
local BASE = ((...) or ""):match("^(.*%.)[^.]+$") or ""
local UI = require(BASE .. "ui")
local Surfaces = require(BASE .. "surfaces")
local Entities = require(BASE .. "entities")

local T = UI.theme
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local TOP, LEFT, RIGHT, STATUS = 36, 132, 288, 24
local TOOL_PITCH = 38

local function fmt(v)
  if type(v) ~= "number" then return tostring(v) end
  if v == floor(v) then return string.format("%d", v) end
  return (string.format("%.3f", v):gsub("0+$", ""):gsub("%.$", ""))
end

local HELP = {
  { "Camera", "" },
  { "MMB drag / Alt+LMB", "orbit" },
  { "Shift+MMB / Alt+Shift+LMB", "pan" },
  { "Wheel", "zoom" },
  { "W A S D", "move (hold Shift: faster)" },
  { "T / V", "top view / side (horizontal) view - press again to tilt back" },
  { "Z / C", "swing the view 90 degrees around the map (all 4 sides)" },
  { "F / Home", "focus selection or map / reset view" },
  { "F9", "flip left-right if the cursor looks mirrored" },
  { "Tools", "" },
  { "1-6", "pencil, box, paint, pick, entity, select" },
  { "LMB / RMB", "place / erase (pencil, box)" },
  { "Q / E, [ ]", "layer down / up   (Shift+wheel too)" },
  { "L  /  G", "lock edits to the layer  /  toggle grid" },
  { ", .  or  Ctrl+wheel", "previous / next block type" },
  { "I", "pick the block under the cursor" },
  { "Entities", "" },
  { "R / Shift+R", "rotate selected 90 degrees" },
  { "Del or X, Ctrl+D", "delete / duplicate selected" },
  { "File", "" },
  { "Ctrl+Z / Ctrl+Y", "undo / redo" },
  { "Ctrl+S, Ctrl+Shift+S", "save / save as" },
  { "Ctrl+O, Ctrl+N", "open / new" },
  { "Ctrl+G", "Export: write the level into the game's level folder" },
  { "F5", "play-test (walk around your level)" },
}

return function(Editor)

-- Layout numbers other code (and the tests) can rely on.
Editor.LAYOUT = {
  top = TOP, left = LEFT, right = RIGHT, status = STATUS,
  toolX = 8, toolY0 = TOP + 6 + UI.HEADER + 6, toolPitch = TOOL_PITCH,
}

local function lineH(ui) return ui.font:getHeight() end

------------------------------------------------------------------ main ----

function Editor:drawPanels(W, H)
  local ui = self.ui
  ui.modalActive = self.dialog ~= nil
  ui:setInput(not self.dialog)

  if self.mode == "play" then
    self:drawPlayHud(W, H)
    ui:setInput(true)
    return
  end

  self:drawToolbar(W)
  self:drawToolColumn(H)
  self:drawInspector(W, H)
  self:drawPalette(W, H)
  self:drawStatus(W, H)

  if self.dialog then
    ui:setInput(true)
    self:drawDialog(W, H)
  end
end

-- text with a 1px drop shadow, for text drawn over the 3D view
local function shadowed(ui, str, x, y, color)
  ui:text(str, x + 1, y + 1, { 0, 0, 0, 0.8 })
  ui:text(str, x, y, color)
end

function Editor:drawPlayHud(W, H)
  local ui = self.ui
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", W / 2 - 2, H / 2 - 9, 4, 18)
  love.graphics.rectangle("fill", W / 2 - 9, H / 2 - 2, 18, 4)
  love.graphics.setColor(1, 1, 1, 0.95)
  love.graphics.rectangle("fill", W / 2 - 1, H / 2 - 8, 2, 16)
  love.graphics.rectangle("fill", W / 2 - 8, H / 2 - 1, 16, 2)
  local w = self.walker
  ui:rect(8, 8, 74, 22, { 0.85, 0.30, 0.30, 0.95 })
  ui:text("PLAY-TEST", 16, 11, { 1, 1, 1, 1 })
  shadowed(ui, string.format("WASD move   Space jump   Shift run   Esc / F5 back to the editor     %.1f, %.1f, %.1f",
    w.x, w.y, w.z), 92, 11, { 1, 1, 1, 0.95 })
  if self.flashTime > 0 then shadowed(ui, self.flashText, 12, 38, T.accent) end
end

------------------------------------------------------------- toolbar -----

function Editor:drawToolbar(W)
  local ui = self.ui
  ui:panel(0, 0, W, TOP)
  love.graphics.setColor(1, 1, 1, 0.05)
  love.graphics.rectangle("fill", 1, 1, W - 2, 1)
  local x, y, h = 6, 5, TOP - 10
  local function btn(label, opts)
    opts = opts or {}
    local w = ui.font:getWidth(label) + 20
    local hit = ui:button(x, y, w, h, label, opts)
    x = x + w + 4
    return hit
  end
  local function gap()
    x = x + 4
    ui:rect(x, y + 3, 1, h - 6, T.border)
    x = x + 9
  end

  if btn("New", { hint = "New map (Ctrl+N)" }) then self:newMap() end
  if btn("Open", { hint = "Open a map (Ctrl+O)" }) then self:openDialog("open") end
  if btn("Save", { hint = "Save (Ctrl+S)" }) then self:save() end
  if btn("Save As", { hint = "Save under a new name (Ctrl+Shift+S)" }) then self:openDialog("saveas") end
  if btn("Export", { hint = "Write this level into the game's level folder so the game can load it (Ctrl+G)" }) then self:exportToGame() end
  gap()
  if btn("Undo", { hint = "Undo (Ctrl+Z)", disabled = #self.hist.undoStack == 0 }) then self:undo() end
  if btn("Redo", { hint = "Redo (Ctrl+Y)", disabled = #self.hist.redoStack == 0 }) then self:redo() end
  gap()
  if btn("Grid", { active = self.showGrid, hint = "Show the grid (G)" }) then self.showGrid = not self.showGrid end
  if btn("Lock layer", { active = self.lockLayer, hint = "Only edit on the current layer (L). Best used from the top view." }) then
    self.lockLayer = not self.lockLayer
  end
  if btn("Top view", { hint = "Look straight down (T)" }) then self.cam:topDown() end
  if btn("Focus", { hint = "Centre the view on the selection or the map (F)" }) then self:focusView() end
  gap()
  if btn("Play", { primary = true, hint = "Walk around the level (F5)" }) then self:startPlay() end
  if btn("Help", { hint = "Keyboard shortcuts (F1)" }) then self:openDialog("help") end
  if btn("Exit", { hint = "Leave the editor (F10)" }) and self.onLeave then self.onLeave() end

  -- file name, right aligned:  [amber square if unsaved]  folder/ NAME
  local full = self.path or "untitled"
  local modified = self:isModified()
  local room = W - x - 40
  local dir, base = full:match("^(.*/)([^/]+)$")
  base = base or full
  dir = dir or ""
  local bw = ui.font:getWidth(base)
  local dw = ui.font:getWidth(dir)
  if bw + dw > room then dir, dw = "", 0 end
  if bw > room then base = ui:fit(base, room); bw = ui.font:getWidth(base) end
  local nx = W - 12 - bw
  ui:text(base, nx, 10, modified and T.warn or T.text)
  if dw > 0 then ui:text(dir, nx - dw, 10, T.dim) end
  if modified then
    local dx = nx - dw - 14
    ui:rect(dx, 14, 8, 8, T.warn)
  end
end

----------------------------------------------------------- tool column ----

function Editor:drawToolColumn(H)
  local ui = self.ui
  local L = Editor.LAYOUT
  local bw = LEFT - 16
  local ph = UI.HEADER + 6 + #Editor.TOOLS * TOOL_PITCH + 6 + 20 + 30 + 28 + 10
  ui:panel(4, TOP + 6, LEFT - 8, ph, "Tools")
  local x, y = L.toolX, L.toolY0
  local fh = lineH(ui)
  for _, t in ipairs(Editor.TOOLS) do
    local on = self.tool == t.id
    if ui:button(x, y, bw, 34, "", { active = on, hint = t.hint }) then self:setTool(t.id) end
    ui:icon(t.id, x + 8, y + 9, 2, on and T.text or T.accent)
    ui:text(t.label, x + 32, y + math.floor((34 - fh) / 2), T.text)
    ui:keycap(t.key, x + bw - 22, y + 8, on)
    y = y + TOOL_PITCH
  end

  y = y + 2
  y = y + ui:section(x + 2, y, bw - 4, "Layer")
  if ui:button(x, y, 24, 24, "", { hint = "Layer down (Q)" }) then self.layer = self.layer - 1 end
  ui:icon("minus", x + 8, y + 8, 1, T.text)
  local fw = bw - 48 - 8
  local v, done = ui:textfield("layer", x + 28, y, fw, 24, self.layer)
  if done and tonumber(v) then self.layer = floor(tonumber(v)) end
  if ui:button(x + bw - 24, y, 24, 24, "", { hint = "Layer up (E)" }) then self.layer = self.layer + 1 end
  ui:icon("plus", x + bw - 16, y + 8, 1, T.text)
  y = y + 30
  local lock = ui:checkbox(x + 2, y, "Lock", self.lockLayer, "Only edit on this layer (L)")
  if lock ~= self.lockLayer then self.lockLayer = lock end
end

-------------------------------------------------------------- palette -----

local SW, PITCH = 24, 32

local function paletteLayout(self, W)
  local avail = W - LEFT - RIGHT - 16
  local per = max(1, floor((avail - 12) / PITCH))
  local n = #self.map.palette + 1 -- + the "add" button
  local rows = ceil(n / per)
  return per, rows
end

function Editor:drawPalette(W, H)
  local ui = self.ui
  local per, rows = paletteLayout(self, W)
  local info = 30
  local ph = UI.HEADER + info + rows * PITCH + 10
  local px, py, pw = LEFT, H - STATUS - ph - 6, W - LEFT - RIGHT
  ui:panel(px, py, pw, ph, "Blocks")

  local def = self.map.palette[self.cur]
  local iy = py + UI.HEADER + 7
  ui:rect(px + 12, iy + 2, 12, 12, def and def.color or { 1, 1, 1 })
  ui:outline(px + 12, iy + 2, 12, 12, { 0, 0, 0, 0.6 })
  local nm = def and def.name or "?"
  ui:text(nm, px + 32, iy, T.text)
  local st = def and def.surface and Surfaces.byId[def.surface]
  local extra = (st and ("[" .. st.label .. "]") or "") .. ((def and def.solid == false) and "  not solid" or "")
  if extra ~= "" then ui:text(extra, px + 42 + ui.font:getWidth(nm), iy, T.dim) end

  if ui:button(px + pw - 66, iy - 4, 54, 24, "Edit", { hint = "Edit this block type's name, colour and solidity" }) then
    self:openDialog("palette")
  end

  local gy = py + UI.HEADER + info + 4
  for i, d in ipairs(self.map.palette) do
    local col, row = (i - 1) % per, floor((i - 1) / per)
    local sx, sy = px + 14 + col * PITCH, gy + row * PITCH
    local sd = d.surface and Surfaces.byId[d.surface]
    if ui:swatch(sx, sy, SW, d.color, i == self.cur, d.name .. (sd and (" [" .. sd.label .. "]") or "") .. (d.solid == false and " (not solid)" or "")) then
      self.cur = i
    end
  end
  local i = #self.map.palette
  local col, row = i % per, floor(i / per)
  local bx, by = px + 14 + col * PITCH, gy + row * PITCH
  if ui:button(bx, by, SW, SW, "", { hint = "Add a new block type" }) then
    local cur = self.map.palette[self.cur]
    local sid = (cur and cur.surface) or (Surfaces.types[1] and Surfaces.types[1].id)
    local c = (Surfaces.byId[sid] or { color = self:blockColor() }).color
    table.insert(self.map.palette, { name = "block" .. (#self.map.palette + 1), surface = sid, color = { c[1], c[2], c[3] }, solid = true })
    self.cur = #self.map.palette
    self.paletteModified = true
    self:openDialog("palette")
  end
  ui:icon("plus", bx + 8, by + 8, 1, T.text)
end

------------------------------------------------------------- inspector ----

local FIELD, ROW = 22, 26

local function numField(self, id, x, y, w, label, value, apply)
  local ui = self.ui
  ui:text(label, x, y + 3, T.dim)
  local lw = ui.font:getWidth(label) + 6
  local v, done = ui:textfield(id, x + lw, y, w - lw, FIELD, fmt(value))
  if done then
    local n = tonumber(v)
    if n then apply(n) end
  end
end

function Editor:drawInspector(W, H)
  local ui = self.ui
  local px, py = W - RIGHT, TOP + 6
  local pw, ph = RIGHT - 4, H - py - STATUS - 6
  local top = ui:panel(px, py, pw, ph, "Inspector")

  -- scrolling: content taller than the panel scrolls with the wheel (position kept between frames)
  local viewY, viewH = top + 1, ph - UI.HEADER - 2
  local maxScroll = max(0, (self.inspContentH or 0) - viewH)
  self.inspScroll = self.inspScroll or 0
  if ui.input and ui.wheelDelta ~= 0 and UI.inRect(ui.mx, ui.my, px, py, pw, ph) then
    self.inspScroll = self.inspScroll - ui.wheelDelta * 48
    ui.wheelDelta = 0
  end
  self.inspScroll = max(0, min(maxScroll, self.inspScroll))

  love.graphics.setScissor(px + 1, viewY, pw - 2, viewH)
  ui:setClip(px + 1, viewY, pw - 2, viewH)
  local x, w = px + 12, pw - 12 - 16
  local y0 = top + 10 - self.inspScroll
  local y = y0

  local function drawChooser()
    -- entity type chooser (entity tool)
    if self.tool == "entity" then
      y = y + ui:section(x, y, w, "Entity type")
      local lastGroup
      for _, def in ipairs(self.entityTypes) do
        local grp = def.group or "General"
        if grp ~= lastGroup then
          ui:text(string.upper(grp), x + 2, y + 2, T.accent); y = y + 22
          lastGroup = grp
        end
        local on = def.name == self.entityType
        if ui:button(x, y, w, 24, "", { active = on }) then self.entityType = def.name end
        ui:rect(x + 7, y + 6, 12, 12, def.color)
        ui:outline(x + 7, y + 6, 12, 12, { 0, 0, 0, 0.6 })
        ui:text(ui:fit(def.name, w - 36), x + 28, y + 4)
        y = y + 27
      end
      y = y + 6
    end
  end

  local e = self.sel
  local function drawSelected()
    local def = self.entityIndex[e.type]
    y = y + ui:section(x, y, w, "Selected", T.accent)
    ui:rect(x, y + 2, 12, 12, def and def.color or T.accent)
    ui:outline(x, y + 2, 12, 12, { 0, 0, 0, 0.6 })
    ui:text(ui:fit(e.type, w - 70), x + 20, y, T.text)
    local idt = "#" .. e.id
    ui:text(idt, x + w - ui.font:getWidth(idt), y, T.dim)
    y = y + 24
    local id = "e" .. e.id .. ":"
    local lc = 44
    ui:text("name", x, y + 3, T.dim)
    local v, done = ui:textfield(id .. "name", x + lc, y, w - lc, FIELD, e.name)
    if done then self:setField(e, "name", v) end
    y = y + ROW
    local half = floor(w / 2) - 3
    numField(self, id .. "x", x, y, half, "x", e.x, function(n) self:setField(e, "x", n) end)
    numField(self, id .. "y", x + half + 6, y, half, "y", e.y, function(n) self:setField(e, "y", n) end)
    y = y + ROW
    numField(self, id .. "z", x, y, half, "z", e.z, function(n) self:setField(e, "z", n) end)
    numField(self, id .. "yaw", x + half + 6, y, half, "yaw", e.yaw, function(n) self:setField(e, "yaw", n % 360) end)
    y = y + ROW + 6

    -- property rows: schema props first, then any extra keys the entity carries
    local rows, seen = {}, {}
    for _, pd in ipairs(def and def.props or {}) do
      seen[pd.name] = true
      rows[#rows + 1] = { pd.name, pd.kind, pd.options }
    end
    local extra = {}
    for k in pairs(e.props) do if not seen[k] then extra[#extra + 1] = k end end
    table.sort(extra)
    for _, k in ipairs(extra) do
      rows[#rows + 1] = { k, type(e.props[k]) == "boolean" and "bool" or (type(e.props[k]) == "number" and "number" or "string") }
    end
    if #rows > 0 then
      y = y + ui:section(x, y, w, "Properties")
    end
    -- one shared label column so every field lines up
    local lw = 0
    for _, r in ipairs(rows) do
      if r[2] ~= "bool" then lw = max(lw, ui.font:getWidth(r[1])) end
    end
    lw = min(lw + 10, floor(w * 0.5))

    for _, r in ipairs(rows) do
      local name, kind, options = r[1], r[2], r[3]
      local val = e.props[name]
      if kind == "bool" then
        local nv = ui:checkbox(x, y, name, val == true)
        if nv ~= (val == true) then self:setProp(e, name, nv) end
        y = y + ROW
      elseif kind == "choice" and options and #options > 0 then
        ui:text(ui:fit(name, lw - 6), x, y + 3, T.dim)
        if ui:button(x + lw, y, w - lw, FIELD, tostring(val)) then
          local idx = 1
          for i, o in ipairs(options) do if o == val then idx = i end end
          self:setProp(e, name, options[idx % #options + 1])
        end
        y = y + ROW
      else
        ui:text(ui:fit(name, lw - 6), x, y + 3, T.dim)
        local s, fin = ui:textfield(id .. "p:" .. name, x + lw, y, w - lw, FIELD, val == nil and "" or tostring(val))
        if fin then
          if kind == "number" or (kind == nil and type(val) == "number") then
            local n = tonumber(s)
            if n then self:setProp(e, name, n) end
          else
            self:setProp(e, name, s)
          end
        end
        y = y + ROW
      end
    end

    y = y + 4
    local bw = floor((w - 8) / 3)
    if ui:button(x, y, bw, 26, "Rotate", { hint = "Rotate 90 degrees (R)" }) then self:rotateSelected(90) end
    if ui:button(x + bw + 4, y, bw, 26, "Copy", { hint = "Duplicate (Ctrl+D)" }) then self:duplicateSelected() end
    if ui:button(x + 2 * (bw + 4), y, bw, 26, "Delete", { danger = true, hint = "Delete (Del)" }) then self:deleteSelected() end
    y = y + 36
  end

  -- With an entity selected its buttons (Rotate / Copy / Delete) come FIRST, so they are never pushed off the
  -- bottom of the panel by the long type list.
  if e then
    drawSelected()
    drawChooser()
  elseif self.tool == "entity" then
    drawChooser()
  elseif self.tool == "select" then
    ui:text("Click an entity to inspect it.", x, y, T.dim); y = y + 28
  end

  -- map info
  y = y + ui:section(x, y, w, "Map")
  ui:text("name", x, y + 3, T.dim)
  local nv, ndone = ui:textfield("mapname", x + 44, y, w - 44, FIELD, self.map.name)
  if ndone and nv ~= "" then self.map.name = nv; self.paletteModified = true end
  y = y + ROW + 2
  local chunks = 0
  for _ in pairs(self.map.chunks) do chunks = chunks + 1 end
  local function stat(label, value)
    ui:text(label, x, y, T.dim)
    local s = tostring(value)
    ui:text(s, x + w - ui.font:getWidth(s), y, T.text)
    y = y + 20
  end
  stat("blocks", self.map.count)
  stat("chunks", chunks)
  stat("entities", #self.map.entities)
  y = y + 6

  y = y + ui:section(x, y, w, "Sky colour")
  local sky = self.map.sky
  local names, cols = { "R", "G", "B" }, { { 1, 0.45, 0.45, 1 }, { 0.5, 0.9, 0.5, 1 }, { 0.5, 0.65, 1, 1 } }
  for i = 1, 3 do
    ui:text(names[i], x, y + 2, cols[i])
    local nvv = ui:slider("sky" .. i, x + 20, y, w - 20, 20, sky[i], 0, 1)
    if nvv ~= sky[i] then sky[i] = nvv; self.paletteModified = true end
    y = y + 24
  end
  ui:rect(x, y + 2, w, 14, { sky[1], sky[2], sky[3], 1 })
  ui:outline(x, y + 2, w, 14, T.border)
  y = y + 24

  self.inspContentH = (y - y0) + 20
  ui:clearClip()
  love.graphics.setScissor()
  if maxScroll > 0 then ui:scrollbar(px + pw - 7, viewY + 3, 4, viewH - 6, self.inspScroll, maxScroll, viewH) end
end

-------------------------------------------------------------- status ------

function Editor:drawStatus(W, H)
  local ui = self.ui
  local y = H - STATUS
  ui:panel(0, y, W, STATUS)
  local ty = y + floor((STATUS - lineH(ui)) / 2)
  local left
  if self.flashTime > 0 then
    ui:rect(8, y + 8, 8, 8, self.flashBad and T.danger or T.accent)
    ui:text(self.flashText, 24, ty, self.flashBad and T.danger or T.accent)
  else
    left = ui.hint
    if not left then
      for _, t in ipairs(Editor.TOOLS) do if t.id == self.tool then left = t.hint end end
    end
    ui:text(ui:fit(left or "", W - 520), 10, ty, T.dim)
  end

  -- right side: segments separated by thin rules, laid out right to left
  local hv = self.hover
  local segs = {}
  if hv and hv.kind then
    local c = self.tool == "pencil" and hv.place or hv.target
    segs[#segs + 1] = { string.format("cell %d, %d, %d", c[1], c[2], c[3]), T.text }
  end
  segs[#segs + 1] = { string.format("layer %d%s", self.layer, self.lockLayer and " (locked)" or ""), self.lockLayer and T.warn or T.dim }
  segs[#segs + 1] = { string.format("%d fps", love.timer.getFPS()), T.dim }
  local x = W - 10
  for i = #segs, 1, -1 do
    local s = segs[i]
    x = x - ui.font:getWidth(s[1])
    ui:text(s[1], x, ty, s[2])
    if i > 1 then
      x = x - 10
      ui:rect(x, y + 5, 1, STATUS - 10, T.border)
      x = x - 10
    end
  end
end

-------------------------------------------------------------- dialogs -----

local DLG_HEAD = 44

-- Returns the content origin (x, y) and the usable width. Closing with the title-bar X works like Cancel.
local function dialogFrame(self, W, H, w, h, title)
  local ui = self.ui
  ui:block(0, 0, W, H)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", 0, 0, W, H)
  local x, y = floor((W - w) / 2), floor((H - h) / 2)
  ui:panel(x, y, w, h)
  ui:rect(x + 1, y + 1, w - 2, DLG_HEAD, T.header)
  ui:rect(x + 1, y + DLG_HEAD + 1, w - 2, 2, T.accent)
  ui:text(title, x + 16, y + 8, T.text, ui.big)
  if ui:button(x + w - 36, y + 8, 28, 28, "", { hint = "Close (Esc)" }) then self:closeDialog() end
  ui:icon("close", x + w - 36 + 6, y + 8 + 6, 2, T.dim)
  ui:outline(x, y, w, h, T.borderHi)
  return x + 16, y + DLG_HEAD + 16, w - 32
end

function Editor:drawDialog(W, H)
  local ui, d = self.ui, self.dialog
  if d.kind == "open" then self:dialogOpen(W, H)
  elseif d.kind == "saveas" then self:dialogSaveAs(W, H)
  elseif d.kind == "confirm" then self:dialogConfirm(W, H)
  elseif d.kind == "palette" then self:dialogPalette(W, H)
  elseif d.kind == "help" then self:dialogHelp(W, H) end
end

function Editor:dialogOpen(W, H)
  local ui, d = self.ui, self.dialog
  local x, y, w = dialogFrame(self, W, H, 440, 356, "Open map")
  ui:text("in " .. self.mapDir .. "/", x, y - 8, T.dim)
  local idx, dbl = ui:list("openlist", x, y + 16, w, 220, d.files, d.sel)
  if idx then d.sel = idx end
  local f = d.files[d.sel]
  local function go()
    if not f then return end
    self:closeDialog()
    self:guard(function()
      local ok, err = self:openPath(self:pathFor(f))
      if not ok then self:flash("Could not open: " .. tostring(err), 5, true) end
    end)
  end
  if dbl then go() end
  if ui:button(x, y + 246, 96, 28, "Open", { primary = true, disabled = not f }) then go() end
  if ui:button(x + 104, y + 246, 96, 28, "Cancel") then self:closeDialog() end
end

function Editor:dialogSaveAs(W, H)
  local ui, d = self.ui, self.dialog
  local x, y, w = dialogFrame(self, W, H, 440, 176, "Save map as")
  if not d.focused then
    d.focused = true
    ui.focus, ui.buffer, ui.replace = "saveas_name", d.name, true
  end
  ui:text("name (saved to " .. self.mapDir .. "/NAME.lua)", x, y - 8, T.dim)
  local v, done = ui:textfield("saveas_name", x, y + 16, w, 28, d.name)
  d.name = v
  local function go()
    if Editor.sanitize(d.name) == "" then return end
    self:closeDialog()
    self:saveAs(d.name)
  end
  if done then go() end
  if ui:button(x, y + 62, 96, 28, "Save", { primary = true }) then go() end
  if ui:button(x + 104, y + 62, 96, 28, "Cancel") then self:closeDialog() end
end

function Editor:dialogConfirm(W, H)
  local ui, d = self.ui, self.dialog
  local dw = 460
  local text = d.text or ""
  local lines = 1
  local okw, _, wrapped = pcall(function() return ui.font:getWrap(text, dw - 32) end)
  if okw and type(wrapped) == "table" and #wrapped > 0 then lines = #wrapped end
  local fh = lineH(ui)
  local h = DLG_HEAD + 16 + lines * (fh + 2) + 18 + 28 + 20
  local x, y, w = dialogFrame(self, W, H, dw, h, "Are you sure?")
  love.graphics.setFont(ui.font)
  UI.setc(T.text)
  love.graphics.printf(text, x, y, w, "left")
  local by = y + lines * (fh + 2) + 18
  if ui:button(x, by, 110, 28, d.yes or "OK", { danger = true }) then
    self:closeDialog()
    if d.onYes then d.onYes() end
  end
  if ui:button(x + 118, by, 110, 28, "Cancel") then self:closeDialog() end
end

function Editor:dialogHelp(W, H)
  local ui = self.ui
  local nSections = 0
  for _, row in ipairs(HELP) do if row[2] == "" then nSections = nSections + 1 end end
  local nRows = #HELP - nSections
  -- shrink the row height if the window is short, so the Close button never falls off the bottom
  local fixed = DLG_HEAD + 16 + 16 + 28 + 24 + nSections * 30
  local rowH = max(17, min(22, floor((H - 24 - fixed) / nRows)))
  local h = fixed + nRows * rowH
  local x, y, w = dialogFrame(self, W, H, 760, h, "Keyboard & mouse")
  for _, row in ipairs(HELP) do
    if row[2] == "" then
      y = y + 8
      y = y + ui:section(x, y, w, row[1], T.accent) + 2
    else
      ui:keycap(row[1], x, y - 1, false)   -- key combo in a keycap
      ui:text(row[2], x + 262, y, T.dim)
      y = y + rowH
    end
  end
  if ui:button(x, y + 10, 96, 28, "Close", { primary = true }) then self:closeDialog() end
end

function Editor:dialogPalette(W, H)
  local ui = self.ui
  local def = self.map.palette[self.cur]
  if not def then self:closeDialog(); return end
  local x, y, w = dialogFrame(self, W, H, 540, def.solid == false and 408 or 374, "Block type #" .. self.cur)
  local changed = false

  ui:text("name", x, y + 5, T.dim)
  local nv, done = ui:textfield("pal_name", x + 56, y, w - 56, 28, def.name)
  if done and nv ~= "" and nv ~= def.name then def.name = nv; changed = true end
  y = y + 42

  -- surface type: a tag your game can read to know what this block is; picking one also sets the editor colour for it
  ui:text("type", x, y + 6, T.dim)
  local nT = #Surfaces.types
  local gap = 4
  local bw = floor((w - 56 - (nT - 1) * gap) / nT)
  for i, t in ipairs(Surfaces.types) do
    local bx = x + 56 + (i - 1) * (bw + gap)
    if ui:button(bx, y, bw, 28, t.label, { active = def.surface == t.id, hint = "Mark these blocks as " .. t.label:lower() }) then
      def.surface = t.id
      def.color = { t.color[1], t.color[2], t.color[3] }
      changed = true
    end
    ui:rect(bx + 4, y + 23, bw - 8, 3, t.color)
  end
  y = y + 44

  local chan = { { "R", { 1, 0.45, 0.45, 1 } }, { "G", { 0.5, 0.9, 0.5, 1 } }, { "B", { 0.5, 0.65, 1, 1 } } }
  for i, ch in ipairs(chan) do
    ui:text(ch[1], x, y + 3, ch[2])
    local v = ui:slider("pal_" .. ch[1], x + 24, y, w - 24 - 52, 22, def.color[i], 0, 1)
    if math.abs(v - def.color[i]) > 1e-4 then def.color[i] = v; changed = true end
    local num = string.format("%3d", floor(def.color[i] * 255 + 0.5))
    ui:text(num, x + w - ui.font:getWidth(num), y + 3, T.text)
    y = y + 30
  end
  ui:rect(x, y + 2, w, 28, def.color)
  ui:outline(x, y + 2, w, 28, T.borderHi)
  y = y + 46

  local solid = ui:checkbox(x, y, "Solid (blocks movement and hides faces behind it)", def.solid ~= false)
  if solid ~= (def.solid ~= false) then def.solid = solid; changed = true end
  y = y + 32
  if def.solid == false then
    ui:text("opacity", x, y + 3, T.dim)
    local ow = ui.font:getWidth("opacity") + 12
    local a = ui:slider("pal_alpha", x + ow, y, w - ow, 22, def.alpha or 1, 0.1, 1)
    if math.abs(a - (def.alpha or 1)) > 1e-4 then def.alpha = a; changed = true end
    y = y + 34
  end

  if ui:button(x, y, 96, 28, "Done", { primary = true }) then self:closeDialog() end
  -- only the last, unused block type can be removed (ids are positions)
  if self.cur == #self.map.palette and #self.map.palette > 1 then
    local used = false
    for _, c in pairs(self.map.chunks) do
      for _, id in pairs(c.data) do if id == self.cur then used = true; break end end
      if used then break end
    end
    if ui:button(x + w - 96, y, 96, 28, "Delete", { danger = true, disabled = used,
        hint = used and "Still used by some blocks; erase them first" or "Remove this unused block type" }) then
      table.remove(self.map.palette)
      self.cur = #self.map.palette
      self.paletteModified = true
      self:closeDialog()
    end
  end
  if changed then
    self.paletteModified = true
    self:remeshAll()
  end
end

end
