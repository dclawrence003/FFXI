-- Designed and directed by Don Lawrence; test code developed using OpenAI Codex.
-- Executes the attributed FastFollow candidate unchanged. No live client calls.
local now, zone, moving, allowed = 100, 100, false, true
local fault = arg and arg[1] == '--drop-stop'
local callbacks, calls, observations = {}, {}, {}
local me = {id=1, name='Follower', x=0, y=0}
local function list(t)
    return setmetatable(t, {__index={remove=table.remove, insert=table.insert}})
end
T = list
S = function(t)
    return setmetatable(t, {__index={
        contains=function(self, value) return self[value] == true end,
        add=function(self, value) self[value] = true end,
        remove=function(self, value) self[value] = nil end,
    }})
end
string.split = function(value)
    local result = list({})
    for token in value:gmatch('%S+') do result[#result+1] = token end
    return result
end
local noop = function() end
local modules = {
    strings={}, tables={}, sets={}, coroutine={}, logger={},
    resources={items={}}, spell_cast_times={},
    config={load=function(defaults) return defaults end, save=noop},
    texts={new=function() return {visible=noop, text=noop} end},
    socket={gettime=function() return now end},
    packets={inject=function() error('Unexpected packet injection') end},
    partyops_trace={
        initialize_executor_pause=function(executor, domain)
            assert(executor == 'fastfollow' and domain == 'follower_movement')
        end,
        movement=function(...) observations[#observations+1] = {...}; return true end,
        executor_pause_tick=function(executor, domain)
            assert(executor == 'fastfollow' and domain == 'follower_movement')
            if allowed == 'error' then error('simulated unavailable pause service') end
            return allowed
        end,
    },
}
require = function(name) assert(modules[name], 'Unexpected dependency: '..name); return modules[name] end
os.clock = function() return now end
io.open = function() return {write=noop, close=noop} end
log = noop
_addon = {}
windower = {
    windower_path='SIMULATED/', add_to_chat=noop, send_command=noop,
    send_ipc_message=noop,
    register_event=function(name, fn) callbacks[name] = fn end,
    ffxi={get_player=function() return me end,
        get_mob_by_target=function() return me end,
        get_info=function() return {zone=zone} end,
        follow=noop,
        run=function(x, y)
            calls[#calls+1] = {x, y}
            if x == false and fault then
                print('INJECTED FAULT: movement boundary dropped stop')
                return
            end
            moving = x ~= false
        end},
}
assert(loadfile('patches/FastFollow/candidate/FastFollow.lua'))()
local function tick(delta) now=now+(delta or 0.1); callbacks.prerender() end
local function command(...) callbacks['addon command'](...) end
local function ipc(value) callbacks['ipc message'](value) end
local function stopped(reason) assert(not moving, 'MOVEMENT_STOP_FAILURE: '..reason) end
local function signal(token, source_zone, age)
    ipc(('zonewalk leader %d 10 0 1 0 %.3f %s'):format(source_zone or zone, now-(age or 0), token))
end

command('follow', 'Leader')
ipc('update leader 100 10 0')
tick()
assert(moving and calls[#calls][1] > 0, 'Follower did not move toward leader')
command('stop')
stopped('operator stop')
tick()
stopped('operator stop remains effective')

command('follow', 'Leader')
tick()
assert(moving, 'Precondition: follow did not resume')
allowed=false
tick()
stopped('PartyOps denied permission')
tick()
stopped('PartyOps denial held')
allowed=true
tick()
assert(moving, 'Allowed follow did not resume')
allowed='error'
tick()
stopped('PartyOps pause callback unavailable')
allowed=true
ipc('update leader 100 0 0')
tick()
stopped('leader reached')

signal('fresh')
tick()
assert(moving, 'Fresh same-zone nudge did not start')
tick(3.1)
stopped('approach timeout with no position progress')
tick()
stopped('expired nudge remains stopped')
signal('fresh')
tick()
stopped('duplicate token rejected')
signal('stale', zone, 5)
signal('future', zone, -2)
signal('wrong-zone', zone+1)
tick()
stopped('stale, future and wrong-zone signals rejected')

signal('natural')
tick()
assert(moving, 'Precondition: natural-request nudge did not start')
assert(callbacks['outgoing chunk'](0x05E, '', '', false, false) ~= true,
    'Natural zone request must not be blocked')
stopped('natural zone request')

signal('transition')
tick()
assert(moving, 'Precondition: transition nudge did not start')
zone=101
callbacks['zone change'](101, 100)
stopped('zone change')
signal('old-zone', 100)
tick()
stopped('old-zone signal after transition')

me.x=10
signal('cross')
tick()
assert(moving, 'Crossing nudge did not start at source point')
tick(1.1)
stopped('cross timeout')
assert(#observations > 0, 'No calls to PartyOps observation seam')
print('PASS - actual FastFollow movement, pause and zone cancellation boundaries')
