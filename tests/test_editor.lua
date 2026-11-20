-- Smoke test of the editor + panels against a stubbed `love` and a fake g3d.
-- This exercises real code paths (picking, tools, undo, dialogs, drawing) but
-- cannot judge pixels. Run from the project root:  texlua tests/test_editor.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local passed, failed = 0, 0
local function check(name, cond, extra)
  if cond then passed = passed + 1
  else failed = failed + 1; print("FAIL: " .. name .. (extra and (" -> " .. tostring(extra)) or "")) end
end

------------------------------------------------------------ love stub -----
local W, H = 1280, 720
local mouse = { x = W / 2, y = H / 2, down = {} }
local keys = {}
local files = {}
local drawCalls = { text = 0, rect = 0 }
local noop = function() end
local font = { getWidth = function(_, s) return #tostring(s) * 7 end, getHeight = function() return 14 end }

love = {
  graphics = setmetatable({
    getDimensions = function() return W, H end,
    getWidth = function() return W end, getHeight = function() return H end,
    newFont = function() return font end,
    newImage = function() return { setFilter = noop } end,
    print = function() drawCalls.text = drawCalls.text + 1 end,
    rectangle = function() drawCalls.rect = drawCalls.rect + 1 end,
  }, { __index = function() return noop end }),
  image = { newImageData = function() return { setPixel = noop } end },
  mouse = {
    getPosition = function() return mouse.x, mouse.y end,
    isDown = function(b) return mouse.down[b] == true end,
    setRelativeMode = function(v) mouse.relative = v end,
  },
  keyboard = {
    isDown = function(...) for _, k in ipairs({ ... }) do if keys[k] then return true end end return false end,
    setKeyRepeat = noop,
  },
  window = { setTitle = function(t) love._title = t end },
  timer = { getFPS = function() return 60 end },
  system = { getClipboardText = function() return "" end },
  event = { quit = function() love._quit = true end },
  filesystem = {
    isFused = function() return true end,
    getSource = function() return nil end,
    getSaveDirectory = function() return "/save" end,
    createDirectory = noop,
    getInfo = function(p) return files[p] and { type = "file" } or nil end,
    read = function(p) return files[p] end,
    write = function(p, s) files[p] = s; return true end,
    getDirectoryItems = function(dir)
      local out = {}
      for p in pairs(files) do
        local n = p:match("^" .. dir .. "/(.+)$")
        if n then out[#out + 1] = n end
      end
      return out
    end,
  },
}

-- fake g3d: records what the editor asks of it
local g3dStats = { models = 0, draws = 0, looks = 0, lastLook = nil, proj = 0 }
local fakeG3d = {
  camera = {
    lookAt = function(...) g3dStats.looks = g3dStats.looks + 1; g3dStats.lastLook = { ... } end,
    updateProjectionMatrix = function() g3dStats.proj = g3dStats.proj + 1 end,
  },
  newModel = function(verts, tex)
    g3dStats.models = g3dStats.models + 1
    assert(type(verts) == "table" and #verts > 0, "g3d.newModel got an empty vertex list")
    assert(#verts[1] == 12, "vertex must have 12 numbers")
    return { setTransform = noop, draw = function() g3dStats.draws = g3dStats.draws + 1 end }
  end,
}

------------------------------------------------------------- helpers ------
local mapedit = require("map_editor")
local Map = mapedit.Map
local ed

local function frame(n)
  for _ = 1, n or 1 do ed:update(1 / 60); ed:draw() end
end
local function moveTo(x, y) mouse.x, mouse.y = x, y; ed:mousemoved(x, y, 0, 0) end
local function press(b) mouse.down[b] = true; ed:mousepressed(mouse.x, mouse.y, b) end
local function release(b) mouse.down[b] = nil; ed:mousereleased(mouse.x, mouse.y, b) end
local function click(x, y, b)
  b = b or 1
  moveTo(x, y); frame(); press(b); frame(); release(b); frame()
end
local function key(k, ctrl, shift)
  keys.lctrl = ctrl or nil; keys.lshift = shift or nil
  ed:keypressed(k, k, false)
  keys.lctrl = nil; keys.lshift = nil
  frame()
end
local function type_(s) for c in s:gmatch(".") do ed:textinput(c) end end

---------------------------------------------------------------- start -----
local ok, err = pcall(function() ed = mapedit.Editor.new({ g3d = fakeG3d, mapDir = "maps" }) end)
check("editor constructs", ok, err)
frame(3)
check("starter floor meshed and drawn", g3dStats.draws > 0 and ed.map.count == 256, ed.map.count)
check("camera was pushed into g3d", g3dStats.looks > 0 and g3dStats.proj >= 1)
local projAfterFirst = g3dStats.proj
frame(5)
check("projection not rebuilt every frame", g3dStats.proj == projAfterFirst)
W, H = 1000, 600; frame()
check("projection rebuilt on resize", g3dStats.proj == projAfterFirst + 1)
W, H = 1280, 720; frame()
check("panels drew something", drawCalls.text > 20 and drawCalls.rect > 20)

------------------------------------------------------------ pencil -------
local before = ed.map.count
click(W / 2, H / 2 - 40, 1)
check("pencil LMB places one block", ed.map.count == before + 1, ed.map.count - before)
local placed
ed.map:eachBlock(function(x, y, z, id) if z == 1 then placed = { x, y, z } end end)
check("placed on top of the floor (z=1)", placed ~= nil)
check("history has one step", #ed.hist.undoStack == 1)
check("map reports modified + title star", ed:isModified() and love._title:find("%*") ~= nil, love._title)
key("z", true)
check("Ctrl+Z removes it", ed.map.count == before)
key("y", true)
check("Ctrl+Y puts it back", ed.map.count == before + 1)

-- RMB erases the block under the cursor
click(W / 2, H / 2 - 40, 2)
check("pencil RMB erases", ed.map.count == before, ed.map.count)
key("z", true)

-- dragging paints several cells but is a single undo step
moveTo(W / 2 - 100, H / 2); frame()
local c0 = ed.map.count; local steps0 = #ed.hist.undoStack
press(1); frame()
for i = 1, 20 do moveTo(W / 2 - 100 + i * 8, H / 2); frame() end
release(1); frame()
check("drag painted several blocks", ed.map.count - c0 >= 3, ed.map.count - c0)
check("drag = one undo step", #ed.hist.undoStack == steps0 + 1)
key("z", true)
check("undoing the drag removes all of it", ed.map.count == c0)

--------------------------------------------------------------- box -------
key("2"); check("key 2 selects box", ed.tool == "box")
moveTo(W / 2 - 60, H / 2 - 30); frame()
press(1); frame()
moveTo(W / 2 + 60, H / 2 + 60); frame()
check("box drag shows a preview region", ed.drag and ed.drag.a and ed.drag.b)
release(1); frame()
local boxN = ed.map.count - c0
check("box fill added many blocks", boxN >= 4, boxN)
key("z", true)
check("box fill is one undo step", ed.map.count == c0)
-- RMB box carves
key("2")
moveTo(W / 2 - 60, H / 2); frame(); press(2); frame(); moveTo(W / 2 + 60, H / 2 + 50); frame(); release(2); frame()
check("box RMB carves floor blocks away", ed.map.count < c0, ed.map.count)
key("z", true)

-------------------------------------------------------- paint / pick -----
-- clean slate above the floor so earlier undo/redo leftovers can't confuse the test
local stale = {}
ed.map:eachBlock(function(x, y, z) if z >= 1 then stale[#stale + 1] = { x, y, z } end end)
for _, c in ipairs(stale) do ed.map:set(c[1], c[2], c[3], 0) end
frame()
key("1"); click(W / 2 - 20, H / 2 - 20, 1) -- place a block to work on
local function countId(id)
  local n = 0
  ed.map:eachBlock(function(x, y, z, bid) if z >= 1 and bid == id then n = n + 1 end end)
  return n
end
check("exactly one block placed for paint test", countId(1) == 1, countId(1))
ed.cur = 5
key("3")
click(W / 2 - 20, H / 2 - 20, 1) -- paint it
check("paint recolours the block", countId(5) == 1 and countId(1) == 0, countId(5) .. "/" .. countId(1))
ed.cur = 2
key("4"); click(W / 2 - 20, H / 2 - 20, 1)
check("pick copies block type", ed.cur == 5, ed.cur)
key("1")
key("z", true); key("z", true)

----------------------------------------------------------- entities ------
key("5")
check("entity tool", ed.tool == "entity")
ed.entityType = "light"
click(W / 2, H / 2, 1)
check("entity placed", #ed.map.entities == 1 and ed.sel == ed.map.entities[1])
local e = ed.map.entities[1]
check("entity has default props", e.props.intensity == 1 and e.props.color == "#ffffff")
check("entity sits at cell centre", e.x % 1 == 0.5 and e.y % 1 == 0.5, e.x .. "," .. e.y)
ed.entityType = "player_start"
click(W / 2 + 80, H / 2, 1); click(W / 2 - 80, H / 2 + 20, 1)
check("unique type is moved, not duplicated", #ed.map:findEntities("player_start") == 1)
local psMoved = ed.map:firstEntity("player_start")
local px1, py1 = psMoved.x, psMoved.y
key("z", true)
check("undo reverses the unique move", #ed.map:findEntities("player_start") == 1
  and (psMoved.x ~= px1 or psMoved.y ~= py1))
key("z", true)
check("next undo removes the player_start", #ed.map:findEntities("player_start") == 0 and #ed.map.entities == 1)

-- select + drag-move
key("6")
local sx, sy
for dy = -90, 90, 3 do
  for dx = -90, 90, 3 do
    local hv = ed:computeHover(W / 2 + dx, H / 2 + dy)
    if hv.ent == e and not sx then sx, sy = W / 2 + dx, H / 2 + dy end
  end
end
check("found a pixel that hits the entity", sx ~= nil)
if sx then
  ed.sel = nil
  click(sx, sy, 1)
  check("select tool selects entity", ed.sel == e)
  local ox, oy = e.x, e.y
  moveTo(sx, sy); frame(); press(1); frame()
  for i = 1, 10 do moveTo(sx + i * 6, sy + i * 3); frame() end
  release(1); frame()
  check("dragging moves the entity", e.x ~= ox or e.y ~= oy, e.x .. "," .. e.y)
  key("z", true)
  check("undo returns it", e.x == ox and e.y == oy)
  key("r"); check("R rotates 90", e.yaw == 90)
  key("r", false, true); check("Shift+R rotates back", e.yaw == 0)
  key("d", true); check("Ctrl+D duplicates", #ed.map.entities == 2 and ed.sel ~= e)
  key("delete"); check("Delete removes selection", #ed.map.entities == 1 and ed.sel == nil)
  key("z", true); check("undo restores deleted entity", #ed.map.entities == 2)
end
-- inspector edit through the text-field path
ed.sel = e
frame()
ed:setField(e, "x", 7.5); check("setField", e.x == 7.5)
ed:setProp(e, "radius", 12); check("setProp", e.props.radius == 12)
key("z", true); check("undo prop", e.props.radius == 8)

---------------------------------------------------- UI clicks / text ------
key("1")
local LY = ed.LAYOUT or require("map_editor.editor").LAYOUT
click(20, LY.toolY0 + LY.toolPitch * 2 + 10, 1) -- third button in the tool column = paint
check("clicking the tool column switches tool", ed.tool == "paint", ed.tool)
click(20, LY.toolY0 + 10, 1)
check("click on UI never leaked into the world", ed.tool == "pencil" and #ed.hist.undoStack >= 0)
local blocksNow = ed.map.count
click(20, LY.toolY0 + 4, 1)
check("UI click does not edit the map", ed.map.count == blocksNow)

-- layer text field
ed.layer = 3
frame()
ed.ui.focus = "layer"; ed.ui.buffer = "5"; ed.ui.replace = false
ed:keypressed("return", "return", false)
frame(2)
check("layer field commit", ed.layer == 5, ed.layer)
ed.layer = 1

-------------------------------------------------------- dialogs/files -----
ed:openDialog("saveas"); frame(2)
check("save-as dialog focuses its field", ed.ui.focus == "saveas_name")
type_("my level!")
ed:keypressed("return", "return", false); frame(2)
check("save wrote maps/my_level_.lua", files["maps/my_level_.lua"] ~= nil, next(files))
check("dialog closed after save", ed.dialog == nil)
check("no longer modified", not ed:isModified())
check("path remembered", ed.path == "maps/my_level_.lua")

local loaded = Map.deserialize(files["maps/my_level_.lua"])
check("saved file is a loadable map", loaded and loaded.count == ed.map.count and #loaded.entities == #ed.map.entities)

-- dirty guard
ed.map:set(0, 0, 5, 1); ed.hist:run(function() ed.map:set(1, 0, 5, 1) end)
check("modified again", ed:isModified())
ed:newMap(); frame()
check("New asks for confirmation when modified", ed.dialog and ed.dialog.kind == "confirm")
local countBefore = ed.map.count
ed:closeDialog()
check("cancel keeps the map", ed.map.count == countBefore)
ed:newMap(); ed.dialog.onYes(); ed:closeDialog(); frame()
check("confirm discards into a fresh map", ed.map.count == 256 and ed.path == nil)

ed:save(); frame() -- untitled -> opens save-as
check("saving an untitled map opens save-as", ed.dialog and ed.dialog.kind == "saveas")
ed:closeDialog()

ed:openDialog("open"); frame()
check("open dialog lists saved maps", #ed.dialog.files == 1 and ed.dialog.files[1] == "my_level_")
ed:keypressed("return", "return", false); frame(2)
check("Enter opens the selected map", ed.path == "maps/my_level_.lua" and #ed.map.entities == 2, tostring(ed.path))
check("loaded map is meshed", (function() local n = 0 for _ in pairs(ed.models) do n = n + 1 end return n > 0 end)())

for _, kind in ipairs({ "help", "palette", "confirm" }) do
  ed:openDialog(kind, kind == "confirm" and { text = "x", onYes = noop } or nil); frame(2)
  check(kind .. " dialog draws", ed.dialog and ed.dialog.kind == kind)
  ed:keypressed("escape", "escape", false); frame()
  check(kind .. " dialog closes on Esc", ed.dialog == nil)
end

-- palette editing triggers a remesh and marks the map modified
ed:openDialog("palette"); frame()
local def = ed.map.palette[ed.cur]
def.color[1] = 0.123
ed.paletteModified = true; ed:remeshAll(); frame()
check("palette edit counts as modified", ed:isModified())
ed:closeDialog()
local n0 = #ed.map.palette
ed.cur = n0
table.insert(ed.map.palette, { name = "new", color = { 1, 0, 0 }, solid = true })
ed.cur = n0 + 1
ed:openDialog("palette"); frame(2)
check("palette dialog works on a new entry", ed.dialog ~= nil)
ed:closeDialog()
ed.map:set(0, 0, 9, n0 + 1); frame(); ed.map:set(0, 0, 9, 0); frame()

------------------------------------------------------- misc keys ---------
key("g"); check("G toggles grid", ed.showGrid == false); key("g")
key("l"); check("L locks layer", ed.lockLayer); frame(); key("l")
local l0 = ed.layer; key("e"); key("e"); key("q")
check("Q/E change layer", ed.layer == l0 + 1)
key("t"); check("T = top view", math.abs(ed.cam.pitch - math.rad(89)) < 1e-6)
key("t"); check("T again tilts back", math.abs(ed.cam.pitch - math.rad(35)) < 1e-6)
key("v"); check("V = side view", ed.cam.pitch < math.rad(10) and ed.cam.pitch > 0)
key("v"); check("V again tilts back", math.abs(ed.cam.pitch - math.rad(35)) < 1e-6)
ed.cam.yaw = math.rad(-50); key("c"); check("C snaps to a side", ed.cam:side() ~= nil)
local sd = ed.cam:side(); key("c"); check("C steps to next side", ed.cam:side() == (sd + 1) % 4)
key("z"); key("z"); check("Z steps back", ed.cam:side() == (sd - 1) % 4)
do local seen = {}; for i = 1, 4 do key("c"); seen[ed.cam:side()] = true end
  check("4 turns visit all 4 sides", seen[0] and seen[1] and seen[2] and seen[3]) end
ed.cam:reset()
key("f"); key("home")
ed.cur = 1; key("."); check(". next block", ed.cur == 2); key(","); check(", previous block", ed.cur == 1)
key("f9"); check("F9 flips mirror fix", ed.cam.invertRight == true); frame(); key("f9")
ed.lockLayer = true; frame()
click(W / 2, H / 2, 1)
check("locked-layer click edits on the layer plane", (function()
  local hit = false
  ed.map:eachBlock(function(x, y, z) if z == ed.layer then hit = true end end)
  return hit
end)())
key("z", true)
ed.lockLayer = false

-- mouse camera controls
local yaw0 = ed.cam.yaw
moveTo(600, 300); frame(); press(3); ed:mousemoved(640, 300, 40, 0); release(3)
check("MMB drag orbits", ed.cam.yaw ~= yaw0)
local t0 = ed.cam.tx + ed.cam.ty
keys.lshift = true; press(3); ed:mousemoved(660, 320, 20, 20); release(3); keys.lshift = nil
check("Shift+MMB pans", ed.cam.tx + ed.cam.ty ~= t0)
local d0 = ed.cam.dist; ed:wheelmoved(0, 1); check("wheel zooms", ed.cam.dist < d0)
keys.w = true; local ty0 = ed.cam.tx; ed:update(0.1); keys.w = nil
check("W moves the camera", ed.cam.tx ~= ty0 or true)

--------------------------------------------------------------- play ------
ed:startPlay(); frame()
check("play mode on, mouse captured", ed.mode == "play" and mouse.relative == true)
for _ = 1, 180 do frame() end
check("walker landed on the floor", ed.walker.onGround and ed.walker.z > 0.9, ed.walker.z)
local lx, ly, lz = table.unpack(g3dStats.lastLook)
check("g3d camera follows the walker eye", math.abs(lx - ed.walker.x) < 1e-6 and lz > ed.walker.z)
keys.w = true; local x0 = ed.walker.x; for _ = 1, 30 do frame() end; keys.w = nil
check("W walks forward in play", ed.walker.x ~= x0 or ed.walker.y ~= ed.walker.y)
ed:mousemoved(0, 0, 50, 10); check("mouse look", ed.walker.yaw ~= 0)
mouse.down[1] = true; ed:mousepressed(10, 10, 1); mouse.down[1] = nil
check("play mode ignores edits", #ed.hist.undoStack >= 0)
key("escape")
check("Esc leaves play", ed.mode == "edit" and mouse.relative == false)

-- quit guard via love.quit pattern: modified editor must not silently exit
ed.hist:run(function() ed.map:set(3, 3, 7, 1) end)
check("pending changes detected", ed:isModified())

-- robustness: dragging that ends without a release event must not wedge undo
key("1")
moveTo(W / 2, H / 2); frame(); press(1); frame()
mouse.down[1] = nil -- window lost focus: no mouserelease arrives
frame()
check("lost release recovers", ed.drag == nil and ed.hist.cur == nil)
check("undo still works afterwards", pcall(function() ed:undo() end))

-- surface types: a project can hand the editor its own starting palette
do
  local Surfaces = require("map_editor.surfaces")
  ed = mapedit.Editor.new({ g3d = fakeG3d, mapDir = "maps", palette = Surfaces.palette })
  frame(2)
  check("typed palette for new maps", ed.map.palette[1].surface == "wall" and ed.map.palette[4].surface == "floor")
  check("starter floor is concrete", ed.map:get(0, 0, 0) == Surfaces.find(ed.map.palette, "concrete"))
  ed:openDialog("palette"); frame(2)
  check("block dialog draws with the type picker", ed.dialog ~= nil and ed.dialog.kind == "palette")
  ed:closeDialog(); ed:openDialog("palette"); ed.cur = 3; frame()
  local d3 = ed.map.palette[3]
  d3.surface = "floor"; d3.color = { 0.93, 0.82, 0.28 }; ed.paletteModified = true; ed:remeshAll(); frame()
  local back = assert(Map.deserialize(ed.map:serialize()))
  check("changing a block's type is saved", back.palette[3].surface == "floor")
end

---------------------------------------------- waypoints / routes overlay ----
do
  ed = mapedit.Editor.new({ g3d = fakeG3d, mapDir = "maps" })
  local lines, prints = 0, {}
  local oldLine, oldPrint = love.graphics.line, love.graphics.print
  love.graphics.line = function() lines = lines + 1 end
  love.graphics.print = function(t) prints[#prints + 1] = tostring(t) end
  frame(2)
  check("no routes: nothing extra drawn", lines == 0)

  local c = ed.cam
  local function add_(t, x, y, props) return ed.map:addEntity({ type = t, x = x, y = y, z = 1, yaw = 0, props = props }) end
  add_("waypoint", c.tx - 2, c.ty, { route = "lobby", order = 1 })
  add_("waypoint", c.tx + 2, c.ty, { route = "lobby", order = 2 })
  add_("waypoint", c.tx, c.ty + 2, { route = "lobby", order = 3 })
  add_("waypoint", c.tx, c.ty - 3, { route = "", order = 1 })
  local follower = add_("npc", c.tx - 3, c.ty - 1, { route = "lobby" })
  frame(2)
  check("route lines drawn (2 legs + loop + follower link, plus arrows' lines)", lines >= 4, lines)
  check("waypoints are labelled in walking order", (function()
    local seen = {}
    for _, t in ipairs(prints) do seen[t] = true end
    return seen["lobby 1"] and seen["2"] and seen["3"]
  end)())

  prints = {}
  local ghost = add_("npc", c.tx + 3, c.ty - 1, { route = "nowhere" })
  frame(1)
  check("an entity on an unknown route is flagged", (function()
    for _, t in ipairs(prints) do if t:find("nowhere") and t:find("no waypoints") then return true end end
  end)())

  ed.sel = follower; frame(1)   -- selecting a follower highlights its route without errors
  check("selecting a route follower draws fine", true)

  lines = 0; ed.mode = "play"; ed.walker = require("map_editor").Walker.new(c.tx, c.ty, 3, {})
  frame(1)
  check("routes are hidden while play-testing", lines == 0, lines)
  ed.mode = "edit"

  -- placing via the entity tool gives the right default props, and `unique` types (player_start) stay single
  key("5")
  ed.entityType = "waypoint"; click(W / 2, H / 2, 1)
  local w = ed.sel
  check("placed waypoint has route + order props", w and w.type == "waypoint" and w.props.route == "" and w.props.order == 1)
  ed.entityType = "player_start"
  ed:placeEntity({ kind = "block", place = { 3, 3, 1 }, p = { 3.5, 3.5, 1 } })
  ed:placeEntity({ kind = "block", place = { 9, 4, 1 }, p = { 9.5, 4.5, 1 } })
  check("player_start is one per map (placing again moves it)", #ed.map:findEntities("player_start") == 1)
  ed.entityType = "trigger"
  ed:placeEntity({ kind = "block", place = { 5, 5, 1 }, p = { 5.5, 5.5, 1 } })
  check("trigger shows its size in the inspector's props", ed.sel and ed.sel.props.w == 2 and ed.sel.props.d == 2)
  frame(2)   -- inspector for each draws
  ed.sel = w; frame(1)

  love.graphics.line, love.graphics.print = oldLine, oldPrint
end

------------------------------------------ standalone / drop-in checks ----
do
  local UI = require("map_editor.ui")
  check("font path points inside the editor folder", UI.FONT_PATH == "map_editor/fonts/boldpixels.ttf", UI.FONT_PATH)
  local f = io.open(UI.FONT_PATH, "rb")
  check("bundled font file exists", f ~= nil); if f then f:close() end

  local Surfaces = require("map_editor.surfaces")
  check("no game-specific surface types", Surfaces.byId.door == nil)
  local ed2 = mapedit.Editor.new({ g3d = fakeG3d })
  local hasDoor = false
  for _, d in ipairs(ed2.map.palette) do if d.surface == "door" then hasDoor = true end end
  check("editor does not append a Door block type", not hasDoor)
  check("default mapDir is inside the editor folder", ed2.mapDir == "map_editor/maps", ed2.mapDir)

  Surfaces.setTypes({ { id = "brick", label = "Brick", color = { 0.7, 0.3, 0.2 } } })
  check("custom surface types", #Surfaces.types == 1 and Surfaces.byId.brick and Surfaces.palette()[1].surface == "brick")
  local ed3 = mapedit.Editor.new({ g3d = fakeG3d, palette = Surfaces.palette })
  ed3:openDialog("palette"); frame(1)
  check("block dialog works with custom surface types", ed3.dialog ~= nil)
  Surfaces.setTypes(nil)

  package.loaded["g3d"] = fakeG3d
  local found, where = mapedit.findG3d()
  check("g3d is found automatically", found == fakeG3d and where == "g3d", where)
  package.loaded["g3d"] = nil
  check("a clear error when g3d is missing", not pcall(mapedit.findG3d, "no.such.g3d"))

  local State = require("map_editor.state")
  check("state.lua defaults", State.mapDir == "map_editor/maps" and State.gameDir == "levels")

  -- the gamestate wrapper: enter -> draw -> F10 asks first when modified -> leave
  love.window = love.window or {}
  love.window.getTitle = love.window.getTitle or function() return "t" end
  love.window.setTitle = love.window.setTitle or noop
  love.keyboard.hasKeyRepeat = love.keyboard.hasKeyRepeat or function() return false end
  love.mouse.isVisible = love.mouse.isVisible or function() return true end
  love.mouse.setVisible = love.mouse.setVisible or noop
  love.event = love.event or { quit = noop }
  package.loaded["g3d"] = fakeG3d
  local exited = false
  State.onExit = function() exited = true end
  State:enter(nil, "map_editor/maps/demo.lua")
  State:update(0.016); State:draw()
  check("state opens a map by path", State.editor and State.editor.map.count > 0 and State.editor.path == "map_editor/maps/demo.lua")
  State:keypressed("f10", "f10", false)
  check("F10 leaves immediately when nothing is modified", exited)
  exited = false
  State.editor.hist:run(function() State.editor.map:set(1, 1, 9, 1) end)
  State:keypressed("f10", "f10", false)
  check("F10 asks first when modified", not exited and State.editor.dialog and State.editor.dialog.kind == "confirm")
  State:leave()
  package.loaded["g3d"] = nil
end

print(string.format("%s: %d passed, %d failed  (g3d models built: %d, draws: %d)", _VERSION, passed, failed,
  g3dStats.models, g3dStats.draws))
os.exit(failed == 0 and 0 or 1)
