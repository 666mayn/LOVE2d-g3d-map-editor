-- Map data model + (de)serialisation. Works without LÖVE (for tools/tests);
-- uses love.filesystem automatically when it is present.
--
-- World is a sparse voxel grid, Z up, one unit per block. Block id 0 is air,
-- ids >= 1 index into map.palette. Blocks live in 16^3 chunks.
local floor = math.floor
local BASE = ((...) or ""):match("^(.*%.)[^.]+$") or "" -- "mapedit." when required as mapedit.map

local Map = {}
Map.__index = Map

local CS = 16
local CS2, CS3 = CS * CS, CS * CS * CS
local FORMAT, VERSION = "g3d-mapedit", 1
local LIMIT = 8000 -- |x|,|y|,|z| must stay below this

Map.CHUNK = CS
Map.LIMIT = LIMIT

local function ckey(cx, cy, cz)
  return (cx + 512) + (cy + 512) * 1024 + (cz + 512) * 1048576
end
Map.chunkKey = ckey

function Map.defaultPalette()
  local function b(name, r, g, bl, solid)
    return { name = name, color = { r, g, bl }, solid = solid }
  end
  return {
    b("grass", 0.36, 0.67, 0.30, true),
    b("dirt", 0.47, 0.33, 0.22, true),
    b("stone", 0.52, 0.53, 0.56, true),
    b("cobble", 0.38, 0.39, 0.42, true),
    b("sand", 0.86, 0.79, 0.55, true),
    b("brick", 0.67, 0.30, 0.24, true),
    b("wood", 0.55, 0.38, 0.20, true),
    b("plank", 0.75, 0.58, 0.34, true),
    b("snow", 0.94, 0.96, 0.98, true),
    b("ice", 0.62, 0.82, 0.92, true),
    b("lava", 0.95, 0.42, 0.10, true),
    { name = "water", color = { 0.20, 0.45, 0.85 }, solid = false, alpha = 0.6 },
  }
end

function Map.new(opts)
  opts = opts or {}
  return setmetatable({
    name = opts.name or "untitled",
    palette = opts.palette or Map.defaultPalette(),
    sky = opts.sky or { 0.45, 0.62, 0.85 },
    chunks = {},   -- ckey -> {cx,cy,cz,data={[idx]=id},n=count}
    count = 0,     -- total non-air blocks
    dirty = {},    -- ckey -> {cx,cy,cz}  (consumed by the mesher)
    entities = {},
    nextId = 1,
  }, Map)
end

------------------------------------------------------------------ blocks --

function Map:get(x, y, z)
  local cx, cy, cz = floor(x / CS), floor(y / CS), floor(z / CS)
  local c = self.chunks[ckey(cx, cy, cz)]
  if not c then return 0 end
  return c.data[(x - cx * CS) + (y - cy * CS) * CS + (z - cz * CS) * CS2] or 0
end

function Map:isSolid(x, y, z)
  local id = self:get(x, y, z)
  if id == 0 then return false end
  local def = self.palette[id]
  return not def or def.solid ~= false
end

