\# map\_editor



An in-engine \*\*voxel level editor + runtime loader\*\* for \[LÖVE](https://love2d.org) and \[g3d](https://github.com/groverburger/g3d) (Z-up). Build a level with the mouse, save it as a plain Lua file, load and draw it in your game with two lines.



It is self-contained: the UI font ships inside the folder and nothing here depends on any particular game.



\## Screenshots



| Editor Overview | Box \& Layer Locking |

| :---: | :---: |

| !\[Editor Overview](reference\_screenshots/map\_editor\_open\_1.png) | !\[Layer Lock](reference\_screenshots/map\_editor\_layer\_lock\_1.png) |

| !\[Editor Workspace](reference\_screenshots/map\_editor\_open\_2.png) | !\[Layer Lock Active](reference\_screenshots/map\_editor\_layer\_lock\_2.png) |



| Box Tool \& Sky Color | Sprite Placer \& Play-Test |

| :---: | :---: |

| !\[Box Tool](reference\_screenshots/map\_editor\_open\_box.png) | !\[Sprite Placer](reference\_screenshots/map\_editor\_sprite\_placer.png) |

| !\[Sky Color](reference\_screenshots/map\_editor\_sky\_color\_1.png) | !\[In-Editor Play-Test](reference\_screenshots/map\_editor\_play\_test\_1.png) |



| Exported Runtime Game (`loadLevel`) | Save As |

| :---: | :---: |

| !\[Exported Game Test 1](reference\_screenshots/z\_exported\_game\_test\_1.png) | !\[Save As Dialog](reference\_screenshots/map\_editor\_save\_as.png) |

| !\[Exported Game Test 2](reference\_screenshots/z\_exported\_game\_test\_2.png) | !\[Sky Color Variants](reference\_screenshots/map\_editor\_sky\_color\_2.png) |


\## Install



1\. Copy the whole `map\\\_editor/` folder next to your `main.lua`.

2\. Have g3d in your project. It is found automatically at `g3d`, `libs.g3d`, `lib.g3d`, `libraries.g3d`,

&#x20;  `vendor.g3d` or `third\\\_party.g3d`. Anywhere else: pass it in (`Editor.g3d = require "my.path.g3d"`, or

&#x20;  `Editor.new{ g3d = ... }`).

3\. Wire it up. `example\\\_main.lua` is a complete, minimal `main.lua` (F8 toggles game/editor); copy it or take the

&#x20;  pieces you need (see below).



You can rename or move the folder (e.g. `libs/map\\\_editor/`): font and map paths are worked out from where the

module was `require`d.



\## Opening the editor



`map\\\_editor/state.lua` is the editor as a gamestate table with the usual callbacks (`enter`, `update`, `draw`,

`keypressed`, `mousepressed`, ...). It has no dependencies, so it works with `hump.gamestate`:



```lua

local Editor = require "map\\\_editor.state"

Editor.onExit = function() Gamestate.switch(game) end     -- F10 / Exit button

Gamestate.switch(Editor)                                   -- or Gamestate.switch(Editor, "map\\\_editor/maps/demo.lua")


