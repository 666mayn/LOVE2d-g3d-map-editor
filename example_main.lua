-- Example main.lua showing how to wire map_editor into a LÖVE + g3d project.
-- Copy it to your project root as main.lua (or merge the pieces into your own). Needs: g3d somewhere on the
-- require path (g3d/, libs/g3d/, lib/g3d/ ...) and the map_editor/ folder next to main.lua.
--
--   F8   game -> editor  (opens the level you are looking at)
--   F10  editor -> game  (asks first if there are unsaved changes)
--   F6   in the editor: play the saved map right now
--
-- The tiny "game" here is just a free-fly camera, replace it with yours.

local mapedit = require "map_editor"
local Editor  = require "map_editor.state"
local g3d     = mapedit.findG3d()                -- or: require "libs.g3d"

local LEVEL = "map_editor/maps/demo.lua"
local mode, level, levelPath = "game", nil, LEVEL

local function startGame(path)
  levelPath = path or levelPath
  level = assert(mapedit.loadLevel(levelPath, g3d))
  local s = level.map:firstEntity("player_start")
  if s then g3d.camera.lookInDirection(s.x, s.y, s.z + 1.6, math.rad(s.yaw or 0), 0) end
  mode = "game"
  g3d.camera.resize(love.graphics.getDimensions())
  love.mouse.setRelativeMode(true)
end

local function startEditor()
  love.mouse.setRelativeMode(false)
  mode = "editor"
  Editor:enter(nil, levelPath)
end

Editor.onExit = function() Editor:leave(); startGame() end       -- F10 / Exit button
Editor.onPlay = function(path) Editor:leave(); startGame(path) end -- F6 in the editor
-- Editor.gameDir = "levels"                  -- where the Export button writes finished levels
-- Editor.entityTypes = { { name = "chest", color = { 0.9, 0.7, 0.2 }, size = { 1, 1, 1 }, props = {} } }

function love.load() startGame() end

function love.update(dt)
  if mode == "editor" then return Editor:update(dt) end
  g3d.camera.firstPersonMovement(dt)
end

function love.draw()
  if mode == "editor" then return Editor:draw() end
  level:draw()
end

function love.mousemoved(x, y, dx, dy)
  if mode == "editor" then return Editor:mousemoved(x, y, dx, dy) end
  g3d.camera.firstPersonLook(dx, dy)
end

function love.keypressed(key, sc, isrepeat)
  if mode == "editor" then return Editor:keypressed(key, sc, isrepeat) end
  if key == "f8" then startEditor() elseif key == "escape" then love.event.quit() end
end

-- the editor needs the rest of the input callbacks too
function love.mousepressed(x, y, b)  if mode == "editor" then Editor:mousepressed(x, y, b) end end
function love.mousereleased(x, y, b) if mode == "editor" then Editor:mousereleased(x, y, b) end end
function love.wheelmoved(dx, dy)     if mode == "editor" then Editor:wheelmoved(dx, dy) end end
function love.keyreleased(k)         if mode == "editor" then Editor:keyreleased(k) end end
function love.textinput(t)           if mode == "editor" then Editor:textinput(t) end end
function love.resize(w, h)
  if mode == "editor" then Editor:resize(w, h) else g3d.camera.resize(w, h) end
end
