-- The in-engine editor: state, tools, input and the 3D pass. The 2D panels
-- live in panels.lua and are mixed into this class at the bottom.
local BASE = ((...) or ""):match("^(.*%.)[^.]+$") or ""
local Map = require(BASE .. "map")
local History = require(BASE .. "history")
local Camera = require(BASE .. "camera")
local Mesher = require(BASE .. "mesher")
local Walker = require(BASE .. "walker")
local Entities = require(BASE .. "entities")
local Routes = require(BASE .. "routes")
local Surfaces = require(BASE .. "surfaces")
local R = require(BASE .. "raycast")
local UI = require(BASE .. "ui")

-- folder this module lives in as a love.filesystem path: "map_editor/" (or "libs/map_editor/" ...)
local DIR = BASE:gsub("%.", "/")

local floor, max, min, cos, sin, rad = math.floor, math.max, math.min, math.cos, math.sin, math.rad

local Editor = {}
Editor.__index = Editor

Editor.TOOLS = {
  { id = "pencil", label = "Pencil", key = "1", hint = "Pencil: LMB place, RMB erase. Drag to paint across a surface." },
  { id = "box", label = "Box", key = "2", hint = "Box: drag a region. LMB fills it, RMB carves it out." },
  { id = "paint", label = "Paint", key = "3", hint = "Paint: LMB recolours blocks without changing the shape." },
  { id = "pick", label = "Pick", key = "4", hint = "Pick: click a block to use its type. (Shortcut: I)" },
  { id = "entity", label = "Entity", key = "5", hint = "Entity: LMB places the chosen type (click a placed one to move it), RMB deletes it. Shift = free placement." },
  { id = "select", label = "Select", key = "6", hint = "Select: click entities to inspect, drag to move." },
}

local MAX_BOX = 250000

-- Where g3d usually lives in a project. The first one that loads wins; pass opts.g3d / opts.g3dPath to override.
Editor.G3D_PATHS = { "g3d", "libs.g3d", "lib.g3d", "libraries.g3d", "vendor.g3d", "third_party.g3d" }

function Editor.findG3d(path)
  local tried = {}
  for _, p in ipairs(path and { path } or Editor.G3D_PATHS) do
    local ok, mod = pcall(require, p)
    if ok and type(mod) == "table" and mod.newModel then return mod, p end
    tried[#tried + 1] = p
  end
  error("map_editor: could not find g3d (tried " .. table.concat(tried, ", ")
    .. "). Pass your g3d module: Editor.new{ g3d = require 'path.to.g3d' }", 0)
end

local function snap(v, step) return floor(v / step + 0.5) * step end

local function ctrlDown() return love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui") end
local function shiftDown() return love.keyboard.isDown("lshift", "rshift") end
local function altDown() return love.keyboard.isDown("lalt", "ralt") end

---------------------------------------------------------------- setup ----

--[[ opts:
  g3d          the g3d module (default: found automatically, see Editor.G3D_PATHS)
  g3dPath      require-path of g3d, if it is somewhere unusual (alternative to passing the module)
  mapDir       folder for maps, relative to the project root (default: the "maps" folder inside this module)
  gameDir      folder your game loads finished levels from ("levels"); the Export button writes there
  onExport     function(destPath) called after a level was written to gameDir
  map          path of a map to open at start
  entityTypes  list shaped like map_editor.entities.defaults
  palette      function returning a fresh palette for NEW maps (default: Map.defaultPalette)
]]
function Editor.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Editor)
  self.g3d = opts.g3d or Editor.findG3d(opts.g3dPath)
  self.mapDir = opts.mapDir or (DIR .. "maps")
  self.gameDir = opts.gameDir or "levels"
  self.onExport = opts.onExport
  self.onLeave  = opts.onLeave     -- toolbar "Exit" button: leave the editor (state.lua asks about unsaved changes)
  self.entityTypes = opts.entityTypes or Entities.defaults
  self.newPalette = opts.palette
  self.entityIndex = Entities.index(self.entityTypes)
  self.entityType = self.entityTypes[1] and self.entityTypes[1].name
  self.cam = Camera.new()
  self.ui = UI.new()
  self.texture = Mesher.whiteTexture()
  self.models = {}
  self.tool = "pencil"
  self.cur = 1
  self.layer = 0
  self.showGrid, self.lockLayer = true, false
  self.mode = "edit"
  self.flashText, self.flashTime, self.flashBad = "", 0, false
  self.cubeCentered = self.g3d.newModel(Mesher.cubeVerts(1, 1, 1, 1, true), self.texture)
  self.cubeCorner = self.g3d.newModel(Mesher.cubeVerts(1, 1, 1, 1, false), self.texture)
  love.keyboard.setKeyRepeat(true)
  if love.keyboard.setTextInput then love.keyboard.setTextInput(true) end   -- LÖVE 12 can start with text input off
  self:setMap(Editor.starterMap(self.newPalette), nil)
  if opts.map then
    local ok, err = self:openPath(opts.map)
    if not ok then self:flash("Could not open " .. opts.map .. ": " .. tostring(err), 5, true) end
  end
  return self
end

