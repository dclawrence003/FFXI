_addon.name = 'FastFollow'
_addon.author = 'DiscipleOfEris'
_addon.version = '1.2.4-safezone'
_addon.commands = {'fastfollow', 'ffo'}

-- TODO: pause on ranged attacks.

require('strings')
require('tables')
require('sets')
require('coroutine')
packets = require('packets')
res = require('resources')
spells = require('spell_cast_times')
items = res.items
config = require('config')
texts = require('texts')
require('logger')
require('strings')
local socket = require('socket')

-- PartyOps-owned P4 passive observer. Failures are deliberately ignored so
-- observation can never change FastFollow movement behavior.
local partyops_trace = nil
local partyops_trace_moving = false
local partyops_state_last = nil
local partyops_state_last_at = 0
local partyops_state_heartbeat_seconds = 15
do
  local ok, module = pcall(require, 'partyops_trace')
  if ok then
    partyops_trace = module
    pcall(partyops_trace.initialize_executor_pause,
      'fastfollow', 'follower_movement')
  end
end
local partyops_pause_work_generation = 0

defaults = {}
defaults.show = false
defaults.min = 0.5
defaults.zone_poke = 1.0
defaults.display = {}
defaults.display.pos = {}
defaults.display.pos.x = 0
defaults.display.pos.y = 0
defaults.display.bg = {}
defaults.display.bg.red = 0
defaults.display.bg.green = 0
defaults.display.bg.blue = 0
defaults.display.bg.alpha = 102
defaults.display.text = {}
defaults.display.text.font = 'Consolas'
defaults.display.text.red = 255
defaults.display.text.green = 255
defaults.display.text.blue = 255
defaults.display.text.alpha = 255
defaults.display.text.size = 10

settings = config.load(defaults)
box = texts.new("", settings.display, settings)

follow_me = 0
following = false
target = nil
last_target = nil
min_dist = settings.min^2
max_dist = 50.0^2
spell_dist = 20.4^2
repeated = false
running = false
casting = nil
cast_time = 0
pause_delay = 0.1
pause_dismount_delay = 0.5
pauseon = S{}
co = nil
tracking = false

local render_interval = 0.05
local next_render_at = 0
local position_heartbeat_seconds = 0.5
local position_epsilon_squared = 0.01 * 0.01
local last_position_broadcast = nil
local last_run_x = nil
local last_run_y = nil
local box_last_visible = nil
local box_last_text = nil
local zone_nudge_duration = math.min(
  math.max(tonumber(settings.zone_poke) or 1.0, 0), 3.0)
local zone_signal_max_age = 4.0
local zone_signal_future_tolerance = 1.0
local zone_approach_timeout = 3.0
local zone_cross_distance_squared = 1.0^2
local zone_signal_sequence = 0
local zone_signal_session = tostring(math.floor(socket.gettime() * 1000))
local active_zone_nudge = nil
local seen_zone_signals = {}
local last_motion_x = nil
local last_motion_y = nil
local trace_character = nil

local function wall_time()
  return socket.gettime()
end

local function zone_trace(event, detail)
  pcall(function()
    local player = windower.ffxi.get_player()
    if player and player.name then trace_character = player.name end
    if not trace_character then return end

    local safe_name = trace_character:gsub('[^%w_-]', '_')
    local path = windower.windower_path
        .. 'addons\\FastFollow\\data\\zone_trace_'
        .. safe_name .. '.log'
    local now = wall_time()
    local seconds = math.floor(now)
    local milliseconds = math.floor((now - seconds) * 1000)
    local value = tostring(detail or ''):gsub('[\r\n]', ' ')
    local file = io.open(path, 'a')
    if not file then return end
    file:write(('%s.%03d|%s|%s\n'):format(
      os.date('%Y-%m-%d %H:%M:%S', seconds),
      milliseconds,
      tostring(event),
      value))
    file:close()
  end)
end

local function set_box_visible(visible)
  visible = not not visible
  if box_last_visible ~= visible then
    box:visible(visible)
    box_last_visible = visible
  end
end

local function stop_running()
  if running then windower.ffxi.run(false) end
  running = false
  last_run_x = nil
  last_run_y = nil
end

local function run_direction(x, y)
  if not running or not last_run_x
      or math.abs(x - last_run_x) > 0.01
      or math.abs(y - last_run_y) > 0.01 then
    windower.ffxi.run(x, y)
    last_run_x = x
    last_run_y = y
  end
  running = true
