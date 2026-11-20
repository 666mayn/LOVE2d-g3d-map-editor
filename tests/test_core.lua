-- Run from the project root:  texlua tests/test_core.lua   (or: pandoc lua tests/test_core.lua)
package.path = "./?.lua;./?/init.lua;" .. package.path
local Map = require("map_editor.map")
local History = require("map_editor.history")
local R = require("map_editor.raycast")

local passed, failed = 0, 0
local function check(name, cond, extra)
  if cond then passed = passed + 1
  else failed = failed + 1; print("FAIL: " .. name .. (extra and (" -> " .. tostring(extra)) or "")) end
end
local function eq(name, a, b) check(name, a == b, tostring(a) .. " ~= " .. tostring(b)) end

-- blocks: set/get across chunk borders and negatives
local m = Map.new()
eq("empty get", m:get(0, 0, 0), 0)
check("set new", m:set(0, 0, 0, 1))
check("set same is no-op", not m:set(0, 0, 0, 1))
m:set(-1, -1, -1, 2); m:set(15, 15, 15, 3); m:set(16, 0, 0, 4); m:set(-17, 5, 100, 5)
eq("get 0", m:get(0, 0, 0), 1); eq("get -1", m:get(-1, -1, -1), 2)
eq("get 15", m:get(15, 15, 15), 3); eq("get 16", m:get(16, 0, 0), 4); eq("get far", m:get(-17, 5, 100), 5)
eq("count", m.count, 5)
m:set(16, 0, 0, 0)
eq("count after delete", m.count, 4)
eq("empty chunk removed", m.chunks[Map.chunkKey(1, 0, 0)], nil)
check("out of range rejected", not m:set(99999, 0, 0, 1))
local x1, y1, z1, x2, y2, z2 = m:bounds()
check("bounds", x1 == -17 and y1 == -1 and z1 == -1 and x2 == 15 and y2 == 15 and z2 == 100,
  table.concat({ x1, y1, z1, x2, y2, z2 }, ","))
check("border block dirties neighbour chunks",
  m.dirty[Map.chunkKey(1, 0, 0)] ~= nil and m.dirty[Map.chunkKey(0, 0, 0)] ~= nil)

-- fillBox + serialisation round trip
local m2 = Map.new({ name = "rt test" })
eq("fill count", m2:fillBox(-5, -5, 0, 20, 20, 2, 3), 26 * 26 * 3)
m2:fillBox(0, 0, 3, 3, 3, 3, 12)
m2.sky = { 0.1, 0.2, 0.3 }
m2.palette[1].uv = { 0, 0, 0.5, 0.5 }
local e = m2:addEntity({ type = "light", name = 'he said "hi"\nnewline', x = 1.25, y = -2.5, z = 3, yaw = 90,
  props = { intensity = 2.5, color = "#ff0000", on = true } })
