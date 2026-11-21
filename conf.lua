function love.conf(t)
  t.identity = "map_editor_demo"   -- save folder name (maps you save from the editor land here)
  t.window.title = "map_editor demo"
  t.window.width, t.window.height = 1280, 720
  t.window.resizable = true
  t.window.vsync = 1
  -- REQUIRED for 3D: without a depth buffer hidden faces draw over visible ones.
  -- LÖVE 12 wants a boolean here, LÖVE 11 wants a bit depth.
  t.window.depth = ((love._version_major or 11) >= 12) and true or 16
end