end

local function cancel_zone_nudge(reason)
  if not active_zone_nudge then return end
  zone_trace('nudge-cancel', ('token=%s reason=%s'):format(
    tostring(active_zone_nudge.token), tostring(reason)))
  active_zone_nudge = nil
  partyops_trace_moving = false
  stop_running()
end

local function receive_zone_signal(args)
  local leader = args[1]
  if not following or leader ~= following then return end

  local source_zone = tonumber(args[2])
  local source_x = tonumber(args[3])
  local source_y = tonumber(args[4])
  local motion_x = tonumber(args[5])
  local motion_y = tonumber(args[6])
  local issued_at = tonumber(args[7])
  local token = args[8]
  if not source_zone or not source_x or not source_y
      or not motion_x or not motion_y or not issued_at or not token then
    zone_trace('signal-reject', 'reason=malformed')
    return
  end

  if seen_zone_signals[leader] == token then
    zone_trace('signal-reject', ('token=%s reason=duplicate'):format(token))
    return
  end
  seen_zone_signals[leader] = token

  local now = wall_time()
  local age = now - issued_at
  if age > zone_signal_max_age or age < -zone_signal_future_tolerance then
    zone_trace('signal-reject', ('token=%s reason=stale age=%.3f'):format(
      token, age))
    return
  end

  local self = windower.ffxi.get_mob_by_target('me')
  local info = windower.ffxi.get_info()
  if not self or not info then
    zone_trace('signal-reject', ('token=%s reason=no-player'):format(token))
    return
  end
  if info.zone ~= source_zone then
    zone_trace('signal-reject',
      ('token=%s reason=source-zone current=%s source=%s'):format(
        token, tostring(info.zone), tostring(source_zone)))
    return
  end
  if zone_nudge_duration <= 0 then
    zone_trace('signal-reject', ('token=%s reason=disabled'):format(token))
    return
  end

  local dx = source_x - self.x
  local dy = source_y - self.y
  local distance_squared = dx * dx + dy * dy
  if distance_squared >= max_dist then
    zone_trace('signal-reject', ('token=%s reason=distance distance=%.3f'):format(
      token, math.sqrt(distance_squared)))
    return
  end

  cancel_zone_nudge('superseded')
  active_zone_nudge = {
    leader = leader,
    source_zone = source_zone,
    source_x = source_x,
    source_y = source_y,
    motion_x = motion_x,
    motion_y = motion_y,
    token = token,
    approach_deadline = now + zone_approach_timeout,
    cross_until = nil,
    direction_x = nil,
    direction_y = nil,
  }
  zone_trace('signal-accept',
    ('token=%s source=%d distance=%.3f age=%.3f'):format(
      token, source_zone, math.sqrt(distance_squared), age))
end

local function tick_zone_nudge(self, info, now)
  local nudge = active_zone_nudge
  if not nudge then return false end
  if not following or following ~= nudge.leader then
    cancel_zone_nudge('leader-changed')
    return true
  end
  if info.zone ~= nudge.source_zone then
    cancel_zone_nudge('source-zone-left')
    return true
  end

  local dx = nudge.source_x - self.x
  local dy = nudge.source_y - self.y
  local distance_squared = dx * dx + dy * dy
  if not nudge.cross_until then
    if now > nudge.approach_deadline then
      cancel_zone_nudge('approach-timeout')
      return true
    end

    if distance_squared > zone_cross_distance_squared then
      local length = math.sqrt(distance_squared)
      nudge.direction_x = dx / length
      nudge.direction_y = dy / length
    else
      local motion_length_squared = nudge.motion_x * nudge.motion_x
          + nudge.motion_y * nudge.motion_y
      if motion_length_squared > 0.0001 then
        local motion_length = math.sqrt(motion_length_squared)
        nudge.direction_x = nudge.motion_x / motion_length
        nudge.direction_y = nudge.motion_y / motion_length
      elseif not nudge.direction_x and distance_squared > 0.0001 then
        local length = math.sqrt(distance_squared)
        nudge.direction_x = dx / length
        nudge.direction_y = dy / length
      elseif not nudge.direction_x and last_run_x then
        nudge.direction_x = last_run_x
        nudge.direction_y = last_run_y
      end

      if not nudge.direction_x then
        cancel_zone_nudge('direction-unavailable')
        return true
      end
      nudge.cross_until = now + zone_nudge_duration
      zone_trace('nudge-cross', ('token=%s duration=%.3f'):format(
        nudge.token, zone_nudge_duration))
    end
  elseif now >= nudge.cross_until then
    cancel_zone_nudge('cross-timeout')
    return true
  end

  run_direction(nudge.direction_x, nudge.direction_y)
  return true
