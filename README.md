# map_editor

An in-engine **voxel level editor + runtime loader** for [LÖVE](https://love2d.org) and
[g3d](https://github.com/groverburger/g3d) (Z-up). Build a level with the mouse, save it as a plain Lua file,
load and draw it in your game with two lines.

It is self-contained: the UI font ships inside the folder and nothing here depends on any particular game.

## Install

1. Copy the whole `map_editor/` folder next to your `main.lua`.
2. Have g3d in your project. It is found automatically at `g3d`, `libs.g3d`, `lib.g3d`, `libraries.g3d`,
   `vendor.g3d` or `third_party.g3d`. Anywhere else: pass it in (`Editor.g3d = require "my.path.g3d"`, or
   `Editor.new{ g3d = ... }`).
3. Wire it up. `example_main.lua` is a complete, minimal `main.lua` (F8 toggles game/editor); copy it or take the
   pieces you need (see below).

You can rename or move the folder (e.g. `libs/map_editor/`): font and map paths are worked out from where the
module was `require`d.

## Opening the editor

`map_editor/state.lua` is the editor as a gamestate table with the usual callbacks (`enter`, `update`, `draw`,
`keypressed`, `mousepressed`, ...). It has no dependencies, so it works with `hump.gamestate`:

```lua
local Editor = require "map_editor.state"
Editor.onExit = function() Gamestate.switch(game) end     -- F10 / Exit button
Gamestate.switch(Editor)                                   -- or Gamestate.switch(Editor, "map_editor/maps/demo.lua")
```

or by hand: call `Editor:enter(nil, path)` and forward the LÖVE callbacks while it is active (again, see
`example_main.lua`).

Settings, set before switching to it:

| Field | Meaning | Default |
|---|---|---|
| `Editor.mapDir` | where maps are saved / listed | `map_editor/maps` |
| `Editor.gameDir` | where the **Export** button writes finished levels | `levels` |
| `Editor.defaultMap` | map opened when none is given | `map_editor/maps/test_room.lua` |
| `Editor.onExit()` | F10 / Exit button (asks about unsaved changes first) | quits LÖVE |
| `Editor.onPlay(path)` | F6 = play the saved map in *your* game; nil disables F6 | nil |
| `Editor.onExport(dest)` | called after Export wrote a file | nil |
| `Editor.entityTypes` | your own entity types, added to the built-in ones | none |
| `Editor.g3d` | your g3d module if it is not at a standard path | auto |
| `Editor.palette` | function returning the palette for NEW maps | built-in |

Prefer no gamestate at all? `require("map_editor").Editor.new{ ...same options... }` gives you the raw editor
object with `:update(dt)`, `:draw()` and the input methods.

## Using a map in your game

```lua
local mapedit = require "map_editor"

level = mapedit.loadLevel("map_editor/maps/demo.lua")   -- g3d found automatically; or pass it as 2nd argument
-- love.draw, after your g3d camera is set up:
level:draw()

level.map:isSolid(x, y, z)                  -- integer block coords
level.map:boxHitsSolid(x1, y1, z1, x2, y2, z2)
level.map:firstEntity("player_start")       -- { x, y, z, yaw, props }
level.map:findEntities("light")             -- all entities of a type
level.map:raycast(ox, oy, oz, dx, dy, dz)
-- after map:set(...) at runtime:
level:remesh()
```

`mapedit.Walker` is a ready-made first-person controller with voxel collision. `mapedit.Mesher` turns a map into
g3d models (hidden faces culled, shading and ambient occlusion baked into vertex colours, so no lights needed).
Palette entries may carry `uv = {u0, v0, u1, v1}` for texture atlases; pass the atlas image as the third argument
of `loadLevel`.

The map file is a plain Lua data table (`format = "g3d-mapedit"`), loaded in a sandbox, so it is safe to read and
diff. 1 block = 1 unit; chunks are 16x16x16.

## Editor controls (F1 in the editor shows them all)

- **Tools** `1`-`6`: pencil, box, paint, pick, entity, select. LMB places, RMB erases.
- **Layers**: `Q`/`E` or `[`/`]` change the layer, `L` locks edits to it, `T` top view, `G` toggles the grid.
- **Camera**: MMB or Alt+LMB orbit, Shift+MMB pan, wheel zoom, WASD move, `F` focus, `Z`/`C` swing 90 degrees.
- **Blocks**: `,` `.` or Ctrl+wheel cycle block types, `I` picks the block under the cursor. The palette bar has
  **Edit** (name, colour, solidity, opacity, surface type) and **+** (new block type).
- **Entities**: `R` rotates, Del/`X` deletes, Ctrl+D duplicates, Shift = free placement. Properties are edited in
  the inspector (scrolls with the wheel).
- **Files**: Ctrl+S save, Ctrl+Shift+S save as, Ctrl+O open, Ctrl+N new, Ctrl+Z / Ctrl+Y undo / redo.
- **F5** play-test inside the editor (walk around your level), **F10** leave, **Ctrl+G** export.
- If the cursor highlight looks mirrored left/right, press **F9**.

## Entities

Built-in types (`entities.lua`): `player_start` (one per map), `light`, `enemy_spawn`, `pickup`, `trigger`
(size set in the inspector), `waypoint` and `prop`. They are only data: your game decides what they do.

Add your own by passing definitions shaped like the entries in `entities.lua`:

```lua
Editor.entityTypes = {
  { name = "chest", group = "Props", color = { 0.9, 0.7, 0.2 }, size = { 1, 1, 1 },
    props = { { name = "loot", kind = "string", default = "gold" } } },
}
```

`kind` is `number`, `string`, `bool` or `choice` (with `options`). `size = {w, d, h}` is the editor box
(x/y centred, z bottom); `sizeProps = {"w","d","h"}` reads the size from props instead; `unique = true` allows
one per map.

### Routes (optional)

`waypoint` entities with the same `route` prop form a path, walked in `order` (1, 2, 3...), looping back to the
first. **Any entity that has a `route` prop** is drawn linked to its route's first waypoint, so give your own
NPC types a `route` prop to use it. Route names ignore case and surrounding spaces; waypoints with the same
`order` are walked in placement order. In the editor each route is drawn as coloured lines with arrows and
numbers, and an entity whose route matches no waypoint gets a red "no waypoints" label.
In code: `mapedit.Routes.collect(map.entities)` returns the sorted routes, `Routes.xy(route)` a plain `{x, y}` list.

## Surface types (optional)

Each block type can carry a **surface** tag (saved as `surface = "..."`) that your game can read to pick a
material or texture. The editor shows it by colour only, so you can build a whole map with no art. The defaults
are Wall, Concrete, Ground, Floor and Ceiling; replace them before the editor opens:

```lua
require("map_editor").Surfaces.setTypes{
  { id = "brick", label = "Brick", color = { 0.70, 0.30, 0.25 } },
  { id = "glass", label = "Glass", color = { 0.60, 0.80, 0.90 } },
}
Editor.palette = require("map_editor").Surfaces.palette   -- new maps start with one block per type
```

## Exporting to your game

Save, then press **Export** (Ctrl+G). The map is written to `Editor.gameDir/<name>.lua` (default `levels/`).
Optional convention: keep `maps/<level>/<level>_noceiling.lua` for editing (nothing blocks the camera) and
`<level>_full.lua` for the complete level; Export then publishes the `_full` one as plain `<level>.lua`. A map
without those suffixes is exported as it is. Your game loads the exported file with `mapedit.loadLevel`.

While running unfused from a folder, maps are written straight into the project directory; in a fused game they
go to LÖVE's save directory.

## What's in the folder

```
init.lua        the public API (require "map_editor")
state.lua       the editor as a gamestate
editor.lua      tools, input, the 3D pass          panels.lua / ui.lua   the 2D panels and widgets
map.lua         data model + save/load             mesher.lua            map -> g3d models
walker.lua      first-person controller            camera.lua / raycast.lua / history.lua
entities.lua    entity types       routes.lua      route helpers        surfaces.lua   surface types
fonts/          boldpixels.ttf (the editor's UI font) + FONT_LICENSE.txt
maps/           demo.lua, test_room.lua (starter maps)
tools/          make_demo.lua, make_test_room.lua (regenerate the starter maps)
tests/          headless tests
example_main.lua   a complete main.lua showing the wiring
```

## UI font

The editor draws in **BoldPixels**, a pixel font on a 16 px grid, so text is only sharp at 16 / 32 / 48 px; the
editor uses 16 for everything and 32 for dialog titles. If the file is missing it falls back to LÖVE's default
font. To use another font set `require("map_editor.ui").FONT_PATH = "path/to/font.ttf"` before the editor opens.
BoldPixels is by YukiPixels under CC BY-SA 4.0 (credit required if you redistribute it, see `fonts/FONT_LICENSE.txt`).

## Tests

Headless, no LÖVE needed (they use stubs). Run from the project root, the folder that contains `map_editor/`:

```
lua map_editor/tests/test_core.lua      # (texlua / luajit / pandoc lua also work)
lua map_editor/tests/test_world.lua
lua map_editor/tests/test_editor.lua
```

Regenerate the starter maps with `lua map_editor/tools/make_demo.lua` and `lua map_editor/tools/make_test_room.lua`.

## Credits

Built for [g3d](https://github.com/groverburger/g3d) by groverbuger (MIT). g3d is not bundled; use your own copy.
UI font: [BoldPixels](https://yukipixels.itch.io/boldpixels) by YukiPixels (CC BY-SA 4.0).