function Map:markDirty(cx, cy, cz, lx, ly, lz)
  -- also dirty neighbours when the block touches a chunk border (faces + AO)
  local xs = { 0 }
  if lx == 0 then xs[#xs + 1] = -1 elseif lx == CS - 1 then xs[#xs + 1] = 1 end
  local ys = { 0 }
  if ly == 0 then ys[#ys + 1] = -1 elseif ly == CS - 1 then ys[#ys + 1] = 1 end
  local zs = { 0 }
  if lz == 0 then zs[#zs + 1] = -1 elseif lz == CS - 1 then zs[#zs + 1] = 1 end
  for _, ox in ipairs(xs) do
    for _, oy in ipairs(ys) do
      for _, oz in ipairs(zs) do
        local ax, ay, az = cx + ox, cy + oy, cz + oz
        self.dirty[ckey(ax, ay, az)] = { ax, ay, az }
      end
    end
  end
end

-- Returns true if something changed.
function Map:set(x, y, z, id)
  id = id or 0
  if x <= -LIMIT or x >= LIMIT or y <= -LIMIT or y >= LIMIT or z <= -LIMIT or z >= LIMIT then
    return false
  end
  local cx, cy, cz = floor(x / CS), floor(y / CS), floor(z / CS)
  local k = ckey(cx, cy, cz)
  local c = self.chunks[k]
  local lx, ly, lz = x - cx * CS, y - cy * CS, z - cz * CS
  local idx = lx + ly * CS + lz * CS2
  local old = c and c.data[idx] or 0
  if old == id then return false end

  if id ~= 0 then
    if not c then
      c = { cx = cx, cy = cy, cz = cz, data = {}, n = 0 }
      self.chunks[k] = c
    end
    if old == 0 then c.n = c.n + 1; self.count = self.count + 1 end
    c.data[idx] = id
  else
    c.data[idx] = nil
    c.n = c.n - 1
    self.count = self.count - 1
    if c.n == 0 then self.chunks[k] = nil end
  end

  self:markDirty(cx, cy, cz, lx, ly, lz)
  local h = self._hist
  if h then h:block(x, y, z, old, id) end
  return true
end

-- Fill the inclusive box. Returns the number of cells changed.
function Map:fillBox(x1, y1, z1, x2, y2, z2, id)
  if x1 > x2 then x1, x2 = x2, x1 end
  if y1 > y2 then y1, y2 = y2, y1 end
  if z1 > z2 then z1, z2 = z2, z1 end
  local n = 0
  for z = z1, z2 do
    for y = y1, y2 do
      for x = x1, x2 do
        if self:set(x, y, z, id) then n = n + 1 end
      end
    end
  end
  return n
end

function Map:eachBlock(fn)
  for _, c in pairs(self.chunks) do
    local ox, oy, oz = c.cx * CS, c.cy * CS, c.cz * CS
    for idx, id in pairs(c.data) do
      fn(ox + idx % CS, oy + floor(idx / CS) % CS, oz + floor(idx / CS2), id)
    end
  end
end

-- minx,miny,minz,maxx,maxy,maxz (inclusive block coords) or nil when empty
function Map:bounds()
  local x1, y1, z1, x2, y2, z2
  self:eachBlock(function(x, y, z)
    if not x1 then
      x1, y1, z1, x2, y2, z2 = x, y, z, x, y, z
    else
      if x < x1 then x1 = x elseif x > x2 then x2 = x end
      if y < y1 then y1 = y elseif y > y2 then y2 = y end
      if z < z1 then z1 = z elseif z > z2 then z2 = z end
    end
  end)
  return x1, y1, z1, x2, y2, z2
end

function Map:clear()
  for _, c in pairs(self.chunks) do
    self.dirty[ckey(c.cx, c.cy, c.cz)] = { c.cx, c.cy, c.cz }
  end
  self.chunks, self.count = {}, 0
end

-- Does the axis-aligned box overlap any solid block? (handy for game code)
function Map:boxHitsSolid(x1, y1, z1, x2, y2, z2)
  for z = floor(z1), floor(z2 - 1e-6) do
    for y = floor(y1), floor(y2 - 1e-6) do
      for x = floor(x1), floor(x2 - 1e-6) do
        if self:isSolid(x, y, z) then return true end
      end
    end
  end
  return false
end

-- Ray through the solid blocks; returns hx,hy,hz,nx,ny,nz,dist or nil.
function Map:raycast(ox, oy, oz, dx, dy, dz, maxDist)
  local R = require(BASE .. "raycast")
  local len = math.sqrt(dx * dx + dy * dy + dz * dz)
  return R.voxel(ox, oy, oz, dx / len, dy / len, dz / len, maxDist or 256,
    function(x, y, z) return self:isSolid(x, y, z) end)
end

---------------------------------------------------------------- entities --
-- Entity: { id, type, name, x, y, z, yaw (degrees), props = {k=v} }
-- Every mutator records into the open history transaction (if any).

function Map:_insertEntity(e, index)
  table.insert(self.entities, index or (#self.entities + 1), e)
end

function Map:_removeEntity(e)
  for i, o in ipairs(self.entities) do
    if o == e then table.remove(self.entities, i); return i end
  end
end

function Map:addEntity(e, index)
  e.id = e.id or self.nextId
  if e.id >= self.nextId then self.nextId = e.id + 1 end
  e.props = e.props or {}
  e.yaw = e.yaw or 0
  e.name = e.name or ""
  e.x, e.y, e.z = e.x or 0, e.y or 0, e.z or 0
  index = index or (#self.entities + 1)
  self:_insertEntity(e, index)
  local h = self._hist
  if h then
    h:op(function() self:_removeEntity(e) end,
         function() self:_insertEntity(e, index) end)
  end
  return e
end

function Map:removeEntity(e)
  local index = self:_removeEntity(e)
  if not index then return false end
  local h = self._hist
  if h then
    h:op(function() self:_insertEntity(e, index) end,
         function() self:_removeEntity(e) end)
  end
  return true
end

function Map:setEntityField(e, key, value)
  local old = e[key]
  if old == value then return end
  e[key] = value
  local h = self._hist
  if h then h:op(function() e[key] = old end, function() e[key] = value end) end
end

function Map:setEntityProp(e, key, value)
  local old = e.props[key]
  if old == value then return end
  e.props[key] = value
  local h = self._hist
  if h then
    h:op(function() e.props[key] = old end, function() e.props[key] = value end)
  end
end

function Map:findEntities(typeName)
  local out = {}
  for _, e in ipairs(self.entities) do
    if not typeName or e.type == typeName then out[#out + 1] = e end
  end
  return out
end

function Map:firstEntity(typeName)
  for _, e in ipairs(self.entities) do
    if e.type == typeName then return e end
  end
end

---------------------------------------------------------- serialisation --

local function num(v)
  if v == floor(v) and v > -1e15 and v < 1e15 then return string.format("%d", v) end
  return string.format("%.8g", v)
end

local function ser(v)
  local t = type(v)
  if t == "number" then return num(v) end
  if t == "string" then return string.format("%q", v) end
  if t == "boolean" then return tostring(v) end
  return "nil"
end

function Map:serialize()
  local out = {}
  local function add(s) out[#out + 1] = s end

  add("-- g3d-mapedit map. Edit it with the editor; load it with mapedit.Map.load().\n")
  add("return {\n")
  add(string.format("  format = %q, version = %d,\n", FORMAT, VERSION))
  add(string.format("  name = %q,\n", self.name))
  add(string.format("  sky = {%s, %s, %s},\n", num(self.sky[1]), num(self.sky[2]), num(self.sky[3])))

  add("  palette = {\n")
  for _, d in ipairs(self.palette) do
    local line = string.format("    {name = %q, color = {%s, %s, %s}, solid = %s",
      d.name, num(d.color[1]), num(d.color[2]), num(d.color[3]), tostring(d.solid ~= false))
    if d.surface then line = line .. string.format(", surface = %q", d.surface) end
    if d.alpha then line = line .. ", alpha = " .. num(d.alpha) end
    if d.uv then
      line = line .. string.format(", uv = {%s, %s, %s, %s}",
        num(d.uv[1]), num(d.uv[2]), num(d.uv[3]), num(d.uv[4]))
    end
    add(line .. "},\n")
  end
  add("  },\n")

  -- chunks: run-length encoded {count, id, count, id, ...} over idx 0..4095
  local keys = {}
  for k in pairs(self.chunks) do keys[#keys + 1] = k end
  table.sort(keys)
  add("  chunks = {\n")
  for _, k in ipairs(keys) do
    local c = self.chunks[k]
    local runs, prev, cnt = {}, nil, 0
    for i = 0, CS3 - 1 do
      local v = c.data[i] or 0
      if v == prev then
        cnt = cnt + 1
      else
        if prev then runs[#runs + 1] = cnt .. "," .. prev end
        prev, cnt = v, 1
      end
    end
    runs[#runs + 1] = cnt .. "," .. prev
    add(string.format("    {%d, %d, %d, {%s}},\n", c.cx, c.cy, c.cz, table.concat(runs, ",")))
  end
  add("  },\n")

  add("  entities = {\n")
  for _, e in ipairs(self.entities) do
    local pk = {}
    for k in pairs(e.props) do pk[#pk + 1] = k end
    table.sort(pk)
    local props = {}
    for _, k in ipairs(pk) do
      props[#props + 1] = string.format("[%q] = %s", k, ser(e.props[k]))
    end
    add(string.format("    {type = %q, name = %q, x = %s, y = %s, z = %s, yaw = %s, props = {%s}},\n",
      e.type, e.name or "", num(e.x), num(e.y), num(e.z), num(e.yaw or 0), table.concat(props, ", ")))
  end
  add("  },\n")
  add("}\n")
  return table.concat(out)
end

-- Evaluate a Lua source string with an empty environment (data only).
local function sandboxLoad(str, chunkname)
  if setfenv then -- Lua 5.1 / LuaJIT (what LÖVE ships)
    local f, err = loadstring(str, chunkname)
    if not f then return nil, err end
    setfenv(f, {})
    return f
  end
  return load(str, chunkname, "t", {})
end

local function isnum(v) return type(v) == "number" and v == v end

function Map.deserialize(str, name)
  local f, err = sandboxLoad(str, "=" .. (name or "map"))
  if not f then return nil, err end
  local ok, t = pcall(f)
  if not ok then return nil, t end
  if type(t) ~= "table" or t.format ~= FORMAT then return nil, "not a " .. FORMAT .. " file" end
  if (t.version or 1) > VERSION then return nil, "map was saved by a newer editor version" end

  local m = Map.new({ name = tostring(t.name or name or "untitled") })
  if type(t.sky) == "table" and isnum(t.sky[1]) and isnum(t.sky[2]) and isnum(t.sky[3]) then
    m.sky = { t.sky[1], t.sky[2], t.sky[3] }
  end

  if type(t.palette) == "table" and #t.palette > 0 then
    m.palette = {}
    for i, d in ipairs(t.palette) do
      local c = type(d.color) == "table" and d.color or {}
      local def = {
        name = tostring(d.name or ("block" .. i)),
        color = { tonumber(c[1]) or 1, tonumber(c[2]) or 1, tonumber(c[3]) or 1 },
        solid = d.solid ~= false,
      }
      if type(d.surface) == "string" and d.surface ~= "" then def.surface = d.surface end
      if isnum(d.alpha) then def.alpha = d.alpha end
      if type(d.uv) == "table" and #d.uv == 4 then def.uv = { d.uv[1], d.uv[2], d.uv[3], d.uv[4] } end
      m.palette[i] = def
    end
  end

  for _, ch in ipairs(t.chunks or {}) do
    local cx, cy, cz, runs = ch[1], ch[2], ch[3], ch[4]
    if isnum(cx) and isnum(cy) and isnum(cz) and type(runs) == "table" then
      local data, n, idx = {}, 0, 0
      for i = 1, #runs, 2 do
        local cnt, id = runs[i], runs[i + 1]
        if not (isnum(cnt) and isnum(id)) then return nil, "corrupt chunk data" end
        if id ~= 0 then
          for j = idx, math.min(idx + cnt, CS3) - 1 do data[j] = id; n = n + 1 end
        end
        idx = idx + cnt
      end
      if n > 0 then
        m.chunks[ckey(cx, cy, cz)] = { cx = cx, cy = cy, cz = cz, data = data, n = n }
        m.count = m.count + n
        m.dirty[ckey(cx, cy, cz)] = { cx, cy, cz }
      end
    end
  end

  for _, e in ipairs(t.entities or {}) do
    if type(e) == "table" and type(e.type) == "string" then
      local props = {}
      if type(e.props) == "table" then
        for k, v in pairs(e.props) do
          local tv = type(v)
          if type(k) == "string" and (tv == "number" or tv == "string" or tv == "boolean") then
            props[k] = v
          end
        end
      end
      m:addEntity({
        type = e.type, name = tostring(e.name or ""),
        x = tonumber(e.x) or 0, y = tonumber(e.y) or 0, z = tonumber(e.z) or 0,
        yaw = tonumber(e.yaw) or 0, props = props,
      })
    end
  end
  return m
end

------------------------------------------------------------------ files --

function Map.readFile(path)
  if love and love.filesystem and love.filesystem.getInfo(path) then
    return (love.filesystem.read(path))
  end
  local f = io.open(path, "rb")
  if f then
    local s = f:read("*a")
    f:close()
    return s
  end
  return nil, "cannot read " .. path
end

-- While developing (running unfused from a folder) save straight into the
-- project directory so the game picks the file up. Falls back to LÖVE's save
-- directory. Returns ok, where-it-went-or-error.
Map.writeToSource = true

-- make the folder of `full` (an absolute path) if it is missing. Plain os.execute, so no extra library is needed.
local function ensureDir(full)
  local dir = full:match("^(.*)[/\\][^/\\]*$")
  if not dir or dir == "" then return end
  local f = io.open(dir .. "/.mapdir_probe", "wb")
  if f then f:close(); os.remove(dir .. "/.mapdir_probe"); return end   -- already exists
  local win = package.config:sub(1, 1) == "\\"
  pcall(os.execute, win and ('mkdir "' .. dir:gsub("/", "\\") .. '" >nul 2>nul') or ('mkdir -p "' .. dir .. '"'))
end

function Map.writeFile(path, str)
  if love and love.filesystem then
    if Map.writeToSource and not love.filesystem.isFused() then
      local src = love.filesystem.getSource()
      if src then
        ensureDir(src .. "/" .. path)
        local f = io.open(src .. "/" .. path, "wb")
        if f then
          f:write(str)
          f:close()
          return true, src .. "/" .. path
        end
      end
    end
    local dir = path:match("^(.*)/[^/]*$")
    if dir then love.filesystem.createDirectory(dir) end
    local ok, err = love.filesystem.write(path, str)
    if ok then return true, love.filesystem.getSaveDirectory() .. "/" .. path end
    return false, err
  end
  ensureDir(path)
  local f, err = io.open(path, "wb")
  if not f then return false, err end
  f:write(str)
  f:close()
  return true, path
end

function Map.load(path)
  local s, err = Map.readFile(path)
  if not s then return nil, err end
  return Map.deserialize(s, path:match("([^/]+)%.lua$") or path)
end

function Map:save(path)
  return Map.writeFile(path, self:serialize())
end

return Map