end

local function broadcast_position(self, info, now)
  local should_send = not last_position_broadcast
      or last_position_broadcast.zone ~= info.zone
      or distanceSquared(last_position_broadcast, self) > position_epsilon_squared
      or now - last_position_broadcast.at >= position_heartbeat_seconds
  if not should_send then return end

  if last_position_broadcast and last_position_broadcast.zone == info.zone then
    local dx = self.x - last_position_broadcast.x
    local dy = self.y - last_position_broadcast.y
    if dx * dx + dy * dy > position_epsilon_squared then
      last_motion_x = dx
      last_motion_y = dy
    end
  elseif last_position_broadcast then
    last_motion_x = nil
    last_motion_y = nil
  end
  windower.send_ipc_message(
    ('update %s %s %s %s'):format(self.name, info.zone, self.x, self.y))
  last_position_broadcast = {
    x = self.x,
    y = self.y,
    zone = info.zone,
    at = now,
  }
end

track_info = T{}

windower.register_event('unload', function()
  windower.send_command('ffo stop')
  coroutine.sleep(0.25) -- Reduce crash on reload, since Windower seems to crash if IPC messages are received as it's restarting.
end)

windower.register_event('addon command', function(command, ...)
  command = command and command:lower() or nil
  args = T{...}
  
  if not command then
    log('Provide a name to follow, or "me" to make others follow you.')
    log('Stop following with "stop" on a single character, or "stopall" on all characters.')
    log('Can configure auto-pausing with pauseon|pausedelay commands.')
  elseif command == 'followme' or command == 'me' then
    self = windower.ffxi.get_mob_by_target('me')
    if not self and not repeated then
      repeated = true
      windower.send_command('@wait 1; ffo followme')
      return
    end
    
    repeated = false
    windower.send_ipc_message('follow '..self.name)
    windower.send_ipc_message('track '..(settings.show and 'on' or 'off'))
  elseif command == 'stop' then
    if following then windower.send_ipc_message('stopfollowing '..following) end
    following = false
    tracking = false
    cancel_zone_nudge('command-stop')
    stop_running()
  elseif command == 'stopall' then
    follow_me = 0
    following = false
    tracking = false
    cancel_zone_nudge('command-stopall')
    stop_running()
    windower.send_ipc_message('stop')
  elseif command == 'follow' then
    if #args == 0 then
      return windower.add_to_chat(0, 'FastFollow: You must provide a player name to follow.')
    end
    cancel_zone_nudge('command-follow')
    casting = nil
    following = args[1]:lower()
    windower.send_ipc_message('following '..following)
    windower.ffxi.follow()
  elseif command == 'pauseon' then
    if #args == 0 then
      return windower.add_to_chat(0, 'FastFollow: To change pausing behavior, provide spell|item|any to pauseon.')
    end
    
    local arg = args[1]:lower()
    if arg == 'spell' or arg == 'any' then
      if pauseon:contains('spell') then pauseon:remove('spell')
      else pauseon:add('spell') end
    end
    if arg == 'item' or arg == 'any' then
      if pauseon:contains('item') then pauseon:remove('item')
      else pauseon:add('item') end
    end
    if arg == 'dismount' or arg == 'any' then
      if pauseon:contains('dismount') then pauseon:remove('dismount')
      else pauseon:add('dismount') end
    end
    
    windower.add_to_chat(0, 'FastFollow: Pausing on Spell: '..tostring(pauseon:contains('spell'))..', Item: '..tostring(pauseon:contains('item')))
    -- TODO: Save settings.
  elseif command == 'pausedelay' then
    pause_delay = tonumber(args[1])
    windower.add_to_chat(0, 'FastFollow: Setting item/spell pause delay to '..tostring(pause_delay)..' seconds.')
  elseif command == 'status' then
    windower.add_to_chat(158,
      ('[FastFollow] v%s; safe movement-only zoning is enabled.'):format(
        _addon.version))
  elseif command == 'info' then
    if not args[1] then
      settings.show = not settings.show
    elseif args[1] == 'on' then
      settings.show = true
    elseif args[1] == 'off' then
      settings.show = false
    end
    
    windower.send_ipc_message('track '..(settings.show and 'on' or 'off'))
    
    config.save(settings)
  elseif command == 'min' then
    local dist = tonumber(args[1])
    if not dist then return end
    
    dist = math.min(math.max(0.2, dist), 50.0)
    
    settings.min = dist
    min_dist = settings.min^2
    config.save(settings)
  elseif command == 'zone' then
    local duration = tonumber(args[1])
    if not duration then
      return windower.add_to_chat(0,
        'FastFollow: Zone nudge duration must be a number from 0 to 3 seconds.')
    end
    zone_nudge_duration = math.min(math.max(duration, 0), 3.0)
    settings.zone_poke = zone_nudge_duration
    config.save(settings)
    windower.add_to_chat(0,
      ('FastFollow: Safe zone nudge duration set to %.2f seconds.'):format(
        zone_nudge_duration))
  elseif command and #args == 0 then
    windower.send_command('ffo follow '..command)
  end
end)

