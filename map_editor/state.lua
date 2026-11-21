-- map_editor/state.lua : the editor as a gamestate table (no dependencies). Use it with hump.gamestate,
-- or call its callbacks yourself - see "Add it to your own game" in the README.
--
--   local Editor = require "map_editor.state"
--   Editor.onExit = function() ... return to your game / menu ... end     -- called by F10 / the Exit button
--   Gamestate.switch(Editor)                    -- or Gamestate.switch(Editor, "map_editor/maps/demo.lua")
--
-- Optional hooks / settings (set them before switching to the state):
--   Editor.mapDir      folder maps are saved to / listed from        (default "<this folder>/maps")
--   Editor.gameDir     folder the Export button writes finished levels to   (default "levels")
--   Editor.defaultMap  map opened when none is given                 (default "<this folder>/maps/test_room.lua")
--   Editor.onExit()    F10 / Exit button (after asking about unsaved changes). Default: quit LÖVE.
--   Editor.onPlay(path) F6 = "play this saved map in my game". Leave nil to disable F6.
--   Editor.onExport(dest) called after Export wrote a level to gameDir
--   Editor.entityTypes extra entity type definitions, appended to the defaults (same shape as map_editor/entities.lua)
--   Editor.g3d         your g3d module, if it is not at a standard path (see Editor.G3D_PATHS in editor.lua)
--   Editor.palette     function returning a fresh palette for NEW maps (default: map_editor.map defaultPalette)
--
-- Keys: F10 leaves the editor, F6 calls onPlay. Esc stays inside the editor (it only closes dialogs / play-test).

local BASE = ((...) or "map_editor.state"):match("^(.*)%.[^.]+$") or "map_editor"
local DIR  = BASE:gsub("%.", "/")

local mapedit  = require(BASE)
local Entities = require(BASE .. ".entities")

local State = {
  mapDir = DIR .. "/maps",
  gameDir = "levels",
  defaultMap = DIR .. "/maps/test_room.lua",
  entityTypes = nil,
  g3d = nil,
  palette = nil,
  onExit = nil, onPlay = nil, onExport = nil,
}

-- Built-in entity types plus any the project added.
local function entityTypes()
  local list = {}
  for _, def in ipairs(Entities.defaults) do
    local d = {}
    for k, v in pairs(def) do d[k] = v end
    d.group = d.group or "General"
    list[#list + 1] = d
  end
  for _, def in ipairs(State.entityTypes or {}) do list[#list + 1] = def end
  return list
end

local function leaveEditor()
  if State.onExit then State.onExit() else love.event.quit() end
end

-- F10 and the toolbar "Exit" button both come through here: ask first if there are unsaved changes
local function requestLeave(ed)
  if ed:isModified() then
    ed:openDialog("confirm", { text = "Leave the editor and discard unsaved changes?", yes = "Leave", onYes = leaveEditor })
  else
    leaveEditor()
  end
end

function State:enter(_, mapPath)
  self.saved = {
    title   = love.window.getTitle(),
    repeat_ = love.keyboard.hasKeyRepeat(),
    visible = love.mouse.isVisible(),
  }
  love.mouse.setRelativeMode(false)
  love.mouse.setVisible(true)
  local start = mapPath
  if not start and State.defaultMap and love.filesystem.getInfo(State.defaultMap) then start = State.defaultMap end
  self.editor = mapedit.Editor.new({
    g3d = State.g3d, mapDir = State.mapDir, gameDir = State.gameDir, onExport = State.onExport,
    onLeave = function() requestLeave(self.editor) end,
    map = start, palette = State.palette, entityTypes = entityTypes(),
  })
end

function State:leave()
  love.mouse.setRelativeMode(false)
  love.mouse.setVisible(self.saved.visible)
  love.keyboard.setKeyRepeat(self.saved.repeat_)
  love.window.setTitle(self.saved.title)
  love.graphics.setDepthMode("always", false)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setShader()
  love.graphics.setCanvas()
  self.editor = nil
end

function State:update(dt)                     self.editor:update(dt) end
function State:draw()                         self.editor:draw() end
function State:mousepressed(x, y, b)          self.editor:mousepressed(x, y, b) end
function State:mousereleased(x, y, b)         self.editor:mousereleased(x, y, b) end
function State:mousemoved(x, y, dx, dy)       self.editor:mousemoved(x, y, dx, dy) end
function State:wheelmoved(dx, dy)             self.editor:wheelmoved(dx, dy) end
function State:keyreleased(k)                 self.editor:keyreleased(k) end
function State:textinput(t)                   self.editor:textinput(t) end
function State:resize(w, h)                   self.editor:resize(w, h) end

function State:keypressed(key, scancode, isrepeat)
  local ed = self.editor
  if key == "f10" and not isrepeat then
    requestLeave(ed)
    return
  end
  if key == "f6" and not isrepeat and ed.mode == "edit" and State.onPlay then
    if not ed.path then
      ed:flash("Save the map first (Ctrl+S), then F6 plays it", 3, true)
    elseif ed:isModified() then
      ed:flash("Unsaved changes: Ctrl+S, then F6 plays it", 3, true)
    else
      State.onPlay(ed.path)
    end
    return
  end
  ed:keypressed(key, scancode, isrepeat)
end

return State
