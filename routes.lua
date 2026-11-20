-- Routes: pure data helpers shared by the editor (route lines) and your game's map loader.
--
-- A route is the set of `waypoint` entities with the same `route` prop. An entity with a `route` prop
-- follows the waypoints of the route it names, in `order`, then loops back to the first.
--   * Names match ignoring case and surrounding spaces ("Lobby " == "lobby").
--   * Waypoints with the same `order` keep the order they were placed in the map.
--   * A waypoint with an empty route name belongs to no route and is ignored.
local Routes = {}

-- normalised name, or nil for "no route"
function Routes.key(name)
  if type(name) == "number" then name = tostring(name) end
  if type(name) ~= "string" then return nil end
  local k = name:match("^%s*(.-)%s*$"):lower()
  if k == "" then return nil end
  return k
end

-- { [key] = { name = "lobby", points = { { x, y, z, order, index, entity }, ... sorted } } }
function Routes.collect(entities)
  local routes = {}
  for i, e in ipairs(entities or {}) do
    if e.type == "waypoint" then
      local key = Routes.key(e.props and e.props.route)
      if key then
        local r = routes[key]
        if not r then
          r = { name = tostring(e.props.route):match("^%s*(.-)%s*$"), points = {} }
          routes[key] = r
        end
        r.points[#r.points + 1] = { x = e.x, y = e.y, z = e.z, order = tonumber(e.props.order) or 1, index = i, entity = e }
      end
    end
  end
  for _, r in pairs(routes) do
    table.sort(r.points, function(a, b)
      if a.order ~= b.order then return a.order < b.order end
      return a.index < b.index
    end)
  end
  return routes
end

-- the plain { {x, y}, ... } list of a route, handy for an AI's patrol path
function Routes.xy(route)
  local out = {}
  for i, p in ipairs(route.points) do out[i] = { p.x, p.y } end
  return out
end

-- a stable, readable colour per route name (r, g, b in 0..1)
function Routes.color(key)
  local h = 0
  for i = 1, #key do h = (h * 31 + key:byte(i)) % 360 end
  local s, v = 0.65, 1
  local c = v * s
  local hp = h / 60
  local x = c * (1 - math.abs(hp % 2 - 1))
  local r, g, b = 0, 0, 0
  if hp < 1 then r, g = c, x elseif hp < 2 then r, g = x, c elseif hp < 3 then g, b = c, x
  elseif hp < 4 then g, b = x, c elseif hp < 5 then r, b = x, c else r, b = c, x end
  local m = v - c
  return r + m, g + m, b + m
end

return Routes