windower.register_event('ipc message', function(msgStr)
  local args = msgStr:lower():split(' ')
  local command = args:remove(1)
  
  if command == 'stop' then
    follow_me = 0
    following = false
    tracking = false
    cancel_zone_nudge('ipc-stop')
    stop_running()
  elseif command == 'follow' then
    if following then windower.send_ipc_message('stopfollowing '..following) end
    cancel_zone_nudge('ipc-follow')
    following = args[1]
    casting = nil
    target_pos = nil
    last_target_pos = nil
    windower.send_ipc_message('following '..following)
    windower.ffxi.follow()
  elseif command == 'following' then
    self = windower.ffxi.get_player()
    if not self or self.name:lower() ~= args[1] then return end
    follow_me = follow_me + 1
  elseif command == 'stopfollowing' then
    self = windower.ffxi.get_player()
    if not self or self.name:lower() ~= args[1] then return end
    follow_me = math.max(follow_me - 1, 0)
  elseif command == 'update' then
    local pos = {x=tonumber(args[3]), y=tonumber(args[4])}
    track_info[args[1]] = pos
    
    if not following or args[1] ~= following then return end
    
    target = {x=pos.x, y=pos.y, zone=tonumber(args[2])}
    
    if not last_target then last_target = target end
    
     if target.zone ~= -1 and (target.x ~= last_target.x or target.y ~= last_target.y or target.zone ~= last_target.zone) then
      last_target = target
    end
  elseif command == 'zonewalk' then
    receive_zone_signal(args)
  elseif command == 'track' then
    tracking = args[1] == 'on' and true or false
  end
end)

