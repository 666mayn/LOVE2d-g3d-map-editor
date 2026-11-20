# map_editor

An in-engine **voxel level editor + runtime loader** for [LÖVE](https://love2d.org) and [g3d](https://github.com/groverburger/g3d) (Z-up). Build a level with the mouse, save it as a plain Lua file, load and draw it in your game with two lines.

It is self-contained: the UI font ships inside the folder and nothing here depends on any particular game.

## Screenshots

| Editor Overview | Box & Layer Locking |
| :---: | :---: |
| ![Editor Overview](reference_screenshots/map_editor_open_1.png) | ![Layer Lock](reference_screenshots/map_editor_layer_lock_1.png) |
| ![Editor Workspace](reference_screenshots/map_editor_open_2.png) | ![Layer Lock Active](reference_screenshots/map_editor_layer_lock_2.png) |

| Box Tool & Sky Color | Sprite Placer & Play-Test |
| :---: | :---: |
| ![Box Tool](reference_screenshots/map_editor_open_box.png) | ![Sprite Placer](reference_screenshots/map_editor_sprite_placer.png) |
| ![Sky Color](reference_screenshots/map_editor_sky_color_1.png) | ![In-Editor Play-Test](reference_screenshots/map_editor_play_test_1.png) |

| Exported Runtime Game (`loadLevel`) | Save As |
| :---: | :---: |
| ![Exported Game Test 1](reference_screenshots/z_exported_game_test_1.png) | ![Save As Dialog](reference_screenshots/map_editor_save_as.png) |
| ![Exported Game Test 2](reference_screenshots/z_exported_game_test_2.png) | ![Sky Color Variants](reference_screenshots/map_editor_sky_color_2.png) |