-- Regenerates map_editor/maps/test_room.lua (two rooms + a courtyard) from the project root:
--   lua map_editor/tools/make_test_room.lua
-- Every block uses one of the surface types (see map_editor/surfaces.lua).
package.path = "./?.lua;./?/init.lua;" .. package.path
local Map = require("map_editor.map")
local Surfaces = require("map_editor.surfaces")

local m = Map.new({ name = "test_room", palette = Surfaces.palette() })
local WALL, CONCRETE, GROUND, FLOOR, CEILING =
  Surfaces.find(m.palette, "wall"), Surfaces.find(m.palette, "concrete"), Surfaces.find(m.palette, "ground"),
  Surfaces.find(m.palette, "floor"), Surfaces.find(m.palette, "ceiling")

-- layer 0 is the floor layer (its top is where the player walks)
m:fillBox(0, 0, 0, 11, 13, 0, CONCRETE)    -- room A
m:fillBox(12, 0, 0, 19, 13, 0, FLOOR)      -- room B
m:fillBox(20, 0, 0, 27, 13, 0, GROUND)     -- courtyard outside

-- walls, 3 blocks high (layers 1-3)
local function wall(x1, y1, x2, y2) m:fillBox(x1, y1, 1, x2, y2, 3, WALL) end
wall(0, 0, 19, 0);  wall(0, 13, 19, 13)    -- south / north
wall(0, 1, 0, 12)                          -- west
wall(19, 1, 19, 5); wall(19, 8, 19, 12)    -- east, with a doorway (y 6-7) to the courtyard
wall(11, 1, 11, 5); wall(11, 8, 11, 12)    -- divider, with a doorway (y 6-7)

-- ceiling over both rooms (layer 4)
m:fillBox(0, 0, 4, 19, 13, 4, CEILING)

-- cover
m:fillBox(5, 3, 1, 5, 3, 3, CONCRETE)      -- pillar
m:fillBox(14, 9, 1, 15, 9, 1, CONCRETE)    -- low wall

m:addEntity({ type = "player_start", name = "", x = 2.5, y = 6.5, z = 1, yaw = 0, props = {} })
m.dirty = {}
local ok, where = m:save("map_editor/maps/test_room.lua")
print(ok and ("wrote " .. where) or ("FAILED: " .. tostring(where)))