windower.register_event('prerender', function()
  local now = os.clock()
  if now < next_render_at then return end
  next_render_at = now + render_interval

  updateInfo()

  local partyops_state = 0
  if partyops_trace then
    if follow_me > 0 then
      partyops_state = 1
    elseif following then
      partyops_state = partyops_trace_moving and 3 or 2
    end
    local partyops_now = now
    if partyops_state_last ~= partyops_state
        or partyops_now - partyops_state_last_at
            >= partyops_state_heartbeat_seconds then
      local ok, sent = pcall(partyops_trace.movement,
        'decision', 'executor_command', partyops_state)
      if ok and sent then
        partyops_state_last = partyops_state
        partyops_state_last_at = partyops_now
      end
    end
  end
  local partyops_selection_allowed = true
  if partyops_trace and partyops_trace.executor_pause_tick then
    local ok, allowed = pcall(
      partyops_trace.executor_pause_tick,
      'fastfollow',
      'follower_movement',
      partyops_state,
      partyops_trace_moving,
      partyops_pause_work_generation,
      false)
    partyops_selection_allowed = ok and allowed == true
  end
  if not partyops_selection_allowed and following then
    if partyops_trace_moving and partyops_trace then
      pcall(partyops_trace.movement,
        'stopped', 'executor_command', 0)
    end
    partyops_trace_moving = false
    stop_running()
    return
  end
  
  if follow_me <= 0 and not following then return end
  
  if follow_me > 0 then
    local self = windower.ffxi.get_mob_by_target('me')
    local info = windower.ffxi.get_info()
    
    if not self or not info then return end
    
    broadcast_position(self, info, now)
  elseif following then
    local self = windower.ffxi.get_mob_by_target('me')
    local info = windower.ffxi.get_info()
    
    if not self or not info then return end
    
    if tracking then
      broadcast_position(self, info, now)
    end
    
    if casting then
      if partyops_trace_moving and partyops_trace then
        pcall(partyops_trace.movement, 'stopped', 'casting_pause', 0)
      end
      partyops_trace_moving = false
      stop_running()
      return
    end

    if active_zone_nudge then
      local was_moving = partyops_trace_moving
      local handled = tick_zone_nudge(self, info, wall_time())
      partyops_trace_moving = active_zone_nudge ~= nil and running
      if partyops_trace_moving and not was_moving then
        partyops_pause_work_generation = partyops_pause_work_generation + 1
        if partyops_trace then
          pcall(partyops_trace.movement, 'selected', 'distance_window', 0)
        end
      elseif was_moving and not partyops_trace_moving and partyops_trace then
        pcall(partyops_trace.movement, 'stopped', 'target_unavailable', 0)
      end
      if handled then return end
    end
    if not target then
      if running then
        if partyops_trace_moving and partyops_trace then
          pcall(partyops_trace.movement, 'stopped', 'target_unavailable', 0)
        end
        partyops_trace_moving = false
        stop_running()
      end
      return
    end

    local distSq = distanceSquared(target, self)
    local len = math.sqrt(distSq)
    if len < 1 then len = 1 end
    
    if target.zone == info.zone and distSq > min_dist and distSq < max_dist then
      if not partyops_trace_moving then
        partyops_pause_work_generation =
          partyops_pause_work_generation + 1
        if partyops_trace then
          pcall(partyops_trace.movement, 'selected', 'distance_window',
            math.floor(len * 10))
        end
      end
      partyops_trace_moving = true
      run_direction((target.x - self.x)/len, (target.y - self.y)/len)
    elseif target.zone == info.zone and distSq <= min_dist then
      if partyops_trace_moving and partyops_trace then
        pcall(partyops_trace.movement, 'stopped', 'target_reached', 0)
      end
      partyops_trace_moving = false
      stop_running()
    elseif running then
      if partyops_trace_moving and partyops_trace then
        pcall(partyops_trace.movement, 'stopped', 'target_unavailable', 0)
      end
      partyops_trace_moving = false
      stop_running()
    end
  end
end)

local PACKET_OUT = { ACTION = 0x01A, USE_ITEM = 0x037, REQUEST_ZONE = 0x05E }
local PACKET_ACTION_CATEGORY = { MAGIC_CAST = 0x03, DISMOUNT = 0x12 }
local EVENT_ACTION_CATEGORY = { SPELL_FINISH = 4, ITEM_FINISH = 5, SPELL_BEGIN_OR_INTERRUPT = 8, ITEM_BEGIN_OR_INTERRUPT = 9 }
local EVENT_ACTION_PARAM = { BEGIN = 24931, INTERRUPT = 28787 }