m2:addEntity({ type = "player_start", x = 0.5, y = 0.5, z = 3 })
local s = m2:serialize()
local m3, err = Map.deserialize(s)
check("deserialize ok", m3 ~= nil, err)
eq("name", m3.name, "rt test")
eq("count rt", m3.count, m2.count)
local same = true
m2:eachBlock(function(x, y, z, id) if m3:get(x, y, z) ~= id then same = false end end)
check("all blocks identical", same)
eq("palette size", #m3.palette, #m2.palette)
check("uv rt", m3.palette[1].uv and m3.palette[1].uv[3] == 0.5)
eq("water non-solid", m3.palette[12].solid, false)
eq("entities", #m3.entities, 2)
eq("entity name w/ quotes+newline", m3.entities[1].name, 'he said "hi"\nnewline')
eq("entity float", m3.entities[1].x, 1.25); eq("entity prop num", m3.entities[1].props.intensity, 2.5)
eq("entity prop bool", m3.entities[1].props.on, true)
check("sky rt", math.abs(m3.sky[2] - 0.2) < 1e-9)
eq("serialize is deterministic", m3:serialize(), s)

-- hostile / broken input
check("rejects wrong format", Map.deserialize("return {format='nope'}") == nil)
check("rejects syntax error", Map.deserialize("return {") == nil)
check("sandbox: no os access", Map.deserialize("os.execute('echo pwned > /tmp/pwned_by_map') return {}") == nil)
local f = io.open("/tmp/pwned_by_map"); check("sandbox really blocked", f == nil); if f then f:close() end
check("rejects corrupt runs", Map.deserialize(
  "return {format='g3d-mapedit', chunks={{0,0,0,{'a',1}}}}") == nil)
check("newer version rejected", Map.deserialize("return {format='g3d-mapedit', version=99}") == nil)

-- file round trip
local ok = Map.writeFile("/tmp/_mapedit_test.lua", s)
check("write file", ok)
local m4 = Map.load("/tmp/_mapedit_test.lua")
check("load file", m4 and m4.count == m2.count)
os.remove("/tmp/_mapedit_test.lua")

-- history
local m5 = Map.new()
local h = History.new(m5)
h:begin(); m5:set(1, 1, 1, 1); m5:set(2, 2, 2, 2); h:commit()
h:begin(); m5:set(1, 1, 1, 5); h:commit()
h:begin(); h:commit()
eq("empty transaction not recorded", #h.undoStack, 2)
h:undo(); eq("undo restores old value", m5:get(1, 1, 1), 1)
h:undo(); eq("undo removes", m5:get(1, 1, 1), 0); eq("undo removes 2", m5:get(2, 2, 2), 0); eq("count 0", m5.count, 0)
h:redo(); eq("redo", m5:get(2, 2, 2), 2)
h:redo(); eq("redo 2", m5:get(1, 1, 1), 5)
h:undo(); h:begin(); m5:set(9, 9, 9, 1); h:commit()
check("new edit clears redo", not h:redo())
-- entity undo/redo
local ent = {}
h:begin(); ent = m5:addEntity({ type = "pickup", x = 1, y = 2, z = 3 }); h:commit()
eq("entity added", #m5.entities, 1)
h:begin(); m5:setEntityField(ent, "x", 10); m5:setEntityProp(ent, "item", "key"); h:commit()
eq("field set", ent.x, 10)
h:undo(); eq("field undone", ent.x, 1); eq("prop undone", ent.props.item, nil)
h:redo(); eq("prop redone", ent.props.item, "key")
h:begin(); m5:removeEntity(ent); h:commit(); eq("entity removed", #m5.entities, 0)
h:undo(); eq("entity restored", #m5.entities, 1); eq("same object restored", m5.entities[1], ent)
h:cancel() -- no-op without transaction
h:begin(); m5:set(50, 50, 50, 1); h:cancel(); eq("cancel rolls back", m5:get(50, 50, 50), 0)
check("history run commits", (function() h:run(function() m5:set(60, 0, 0, 1) end) return m5:get(60, 0, 0) == 1 end)())

-- raycast: voxel
local function solidAt(set) return function(x, y, z) return set[x .. "," .. y .. "," .. z] end end
local hx, hy, hz, nx, ny, nz, t = R.voxel(0.5, 0.5, 5.5, 0, 0, -1, 100, solidAt({ ["0,0,2"] = true }))
check("ray down hits", hx == 0 and hy == 0 and hz == 2 and nz == 1 and nx == 0 and ny == 0, table.concat({ hx, hy, hz, nx, ny, nz }, ","))
check("ray dist", math.abs(t - 2.5) < 1e-9, t)
hx, hy, hz, nx, ny, nz = R.voxel(-3.2, 0.5, 0.5, 1, 0, 0, 100, solidAt({ ["2,0,0"] = true }))
check("ray +x hits with -x normal", hx == 2 and nx == -1, table.concat({ hx, nx }, ","))
hx, hy, hz, nx = R.voxel(10.5, 0.5, 0.5, -1, 0, 0, 100, solidAt({ ["2,0,0"] = true }))
check("ray -x normal +x", hx == 2 and nx == 1)
check("ray misses", R.voxel(0.5, 0.5, 5.5, 0, 0, 1, 50, solidAt({ ["0,0,2"] = true })) == nil)
check("ray maxDist", R.voxel(0.5, 0.5, 50.5, 0, 0, -1, 10, solidAt({ ["0,0,2"] = true })) == nil)
local d = 1 / math.sqrt(3)
hx, hy, hz = R.voxel(-5.5, -5.5, -5.5, d, d, d, 100, solidAt({ ["3,3,3"] = true }))
check("diagonal ray", hx == 3 and hy == 3 and hz == 3)
hx, hy, hz, nx, ny, nz, t = R.voxel(0.5, 0.5, 0.5, 1, 0, 0, 10, solidAt({ ["0,0,0"] = true }))
check("starting inside solid", hx == 0 and t == 0 and nx == 0)
-- through the real map
local mm = Map.new(); mm:fillBox(-10, -10, 0, 10, 10, 0, 1)
local rx, ry, rz, rnx, rny, rnz = mm:raycast(0.3, 0.3, 10, 0, 0, -1)
check("map:raycast onto floor", rx == 0 and ry == 0 and rz == 0 and rnz == 1)
-- aabb / plane
check("aabb hit", math.abs(R.aabb(-5, 0.5, 0.5, 1, 0, 0, 0, 0, 0, 1, 1, 1) - 5) < 1e-9)
check("aabb miss", R.aabb(-5, 5, 0.5, 1, 0, 0, 0, 0, 0, 1, 1, 1) == nil)
check("aabb parallel outside", R.aabb(0.5, 3, 0.5, 1, 0, 0, 0, 0, 0, 1, 1, 1) == nil)
check("aabb behind", R.aabb(5, 0.5, 0.5, 1, 0, 0, 0, 0, 0, 1, 1, 1) == nil)
local pt, px, py, pz = R.plane(0, 0, 10, 0.5, 0, -1, 3, 2)
check("plane z", math.abs(pt - 8) < 1e-9 and math.abs(px - 4) < 1e-9 and pz == 2)
check("plane parallel", R.plane(0, 0, 10, 1, 0, 0, 3, 2) == nil)
check("plane behind", R.plane(0, 0, 10, 0, 0, 1, 3, 2) == nil)

print(string.format("%s: %d passed, %d failed", _VERSION, passed, failed))
os.exit(failed == 0 and 0 or 1)
