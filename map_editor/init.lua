-- map_editor: a voxel level editor + runtime loader for LÖVE and g3d (Z-up). Drop this folder next to main.lua.
--
--   local mapedit = require("map_editor")
--
--   -- in your game: load and draw a level
--   level = mapedit.loadLevel("map_editor/maps/demo.lua")      -- g3d is found automatically (or pass it as arg 2)
--   level:draw()                       -- inside love.draw, after g3d.camera is set up
--   level.map:isSolid(x, y, z)         -- collision queries
--   level.map:firstEntity("player_start")
--
--   -- the editor itself, as a gamestate (works with hump.gamestate or by hand, see the README):
--   local State = require("map_editor.state")
--
--   -- or drive the Editor object directly:
--   editor = mapedit.Editor.new{ g3d = require("path.to.g3d") }
local BASE = ((...) or "map_editor") .. "."

local M = {}
M.Map = require(BASE .. "map")
M.Mesher = require(BASE .. "mesher")
M.Walker = require(BASE .. "walker")
M.Camera = require(BASE .. "camera")
M.Entities = require(BASE .. "entities")
M.Surfaces = require(BASE .. "surfaces")
M.Routes = require(BASE .. "routes")
M.History = require(BASE .. "history")
M.raycast = require(BASE .. "raycast")
M.Editor = require(BASE .. "editor")
M.findG3d = M.Editor.findG3d

-- Load a map file and mesh it. `g3d` is optional (found automatically when nil). `texture` is optional (an atlas
-- image if your palette entries use `uv` rectangles); by default blocks are flat-coloured.
-- Returns a level table, or nil + error message.
function M.loadLevel(path, g3d, texture)
  g3d = g3d or M.findG3d()
  local map, err = M.Map.load(path)
  if not map then return nil, err end
  local tex = texture or M.Mesher.whiteTexture()
  local level = { map = map, texture = tex, models = M.Mesher.buildAll(map, g3d, tex) }

  function level:draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setDepthMode("lequal", true)
    for _, model in pairs(self.models) do model:draw() end
    love.graphics.setDepthMode("always", false)
  end

  -- call after changing blocks at runtime (map:set ...) to re-mesh touched chunks
  function level:remesh() return M.Mesher.update(self.map, self.models, g3d, self.texture) end

  return level
end

return M