windower.register_event('outgoing chunk', function(id, original, modified, injected, blocked)
  if blocked then return end
  
  if id == PACKET_OUT.REQUEST_ZONE then
    local self = windower.ffxi.get_mob_by_target('me')
    local info = windower.ffxi.get_info()
    if not injected and follow_me > 0 and self and info
        and tonumber(info.zone) and tonumber(self.x) and tonumber(self.y) then
      zone_signal_sequence = zone_signal_sequence + 1
      local token = zone_signal_session .. '-' .. tostring(zone_signal_sequence)
      local issued_at = wall_time()
      windower.send_ipc_message(
        ('zonewalk %s %d %.6f %.6f %.6f %.6f %.3f %s'):format(
          self.name,
          info.zone,
          self.x,
          self.y,
          last_motion_x or 0,
          last_motion_y or 0,
          issued_at,
          token))
      zone_trace('signal-send',
        ('token=%s source=%d x=%.3f y=%.3f'):format(
          token, info.zone, self.x, self.y))
    end

    if not injected and following then
      zone_trace('natural-request',
        ('source=%s nudge=%s'):format(
          info and tostring(info.zone) or 'unknown',
          active_zone_nudge and active_zone_nudge.token or 'none'))
      cancel_zone_nudge('natural-zone-request')
    end
    -- Never block, copy, synthesize, or inject a zone request. The game owns
    -- the destination selection; FastFollow only supplies a brief movement
    -- nudge toward the leader's source-zone coordinates.
  elseif id == PACKET_OUT.ACTION and not casting then
    if not pauseon:contains('spell') and not pauseon:contains('dismount') then return end
    
    local packet = packets.parse('outgoing', modified)
    if packet.Category ~= PACKET_ACTION_CATEGORY.MAGIC_CAST and packet.CATEGORY ~= PACKET_ACTION_CATEGORY.DISMOUNT then return end
    if packet.Category == PACKET_ACTION_CATEGORY.MAGIC_CAST and not pauseon:contains('spell') then return end
    if packet.Category == PACKET_ACTION_CATEGORY.DISMOUNT and not pauseon:contains('dismount') then return end
    
    local cast_attempt = os.clock()
    casting = cast_attempt
    if pause_delay <= 0 then return end
    
    windower.ffxi.run(false)
    running = false
    coroutine.schedule(function()
      packets.inject(packet)
    end, pause_delay)
    
    local delay = pause_dismount_delay
    if packet.Category == PACKET_ACTION_CATEGORY.MAGIC_CAST then
      -- TODO: Maybe get a little smarter, such as checking if the target is within range, we have sufficient mp, etc.
      local spell = spells[packet.Param]
      delay = spell.cast_time + 0.5
    end
    
    if co then coroutine.close(co) end
    co = coroutine.schedule(function()
      if casting and not (casting > cast_attempt) then
        casting = false
      end
    end, pause_delay+0.5)
    
    return true
  elseif id == PACKET_OUT.USE_ITEM and not casting then
    if not pauseon:contains('item') then return end
    
    casting = os.time()
    if pause_delay <= 0 then return end
    
    local packet = packets.parse('outgoing', modified)
    
    local item = items[packet.Param]
    if not item or not item.cast_time then return end
    
    local cast_time = os.time()
    casting = cast_time
    
    coroutine.schedule(function()
      packets.inject(packets.parse('outgoing', modified))
    end, pause_delay)
    
    if co then coroutine.close(co) end
    co = coroutine.schedule(function()
      if casting ~= cast_time then return end
      casting = false
    end, pause_delay+item.cast_time)
    
    return true
  end
end)

windower.register_event('zone change', function(new_zone, old_zone)
  zone_trace('zone-change', ('old=%s new=%s nudge=%s'):format(
    tostring(old_zone), tostring(new_zone),
    active_zone_nudge and active_zone_nudge.token or 'none'))
  cancel_zone_nudge('zone-change')
  stop_running()
  target = nil
  last_target = nil
  last_position_broadcast = nil
  last_motion_x = nil
  last_motion_y = nil
end)

windower.register_event('action', function(action)
  local player = windower.ffxi.get_player()
  if not player or action.actor_id ~= player.id then return end

  if action.category == EVENT_ACTION_CATEGORY.SPELL_FINISH or (action.category == EVENT_ACTION_CATEGORY.SPELL_BEGIN_OR_INTERRUPT and action.param == EVENT_ACTION_PARAM.INTERRUPT) then
    casting = false
  elseif action.category == EVENT_ACTION_CATEGORY.ITEM_FINISH or (action.category == EVENT_ACTION_CATEGORY.ITEM_BEGIN_OR_INTERRUPT and action.param == EVENT_ACTION_PARAM.INTERRUPT) then
    casting = false
  elseif action.category == EVENT_ACTION_CATEGORY.SPELL_BEGIN_OR_INTERRUPT and action.param == EVENT_ACTION_PARAM.BEGIN then
    casting = os.clock()
  end
end)

function updateInfo()
  set_box_visible(settings.show)
  
  if not settings.show then return end
  
  local self = windower.ffxi.get_mob_by_target('me')
  
  if not self then
    set_box_visible(false)
    return
  end
  
  local lines = T{}
  for char,pos in pairs(track_info) do
    local dist = math.sqrt(distanceSquared(self, pos))
    lines:insert(string.format('%s %.2f', char, dist))
  end
  
  local maxWidth = math.max(1, table.reduce(lines, function(a, b) return math.max(a, #b) end, '1'))
  for i,line in ipairs(lines) do lines[i] = lines[i]:lpad(' ', maxWidth) end
  local value = lines:concat('\n')
  if value ~= box_last_text then
    box:text(value)
    box_last_text = value
  end
end

function distanceSquared(A, B)
  local dx = B.x-A.x
  local dy = B.y-A.y
  return dx*dx + dy*dy
end

windower.add_to_chat(158,
  ('[FastFollow] Loaded v%s; safe movement-only zoning enabled.'):format(
    _addon.version))