function Editor.starterMap(newPalette)
  local m = Map.new(newPalette and { palette = newPalette() } or nil)
  local floorId = require(BASE .. "surfaces").find(m.palette, "concrete") or 1   -- the starter floor is concrete
  m:fillBox(0, 0, 0, 15, 15, 0, floorId)
  m.dirty = {}
  for k, c in pairs(m.chunks) do m.dirty[k] = { c.cx, c.cy, c.cz } end
  return m
end

function Editor:setMap(map, path)
  self.map = map
  self.hist = History.new(map)
  self.path = path
  self.savedVersion = self.hist.version
  self.paletteModified = false
  self.models = {}
  self.sel = nil
  self.drag, self.camDrag, self.hover = nil, nil, nil
  self.cur = max(1, min(self.cur, #map.palette))
  for k, c in pairs(map.chunks) do map.dirty[k] = { c.cx, c.cy, c.cz } end
  local x1, y1, z1, x2, y2, z2 = map:bounds()
  if x1 then
    self.cam:focus((x1 + x2 + 1) / 2, (y1 + y2 + 1) / 2, z1, max(14, (x2 - x1 + y2 - y1) * 0.8))
    self.layer = z2 + 1
  else
    self.cam:reset()
    self.layer = 0
  end
  self.gridKey = nil
end

function Editor:isModified()
  return self.hist.version ~= self.savedVersion or self.paletteModified
end

function Editor:flash(text, secs, bad)
  self.flashText, self.flashTime, self.flashBad = text, secs or 3, bad or false
end

function Editor:remeshAll()
  for k, c in pairs(self.map.chunks) do self.map.dirty[k] = { c.cx, c.cy, c.cz } end
end

---------------------------------------------------------------- files ----

-- A map name may include sub-folders ("mylevel/mylevel_full"): maps are packaged one folder per level.
local function sanitize(name)
  name = (name or ""):gsub("%.lua$", ""):gsub("\\", "/"):gsub("[^%w_%-%./]", "_")
  name = name:gsub("%.%.+", "_"):gsub("//+", "/"):gsub("^/", ""):gsub("/$", "")
  return name
end
Editor.sanitize = sanitize

function Editor:pathFor(name) return self.mapDir .. "/" .. sanitize(name) .. ".lua" end

-- every map under mapDir, one folder level deep: "demo", "mylevel/mylevel_full", ...
function Editor:listMaps()
  local out, seen = {}, {}
  local fs = love.filesystem
  if fs and fs.getDirectoryItems then
    local function scan(dir, prefix, depth)
      for _, f in ipairs(fs.getDirectoryItems(dir)) do
        local n = f:match("^(.*)%.lua$")
        if n and not seen[prefix .. n] then seen[prefix .. n] = true; out[#out + 1] = prefix .. n end
        local info = (not n) and fs.getInfo(dir .. "/" .. f)
        if info and info.type == "directory" and depth < 2 then scan(dir .. "/" .. f, prefix .. f .. "/", depth + 1) end
      end
    end
    scan(self.mapDir, "", 1)
  end
  table.sort(out)
  return out
end

function Editor:openPath(path)
  local m, err = Map.load(path)
  if not m then return false, err end
  self:setMap(m, path)
  self:flash("Opened " .. path)
  return true
end

function Editor:save()
  if not self.path then return self:openDialog("saveas") end
  self.map.name = self.path:match("([^/]+)%.lua$") or self.map.name
  local ok, where = self.map:save(self.path)
  if ok then
    self.savedVersion = self.hist.version
    self.paletteModified = false
    self:flash("Saved to " .. where, 4)
  else
    self:flash("Save failed: " .. tostring(where), 6, true)
  end
  return ok
end

function Editor:saveAs(name)
  name = sanitize(name)
  if name == "" then return false end
  self.path = self:pathFor(name)
  return self:save()
end

-- Export: write the finished level into your project's level folder (gameDir/NAME.lua), where your game loads it.
--   Optional packaging convention: maps/<level>/<level>_noceiling.lua (for editing, nothing blocks the camera) +
--   <level>_full.lua (the complete one). The game gets the _full version, named plainly "<level>"; if you are looking
--   at the _noceiling copy and a _full sits next to it, that one is exported (and the message says so).
--   A map without those suffixes is exported as it is.
function Editor:exportToGame()
  if not self.path then return self:flash("Save the map first (Ctrl+S), then Export writes it to the game folder", 3, true) end
  if self:isModified() then return self:flash("Unsaved changes: Ctrl+S first, then Export writes the saved map", 3, true) end
  local dir, file = self.path:match("^(.*)/([^/]+)%.lua$")
  file = file or self.path
  local base, kind = file, nil
  local b = file:match("^(.-)_noceiling$")
  if b and b ~= "" then base, kind = b, "noceiling" end
  b = file:match("^(.-)_full$")
  if b and b ~= "" then base, kind = b, "full" end

  local src, sourceName = self.map, file
  if kind == "noceiling" then
    local full = (dir and (dir .. "/") or "") .. base .. "_full.lua"
    local m = Map.load(full)
    if m then src, sourceName = m, base .. "_full"
    else self:flash("No " .. base .. "_full.lua next to it: exporting the no-ceiling map as it is", 5, true) end
  end

  local oldName = src.name
  src.name = base
  local str = src:serialize()
  src.name = oldName
  local dest = self.gameDir .. "/" .. sanitize(base) .. ".lua"
  local ok, where = Map.writeFile(dest, str)
  if not ok then return self:flash("Export failed: " .. tostring(where), 6, true) end
  self:flash("Exported " .. sourceName .. " -> " .. dest, 6)
  if self.onExport then self.onExport(dest) end
  return true
end

-- run fn now, or after the user confirms discarding unsaved changes
function Editor:guard(fn)
  if not self:isModified() then return fn() end
  self:openDialog("confirm", {
    text = "You have unsaved changes. Discard them?",
    yes = "Discard", onYes = fn,
  })
end

function Editor:newMap()
  self:guard(function()
    self:setMap(Editor.starterMap(self.newPalette), nil)
    self:flash("New map")
  end)
end

function Editor:openDialog(kind, data)
  self:finishDrag()
  self.dialog = data or {}
  self.dialog.kind = kind
  if kind == "open" then
    self.dialog.files = self:listMaps()
    self.dialog.sel = 1
  elseif kind == "saveas" then
    -- default: the current file's name relative to mapDir, so Save As stays inside the level's folder
    local rel = self.path and self.path:gsub("%.lua$", "")
    if rel and rel:sub(1, #self.mapDir + 1) == self.mapDir .. "/" then rel = rel:sub(#self.mapDir + 2) end
    self.dialog.name = rel or "my_level"
  end
end

function Editor:closeDialog()
  self.dialog = nil
  self.ui.focus = nil
end

------------------------------------------------------------- history ----

function Editor:undo()
  if self.drag then return end
  if self.hist:undo() then self:flash("Undo", 0.8) end
  self:fixSelection()
end

function Editor:redo()
  if self.drag then return end
  if self.hist:redo() then self:flash("Redo", 0.8) end
  self:fixSelection()
end

function Editor:fixSelection()
  if self.sel then
    for _, e in ipairs(self.map.entities) do if e == self.sel then return end end
    self.sel = nil
  end
end

-- change an entity field/prop as one undo step (inspector uses these)
function Editor:setField(e, key, value)
  self.hist:run(function() self.map:setEntityField(e, key, value) end)
end

function Editor:setProp(e, key, value)
  self.hist:run(function() self.map:setEntityProp(e, key, value) end)
end

function Editor:deleteSelected()
  local e = self.sel
  if not e then return end
  self.hist:run(function() self.map:removeEntity(e) end)
  self.sel = nil
end

function Editor:duplicateSelected()
  local e = self.sel
  if not e then return end
  local copy = { type = e.type, name = e.name, x = e.x + 1, y = e.y, z = e.z, yaw = e.yaw, props = {} }
  for k, v in pairs(e.props) do copy.props[k] = v end
  self.hist:run(function() self.map:addEntity(copy) end)
  self.sel = copy
end

function Editor:rotateSelected(deg)
  local e = self.sel
  if e then self:setField(e, "yaw", (e.yaw + deg) % 360) end
end

-------------------------------------------------------------- picking ----

function Editor:pickEntity(ox, oy, oz, dx, dy, dz)
  local best, bt
  for _, e in ipairs(self.map.entities) do
    local w, d, h = Entities.size(self.entityIndex[e.type], e)
    local t = R.aabb(ox, oy, oz, dx, dy, dz, e.x - w / 2, e.y - d / 2, e.z, e.x + w / 2, e.y + d / 2, e.z + h)
    if t and (not bt or t < bt) then best, bt = e, t end
  end
  return best, bt
end

-- cells on either side of a point lying on a voxel face
local function cellsFromPoint(p, face)
  local q = { p[1], p[2], p[3] }
  q[face.axis] = face.coord
  local n = { 0, 0, 0 }
  n[face.axis] = face.sign
  local e = 0.001
  return { floor(q[1] + n[1] * e), floor(q[2] + n[2] * e), floor(q[3] + n[3] * e) },
         { floor(q[1] - n[1] * e), floor(q[2] - n[2] * e), floor(q[3] - n[3] * e) }
end

function Editor:computeHover(mx, my)
  local W, H = love.graphics.getDimensions()
  local ox, oy, oz, dx, dy, dz = self.cam:ray(mx, my, W, H)
  local hv = { ray = { ox, oy, oz, dx, dy, dz } }
  if self.tool == "select" or self.tool == "entity" then hv.ent = self:pickEntity(ox, oy, oz, dx, dy, dz) end

  local bx, by, bz, nx, ny, nz, t
  if not self.lockLayer then
    bx, by, bz, nx, ny, nz, t = self.map:raycast(ox, oy, oz, dx, dy, dz, 600)
  end
  if bx and t > 0 then
    local axis = nx ~= 0 and 1 or (ny ~= 0 and 2 or 3)
    local sign = nx + ny + nz
    local coord = (axis == 1 and bx or axis == 2 and by or bz) + (sign > 0 and 1 or 0)
    hv.kind = "block"
    hv.p = { ox + dx * t, oy + dy * t, oz + dz * t }
    hv.face = { axis = axis, sign = sign, coord = coord }
  else
    local planeZ = self.lockLayer and (self.layer + 0.5) or self.layer
    local pt, wx, wy, wz = R.plane(ox, oy, oz, dx, dy, dz, 3, planeZ)
    if pt and pt < 900 then
      hv.kind = "plane"
      hv.p = { wx, wy, wz }
      hv.face = { axis = 3, sign = 1, coord = planeZ }
    end
  end
  if hv.kind then hv.place, hv.target = cellsFromPoint(hv.p, hv.face) end
  return hv
end

-- point where the current mouse ray crosses the face plane a drag started on
function Editor:dragCells(face)
  local mx, my = love.mouse.getPosition()
  local W, H = love.graphics.getDimensions()
  local ox, oy, oz, dx, dy, dz = self.cam:ray(mx, my, W, H)
  local t, px, py, pz = R.plane(ox, oy, oz, dx, dy, dz, face.axis, face.coord)
  if not t or t > 2000 then return nil end
  local p = { px, py, pz }
  local place, target = cellsFromPoint(p, face)
  return place, target, p
end

--------------------------------------------------------------- actions ----

local function key3(c) return c[1] .. "," .. c[2] .. "," .. c[3] end

function Editor:paintCell(c)
  local id = self.map:get(c[1], c[2], c[3])
  if id ~= 0 and id ~= self.cur then self.map:set(c[1], c[2], c[3], self.cur) end
end

function Editor:pickCell(c)
  local id = self.map:get(c[1], c[2], c[3])
  if id ~= 0 then
    self.cur = id
    self:flash("Picked " .. (self.map.palette[id] and self.map.palette[id].name or id), 1.2)
  end
end

function Editor:placeEntity(hv)
  local def = self.entityIndex[self.entityType]
  if not (def and hv.kind) then return end
  local x, y, z
  if shiftDown() then
    x, y, z = snap(hv.p[1], 0.25), snap(hv.p[2], 0.25), snap(hv.p[3], 0.25)
  else
    x, y, z = hv.place[1] + 0.5, hv.place[2] + 0.5, hv.place[3]
  end
  local e
  self.hist:run(function()
    local existing = def.unique and self.map:firstEntity(def.name)
    if existing then
      self.map:setEntityField(existing, "x", x)
      self.map:setEntityField(existing, "y", y)
      self.map:setEntityField(existing, "z", z)
      e = existing
    else
      e = self.map:addEntity({ type = def.name, x = x, y = y, z = z, yaw = 0, props = Entities.newProps(def) })
    end
  end)
  self.sel = e
end

function Editor:finishDrag()
  local d = self.drag
  if not d then return end
  self.drag = nil
  if d.kind == "box" then
    if d.a and d.b then
      local dx = math.abs(d.a[1] - d.b[1]) + 1
      local dy = math.abs(d.a[2] - d.b[2]) + 1
      local dz = math.abs(d.a[3] - d.b[3]) + 1
      if dx * dy * dz > MAX_BOX then
        self:flash(("Box too large (%d cells, limit %d)"):format(dx * dy * dz, MAX_BOX), 4, true)
      else
        self.hist:begin()
        self.map:fillBox(d.a[1], d.a[2], d.a[3], d.b[1], d.b[2], d.b[3], d.button == 1 and self.cur or 0)
        self.hist:commit()
      end
    end
  else
    self.hist:commit()
  end
end

function Editor:updateDrag()
  local d = self.drag
  if d.kind == "move" then
    local e = d.ent
    local mx, my = love.mouse.getPosition()
    local W, H = love.graphics.getDimensions()
    local ox, oy, oz, dx, dy, dz = self.cam:ray(mx, my, W, H)
    local t, px, py = R.plane(ox, oy, oz, dx, dy, dz, 3, d.z)
    if t then
      local step = shiftDown() and 0.25 or 0.5
      local nx, ny = snap(px - d.offx, step), snap(py - d.offy, step)
      if nx ~= e.x then self.map:setEntityField(e, "x", nx) end
      if ny ~= e.y then self.map:setEntityField(e, "y", ny) end
    end
    return
  end

  local place, target = self:dragCells(d.face)
  if not place then return end
  local cell = (d.button == 1) and place or target
  if d.kind == "pencil" then
    local k = key3(cell)
    if k ~= d.last then
      d.last = k
      self.map:set(cell[1], cell[2], cell[3], d.button == 1 and self.cur or 0)
    end
  elseif d.kind == "paint" then
    local k = key3(target)
    if k ~= d.last then d.last = k; self:paintCell(target) end
  elseif d.kind == "box" then
    d.b = cell
  end
end

function Editor:mousepressed(x, y, button)
  self.ui:onPress(x, y, button) -- also lets a focused text field commit on click-away
  if self.dialog or self.ui:over(x, y) then return end
  if self.mode == "play" then return end

  -- camera drags: MMB, or Alt+LMB (Shift to pan)
  if button == 3 or (button == 1 and altDown()) then
    self.camDrag = { button = button, pan = shiftDown() or ctrlDown() }
    return
  end

  local hv = self:computeHover(x, y)
  self.hover = hv
  local tool = self.tool

  if tool == "pencil" and (button == 1 or button == 2) and hv.kind then
    self.hist:begin()
    self.drag = { kind = "pencil", button = button, face = hv.face }
    local cell = button == 1 and hv.place or hv.target
    self.drag.last = key3(cell)
    self.map:set(cell[1], cell[2], cell[3], button == 1 and self.cur or 0)
  elseif tool == "box" and (button == 1 or button == 2) and hv.kind then
    local cell = button == 1 and hv.place or hv.target
    self.drag = { kind = "box", button = button, face = hv.face, a = cell, b = cell }
  elseif tool == "paint" and button == 1 and hv.kind then
    self.hist:begin()
    self.drag = { kind = "paint", button = 1, face = hv.face, last = key3(hv.target) }
    self:paintCell(hv.target)
  elseif tool == "pick" and button == 1 and hv.kind then
    self:pickCell(hv.target)
  elseif tool == "entity" and button == 2 and hv.ent then
    -- right-click a placed entity (any character, light, ...) removes it
    self.sel = hv.ent
    self:deleteSelected()
  elseif tool == "entity" and button == 1 and hv.ent and not shiftDown() then
    -- left-click on an existing entity selects it and lets you drag it, instead of stacking another one on top
    self:startEntityMove(hv)
  elseif tool == "entity" and button == 1 then
    self:placeEntity(hv)
  elseif tool == "select" and button == 1 then
    self.sel = hv.ent
    if hv.ent then self:startEntityMove(hv) end
  end
end

function Editor:startEntityMove(hv)
  local e = hv.ent
  self.sel = e
  local t, hx, hy = R.plane(hv.ray[1], hv.ray[2], hv.ray[3], hv.ray[4], hv.ray[5], hv.ray[6], 3, e.z)
  self.hist:begin()
  self.drag = { kind = "move", button = 1, ent = e, z = e.z,
    offx = t and (hx - e.x) or 0, offy = t and (hy - e.y) or 0 }
end

function Editor:mousereleased(x, y, button)
  if self.camDrag and self.camDrag.button == button then self.camDrag = nil end
  if self.drag and self.drag.button == button then self:finishDrag() end
end

function Editor:mousemoved(x, y, dx, dy)
  if self.mode == "play" then
    local s = self.cam.invertRight and -1 or 1
    self.walker:look(dx * s, dy)
    return
  end
  local cd = self.camDrag
  if cd then
    if cd.pan then
      local _, H = love.graphics.getDimensions()
      self.cam:pan(dx * (self.cam.invertRight and -1 or 1), dy, H)
    else
      self.cam:orbit(dx * (self.cam.invertRight and -1 or 1), dy)
    end
  end
end

function Editor:wheelmoved(dx, dy)
  self.ui:onWheel(dy)
  if self.dialog or self.mode == "play" then return end
  local mx, my = love.mouse.getPosition()
  if self.ui:over(mx, my) then return end
  if ctrlDown() then
    local n = #self.map.palette
    self.cur = ((self.cur - 1 - (dy > 0 and 1 or -1)) % n) + 1
  elseif shiftDown() then
    self.layer = self.layer + (dy > 0 and 1 or -1)
  else
    self.cam:zoom(dy)
  end
end

function Editor:setTool(id)
  if self.tool ~= id then self:finishDrag() end
  self.tool = id
end

function Editor:keypressed(key, scancode, isrepeat)
  if self.ui:keypressed(key) then return end

  if self.dialog then
    if key == "escape" then self:closeDialog() end
    if self.dialog and self.dialog.kind == "open" and (key == "return" or key == "kpenter") then
      local f = self.dialog.files[self.dialog.sel]
      if f then self:closeDialog(); self:guard(function() self:openPath(self:pathFor(f)) end) end
    end
    return
  end

  if self.mode == "play" then
    if (key == "escape" or key == "f5") and not isrepeat then self:stopPlay() end
    return
  end

  if key == "f10" and not isrepeat and self.onLeave then self.onLeave(); return end

  local ctrl, shift = ctrlDown(), shiftDown()
  if ctrl then
    if key == "z" then if shift then self:redo() else self:undo() end
    elseif key == "y" then self:redo()
    elseif isrepeat then return
    elseif key == "s" then if shift then self:openDialog("saveas") else self:save() end
    elseif key == "o" then self:openDialog("open")
    elseif key == "n" then self:newMap()
    elseif key == "g" then self:exportToGame()
    elseif key == "d" then self:duplicateSelected()
    end
    return
  end

  if key == "q" or key == "pagedown" or key == "[" then self.layer = self.layer - 1
  elseif key == "e" or key == "pageup" or key == "]" then self.layer = self.layer + 1
  elseif isrepeat then return
  elseif key == "," then self.cur = (self.cur - 2) % #self.map.palette + 1
  elseif key == "." then self.cur = self.cur % #self.map.palette + 1
  elseif key == "i" and self.hover and self.hover.kind then self:pickCell(self.hover.target)
  elseif key == "g" then self.showGrid = not self.showGrid
  elseif key == "l" then self.lockLayer = not self.lockLayer
  elseif key == "t" then self.cam:topDown()
  elseif key == "v" then self.cam:sideView()
  elseif key == "z" then self.cam:turn(-1)
  elseif key == "c" then self.cam:turn(1)
  elseif key == "f" then self:focusView()
  elseif key == "home" then self.cam:reset()
  elseif key == "r" then self:rotateSelected(shift and -90 or 90)
  elseif key == "delete" or key == "x" or key == "backspace" then self:deleteSelected()
  elseif key == "f1" then self:openDialog("help")
  elseif key == "f5" then self:startPlay()
  elseif key == "f9" then
    self.cam.invertRight = not self.cam.invertRight
    self:flash("Mirror fix " .. (self.cam.invertRight and "ON" or "OFF") .. " (F9)", 2)
  elseif key == "escape" then
    if self.sel then self.sel = nil end
  else
    for _, t in ipairs(Editor.TOOLS) do
      if key == t.key then self:setTool(t.id) end
    end
  end
end

function Editor:textinput(t) self.ui:textinput(t) end
function Editor:keyreleased() end
function Editor:resize() self.gridKey = nil end

function Editor:focusView()
  if self.sel then
    self.cam:focus(self.sel.x, self.sel.y, self.sel.z)
    return
  end
  local x1, y1, z1, x2, y2, z2 = self.map:bounds()
  if x1 then
    self.cam:focus((x1 + x2 + 1) / 2, (y1 + y2 + 1) / 2, (z1 + z2 + 1) / 2,
      max(14, (x2 - x1 + y2 - y1) * 0.8))
  else
    self.cam:reset()
  end
end

--------------------------------------------------------------- play-test ---

function Editor:startPlay()
  self:finishDrag()
  local s = self.map:firstEntity("player_start")
  local x, y, z, yaw
  if s then x, y, z, yaw = s.x, s.y, s.z + 0.01, rad(s.yaw)
  else x, y, z, yaw = self.cam.tx, self.cam.ty, self.cam.tz + 30, 0 end
  self.walker = Walker.new(x, y, z, { yaw = yaw })
  self.walker.start = { x, y, z }
  self.mode = "play"
  love.mouse.setRelativeMode(true)
  self:flash(s and "Play-test (Esc to return)" or "Play-test: no player_start, dropping in from above", 3)
end

function Editor:stopPlay()
  self.mode = "edit"
  love.mouse.setRelativeMode(false)
end

function Editor:updatePlay(dt)
  local w = self.walker
  local kd = love.keyboard.isDown
  local sgn = self.cam.invertRight and -1 or 1
  w:update(self.map, dt, {
    forward = (kd("w", "up") and 1 or 0) - (kd("s", "down") and 1 or 0),
    strafe = ((kd("d", "right") and 1 or 0) - (kd("a", "left") and 1 or 0)) * sgn,
    jump = kd("space"), run = kd("lshift", "rshift"),
  })
  if w.z < -300 then
    w.x, w.y, w.z, w.vz = w.start[1], w.start[2], w.start[3], 0
  end
end

--------------------------------------------------------------- update ----

function Editor:update(dt)
  self.ui.time = self.ui.time + dt
  if self.flashTime > 0 then self.flashTime = self.flashTime - dt end

  if self.mode == "play" then
    self:updatePlay(dt)
  else
    local mx, my = love.mouse.getPosition()
    local kd = love.keyboard.isDown
    if not self.ui.focus and not self.dialog and not ctrlDown() then
      local f = (kd("w", "up") and 1 or 0) - (kd("s", "down") and 1 or 0)
      local s = (kd("d", "right") and 1 or 0) - (kd("a", "left") and 1 or 0)
      if f ~= 0 or s ~= 0 then
        self.cam:move(f, s, 0, dt * (shiftDown() and 2.5 or 1))
      end
    end

    if self.drag and not love.mouse.isDown(self.drag.button) then self:finishDrag() end
    if self.camDrag and not love.mouse.isDown(self.camDrag.button) then self.camDrag = nil end

    if self.drag then
      self:updateDrag()
    elseif self.dialog or self.camDrag or self.ui:over(mx, my) then
      self.hover = nil
    else
      self.hover = self:computeHover(mx, my)
    end
    Mesher.update(self.map, self.models, self.g3d, self.texture, 64)
  end

  local title = "g3d map editor - " .. (self.path or "untitled") .. (self:isModified() and " *" or "")
  if title ~= self.title then
    self.title = title
    love.window.setTitle(title)
  end
end

----------------------------------------------------------------- draw ------

local function drawCube(model, r, g, b, a, x, y, z, sx, sy, sz, yaw)
  love.graphics.setColor(r, g, b, a)
  model:setTransform({ x, y, z }, { 0, 0, yaw or 0 }, { sx, sy, sz })
  model:draw()
end

function Editor:rebuildGrid()
  local N = 32
  local cx, cy = floor(self.cam.tx / 8) * 8, floor(self.cam.ty / 8) * 8
  local z = self.layer + 0.01
  local key = cx .. "," .. cy .. "," .. self.layer .. (self.lockLayer and "L" or "")
  if key == self.gridKey then return end
  self.gridKey = key
  local verts = {}
  local function quad(x1, y1, x2, y2, r, g, b, a)
    local function v(x, y) return { x, y, z, 0, 0, 0, 0, 1, r, g, b, a } end
    local A, B, C, D = v(x1, y1), v(x2, y1), v(x2, y2), v(x1, y2)
    for _, p in ipairs({ A, B, C, A, C, D }) do verts[#verts + 1] = p end
  end
  local tint = self.lockLayer and { 0.45, 0.75, 1 } or { 1, 1, 1 }
  for i = -N, N do
    local gx, gy = cx + i, cy + i
    local major = (gx % 8 == 0)
    local w = major and 0.05 or 0.025
    local a = major and 0.38 or 0.17
    local r, g, b = tint[1], tint[2], tint[3]
    local r2, g2, b2, a2, w2 = r, g, b, a, w
    if gx == 0 then g, r, b, a, w = 1, 0.35, 0.35, 0.95, 0.08 end   -- the Y axis (line at x = 0)
    quad(gx - w / 2, cy - N, gx + w / 2, cy + N, r, g, b, a)
    if gy == 0 then r2, g2, b2, a2, w2 = 1, 0.3, 0.3, 0.95, 0.08 end -- the X axis (line at y = 0)
    quad(cx - N, gy - w2 / 2, cx + N, gy + w2 / 2, r2, g2, b2, a2)
  end
  self.gridModel = self.g3d.newModel(verts, self.texture)
end

function Editor:draw3D(W, H)
  local g = love.graphics
  local s = self.map.sky
  g.clear(s[1], s[2], s[3], 1, true, true)
  g.setColor(1, 1, 1, 1)

  if self.mode == "play" then
    local w = self.walker
    local ex, ey, ez = w:eyePosition()
    local lx, ly, lz = w:lookVector()
    self.cam:apply(self.g3d, W, H, ex, ey, ez, ex + lx, ey + ly, ez + lz)
  else
    self.cam:apply(self.g3d, W, H)
  end

  g.setDepthMode("lequal", true)
  for _, m in pairs(self.models) do m:draw() end

  -- entities (always visible in the editor, hidden when play-testing)
  if self.mode == "edit" then
    for _, e in ipairs(self.map.entities) do
      local def = self.entityIndex[e.type] or { color = { 1, 0, 1 } }
      local c = def.color
      local w, d, h = Entities.size(def, e)
      local yaw = rad(e.yaw or 0)
      drawCube(self.cubeCentered, c[1], c[2], c[3], 0.9, e.x, e.y, e.z, w, d, h, yaw)
      -- a small "nose" shows which way the entity faces (yaw 0 = +x)
      local nd = w / 2 + 0.12
      drawCube(self.cubeCentered, c[1] * 0.4, c[2] * 0.4, c[3] * 0.4, 1,
        e.x + cos(yaw) * nd, e.y + sin(yaw) * nd, e.z + h * 0.5 - 0.15, 0.3, 0.3, 0.3, yaw)
    end
  end

  g.setDepthMode("lequal", false)
  if self.mode == "edit" then
    if self.showGrid then
      self:rebuildGrid()
      g.setColor(1, 1, 1, 1)
      self.gridModel:draw()
    end
    self:drawCursor()
  end
  g.setColor(1, 1, 1, 1)
  g.setDepthMode("always", false)
end

function Editor:drawCursor()
  local sel = self.sel
  if sel then
    local w, d, h = Entities.size(self.entityIndex[sel.type], sel)
    drawCube(self.cubeCentered, 1, 1, 1, 0.3, sel.x, sel.y, sel.z - 0.03, w + 0.08, d + 0.08, h + 0.06, rad(sel.yaw or 0))
  end

  local d = self.drag
  if d and d.kind == "box" and d.a and d.b then
    local x1, x2 = min(d.a[1], d.b[1]), max(d.a[1], d.b[1])
    local y1, y2 = min(d.a[2], d.b[2]), max(d.a[2], d.b[2])
    local z1, z2 = min(d.a[3], d.b[3]), max(d.a[3], d.b[3])
    local c = d.button == 1 and self:blockColor() or { 1, 0.25, 0.25 }
    drawCube(self.cubeCorner, c[1], c[2], c[3], 0.45, x1 - 0.005, y1 - 0.005, z1 - 0.005,
      x2 - x1 + 1.01, y2 - y1 + 1.01, z2 - z1 + 1.01)
    return
  end

  local hv = self.hover
  if not (hv and hv.kind) then return end
  local tool = self.tool
  if tool == "pencil" or tool == "box" then
    local p = hv.place
    local c = self:blockColor()
    drawCube(self.cubeCorner, c[1], c[2], c[3], 0.5, p[1] - 0.005, p[2] - 0.005, p[3] - 0.005, 1.01, 1.01, 1.01)
    if hv.kind == "block" then
      local t = hv.target
      drawCube(self.cubeCorner, 1, 0.3, 0.3, 0.18, t[1] - 0.01, t[2] - 0.01, t[3] - 0.01, 1.02, 1.02, 1.02)
    end
  elseif tool == "paint" or tool == "pick" then
    if hv.kind == "block" then
      local t = hv.target
      local c = tool == "paint" and self:blockColor() or { 1, 1, 1 }
      drawCube(self.cubeCorner, c[1], c[2], c[3], 0.5, t[1] - 0.01, t[2] - 0.01, t[3] - 0.01, 1.02, 1.02, 1.02)
    end
  elseif tool == "entity" then
    local def = self.entityIndex[self.entityType]
    if def then
      local x, y, z
      if shiftDown() then x, y, z = snap(hv.p[1], 0.25), snap(hv.p[2], 0.25), snap(hv.p[3], 0.25)
      else x, y, z = hv.place[1] + 0.5, hv.place[2] + 0.5, hv.place[3] end
      local w, dd, h = Entities.size(def, { props = Entities.newProps(def) })
      local c = def.color
      drawCube(self.cubeCentered, c[1], c[2], c[3], 0.45, x, y, z, w, dd, h)
    end
  elseif tool == "select" and hv.ent then
    local e = hv.ent
    local w, dd, h = Entities.size(self.entityIndex[e.type], e)
    drawCube(self.cubeCentered, 1, 1, 1, 0.2, e.x, e.y, e.z - 0.02, w + 0.06, dd + 0.06, h + 0.04, rad(e.yaw or 0))
  end
end

-- Routes, drawn as a 2D overlay on top of the 3D view (so they show through walls):
--   solid line + arrow   waypoint -> next waypoint, in `order`
--   faint line           last waypoint -> first (the route loops)
--   dashed line          a route follower -> the first waypoint of its route (where it heads first)
--   red "no waypoints"   an entity whose `route` matches no waypoint (it would not move)
-- The route of the selected entity is drawn thicker.
function Editor:drawRoutes(W, H)
  if self.mode ~= "edit" then return end
  local routes = Routes.collect(self.map.entities)
  local g, cam = love.graphics, self.cam
  local font = self.ui.small
  local prevFont = g.getFont and g.getFont()
  if font then g.setFont(font) end
  local selKey = self.sel and Routes.key(self.sel.props and self.sel.props.route)

  local function pt(x, y, z)
    local sx, sy = cam:project(x, y, z, W, H)
    return sx, sy
  end
  local function seg(a, b, width, alpha, r, gg, bb, arrow)
    local ax, ay = pt(a.x, a.y, a.z + 0.25)
    local bx, by = pt(b.x, b.y, b.z + 0.25)
    if not (ax and bx) then return end
    g.setColor(r, gg, bb, alpha)
    g.setLineWidth(width)
    g.line(ax, ay, bx, by)
    if arrow then
      local dx, dy = bx - ax, by - ay
      local len = math.sqrt(dx * dx + dy * dy)
      if len > 24 then
        dx, dy = dx / len, dy / len
        local mx, my = ax + (bx - ax) * 0.6, ay + (by - ay) * 0.6
        g.polygon("fill", mx + dx * 6, my + dy * 6, mx - dx * 5 - dy * 4, my - dy * 5 + dx * 4, mx - dx * 5 + dy * 4, my - dy * 5 - dx * 4)
      end
    end
  end
  local function dashed(a, b, width, alpha, r, gg, bb)
    local ax, ay = pt(a.x, a.y, a.z + 0.25)
    local bx, by = pt(b.x, b.y, b.z + 0.25)
    if not (ax and bx) then return end
    g.setColor(r, gg, bb, alpha)
    g.setLineWidth(width)
    local dx, dy = bx - ax, by - ay
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    dx, dy = dx / len, dy / len
    local t = 0
    while t < len do
      local t2 = math.min(t + 6, len)
      g.line(ax + dx * t, ay + dy * t, ax + dx * t2, ay + dy * t2)
      t = t + 12
    end
  end

  for key, r in pairs(routes) do
    local cr, cg, cb = Routes.color(key)
    local on = key == selKey
    local width, alpha = on and 3 or 2, on and 1 or 0.75
    local n = #r.points
    for i = 1, n - 1 do seg(r.points[i], r.points[i + 1], width, alpha, cr, cg, cb, true) end
    if n > 2 then seg(r.points[n], r.points[1], width, alpha * 0.35, cr, cg, cb, false) end
    for i, p in ipairs(r.points) do
      local sx, sy = pt(p.x, p.y, p.z + 0.25)
      if sx then
        g.setColor(0, 0, 0, 0.7)
        g.print(i == 1 and (r.name .. " 1") or tostring(i), sx + 7, sy - 7 + 1)
        g.setColor(cr, cg, cb, 1)
        g.print(i == 1 and (r.name .. " 1") or tostring(i), sx + 6, sy - 7)
      end
    end
  end

  for _, e in ipairs(self.map.entities) do
    if e.type ~= "waypoint" then
      local key = Routes.key(e.props and e.props.route)
      if key then
        local r = routes[key]
        local from = { x = e.x, y = e.y, z = e.z + 0.75 - 0.25 }
        if r then
          local cr, cg, cb = Routes.color(key)
          dashed(from, r.points[1], key == selKey and 3 or 2, 0.9, cr, cg, cb)
        else
          local sx, sy = pt(e.x, e.y, e.z + 2.1)
          if sx then
            g.setColor(1, 0.3, 0.3, 1)
            g.print("route '" .. tostring(e.props.route) .. "': no waypoints", sx - 40, sy)
          end
        end
      end
    end
  end

  g.setLineWidth(1)
  g.setColor(1, 1, 1, 1)
  if prevFont then g.setFont(prevFont) end
end

function Editor:blockColor()
  local def = self.map.palette[self.cur]
  return def and def.color or { 1, 1, 1 }
end

function Editor:draw()
  local W, H = love.graphics.getDimensions()
  self:draw3D(W, H)
  self:drawRoutes(W, H)
  self.ui:begin()
  self:drawPanels(W, H) -- panels.lua
  self.ui:finish()
end

-- panels.lua adds drawPanels and the dialogs
require(BASE .. "panels")(Editor)

return Editor
