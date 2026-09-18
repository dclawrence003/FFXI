-- Pure position, bearing, and waypoint-path helpers.

local Navigation = {}
local PI = math.pi
local TWO_PI = PI * 2

local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 and y >= 0 then return math.atan(y / x) + PI end
    if x < 0 and y < 0 then return math.atan(y / x) - PI end
    if x == 0 and y > 0 then return PI / 2 end
    if x == 0 and y < 0 then return -PI / 2 end
    return 0
end

function Navigation.normalize_angle(value)
    value = tonumber(value) or 0
    while value > PI do value = value - TWO_PI end
    while value <= -PI do value = value + TWO_PI end
    return value
end

function Navigation.distance(from, destination)
    if type(from) ~= 'table' or type(destination) ~= 'table'
        or not tonumber(from.x) or not tonumber(from.y)
        or not tonumber(destination.x) or not tonumber(destination.y) then
        return nil, nil
    end
    local dx = destination.x - from.x
    local dy = destination.y - from.y
    local dz = (tonumber(destination.z) or tonumber(from.z) or 0)
        - (tonumber(from.z) or tonumber(destination.z) or 0)
    return math.sqrt(dx * dx + dy * dy), dz
end

-- Windower faces a point with -atan2(delta_y, delta_x).  Returning the same
-- convention lets the desired heading be compared directly to mob.facing.
function Navigation.heading(from, destination)
    if type(from) ~= 'table' or type(destination) ~= 'table'
        or not tonumber(from.x) or not tonumber(from.y)
        or not tonumber(destination.x) or not tonumber(destination.y) then
        return nil
    end
    return Navigation.normalize_angle(-atan2(
        destination.y - from.y, destination.x - from.x))
end

function Navigation.relative_heading(from, destination, facing)
    local desired = Navigation.heading(from, destination)
    facing = tonumber(facing)
    if not desired or not facing then return nil end
    return Navigation.normalize_angle(desired - facing)
end

local ARROWS = {'^', '/^', '>', '\\v', 'v', 'v/', '<', '^\\'}
local WORDS = {'ahead', 'ahead-right', 'right', 'back-right', 'behind',
    'back-left', 'left', 'ahead-left'}

function Navigation.arrow(relative)
    relative = Navigation.normalize_angle(relative)
    local index = math.floor((relative + PI / 8) / (PI / 4)) % 8 + 1
    return ARROWS[index], WORDS[index], index
end

-- Frame one points straight ahead. Positive relative headings turn clockwise
-- on screen, matching the pre-rendered arrow frame order.
function Navigation.frame(relative, frame_count)
    frame_count = math.max(1, math.floor(tonumber(frame_count) or 32))
    relative = Navigation.normalize_angle(relative)
    local sector = TWO_PI / frame_count
    return math.floor((relative + sector / 2) / sector) % frame_count + 1
end

function Navigation.resolve_landmark(landmark_id, landmarks, overrides)
    local source = overrides and overrides[landmark_id]
        or landmarks and landmarks[landmark_id]
    if type(source) ~= 'table' then return nil end
    if not tonumber(source.x) or not tonumber(source.y) then return nil end
    return {
        id = landmark_id,
        name = source.name or landmark_id,
        x = tonumber(source.x), y = tonumber(source.y), z = tonumber(source.z),
        radius = tonumber(source.radius) or 5,
        z_tolerance = tonumber(source.z_tolerance) or 12,
        confidence = source.confidence or 'unknown',
        cue = type(source.cue) == 'string' and source.cue or '',
    }
end

function Navigation.current_waypoint(step, waypoint_index, landmarks, overrides)
    if type(step) ~= 'table' then return nil end
    local path = step.path
    local id = type(path) == 'table' and path[tonumber(waypoint_index) or 1]
        or step.waypoint
    if not id then return nil end
    return Navigation.resolve_landmark(id, landmarks, overrides)
end

-- A waypoint is advanced only after remaining inside its radius for the dwell
-- interval.  Leaving radius resets the observation, which prevents boundary
-- oscillation from skipping turns.
function Navigation.observe_waypoint(tracker, position, waypoint, now, dwell)
    tracker = tracker or {}
    now = tonumber(now) or os.clock()
    dwell = tonumber(dwell) or 0.6
    local distance, dz
    if waypoint then distance, dz = Navigation.distance(position, waypoint) end
    local wrong_layer = waypoint and waypoint.z ~= nil and dz ~= nil
        and math.abs(dz) > (tonumber(waypoint.z_tolerance) or 12)
    if not distance or distance > waypoint.radius or wrong_layer then
        tracker.id, tracker.entered_at = nil, nil
        return false, tracker, distance
    end
    if tracker.id ~= waypoint.id then
        tracker.id, tracker.entered_at = waypoint.id, now
        return false, tracker, distance
    end
    return now - (tracker.entered_at or now) >= dwell, tracker, distance
end

return Navigation
