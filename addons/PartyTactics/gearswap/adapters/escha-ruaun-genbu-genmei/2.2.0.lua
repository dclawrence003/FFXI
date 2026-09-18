-- PartyTactics GearSwap adapter: Genbu best-effort fixed actions.
--
-- This revision deliberately has no action-ownership layer.  It submits only
-- fixed, profile-named actions through Windower's normal input path so the
-- character GearSwap file remains the sole equipment/instrument owner.  It
-- never filters, cancels, reserves, delays, or replaces a manual action.

local M = {
    id = 'escha-ruaun-genbu-genmei',
    version = '2.2.0',
    controller = 'genmei',
    protocol = 1,
}

local ZONE = 289
local TARGET_NAME = 'Genbu'
local MIN_REPEAT = 0.75

local ACTIONS = {
    BRD = {
        barwatera={command='/ma', name='Barwatera', self_target=true},
    },
    COR = {
        disengage={command='/attack', off=true},
        shoot={command='/ra'},
        ['last-stand']={command='/ws', name='Last Stand'},
        proc={command='/ja', name='Thunder Shot'},
    },
    DNC = {},
    GEO = {
        setup={command='/ma', name='Geo-Malaise'},
        proc={command='/ma', name='Thunder'},
        burst={command='/ma', name='Thunder IV'},
    },
    PLD = {
        crusade={command='/ma', name='Crusade', self_target=true},
        ['divine-emblem']={
            command='/ja', name='Divine Emblem', self_target=true,
        },
        sentinel={command='/ja', name='Sentinel', self_target=true},
        flash={command='/ma', name='Flash'},
        provoke={command='/ja', name='Provoke'},
    },
    RDM = {
        dispel={command='/ma', name='Dispel'},
        proc={command='/ma', name='Thunder'},
        burst={command='/ma', name='Thunder IV'},
    },
}

local RECOVERY = {
    BRD={
        ['recover-songs']={214, 197, 196}, -- March, Minne, Ballad
    },
    COR={
        ['recover-rolls']={321, 314}, -- Samurai, Warlock
    },
}

local capability
local active = false
local last_dispatch = {}
local recovery_seen = {}
local dispatched = 0
local rejected = 0

local function nonnegative_integer(value)
    if type(value) ~= 'string' or value == '' or #value > 12
        or value:match('^%d+$') == nil
    then
        return nil
    end
    local number = tonumber(value)
    if not number or number < 0 or number ~= math.floor(number) then
        return nil
    end
    return number
end

local function uint32(value)
    if type(value) ~= 'string' or value == '' or #value > 10
        or value:match('^%d+$') == nil
    then
        return nil
    end
    local number = tonumber(value)
    if not number or number < 1 or number > 4294967295
        or number ~= math.floor(number)
    then
        return nil
    end
    return number
end

local function generation(value)
    return type(value) == 'string' and #value <= 64
        and value:match('^%d+%-%d+%-%d+$') ~= nil
end

local function current_player()
    local live = type(windower) == 'table'
        and type(windower.ffxi) == 'table'
        and type(windower.ffxi.get_player) == 'function'
        and windower.ffxi.get_player() or nil
    return type(player) == 'table' and player or live, live
end

local function current_job()
    local current, live = current_player()
    return current and current.main_job or live and live.main_job or nil
end

local function party_claimed(target)
    local claim = target and tonumber(target.claim_id) or nil
    if not claim or claim < 1 or claim > 4294967295
        or claim ~= math.floor(claim)
    then
        return false
    end
    local current, live = current_player()
    if tonumber(current and current.id) == claim
        or tonumber(live and live.id) == claim
    then
        return true
    end
    local party = windower.ffxi.get_party() or {}
    for index = 0, 5 do
        local member = party['p'..tostring(index)]
        if tonumber(member and member.mob and member.mob.id) == claim then
            return true
        end
    end
    return false
end

local function exact_target(id)
    local info = windower.ffxi.get_info()
    local target = windower.ffxi.get_mob_by_id(id)
    local claim = target and tonumber(target.claim_id) or nil
    return info and info.logged_in and tonumber(info.zone) == ZONE
        and type(target) == 'table'
        and target.name == TARGET_NAME
        and tonumber(target.spawn_type) == 16
        and target.valid_target == true
        and (tonumber(target.hpp) or 0) > 0
        and (claim == 0 or party_claimed(target))
        and target or nil
end

local function valid_authority(arguments)
    return type(arguments) == 'table'
        and generation(arguments[2])
        and nonnegative_integer(arguments[3]) ~= nil
end

local function report_ready(arguments)
    local epoch = nonnegative_integer(arguments[2])
    local protocol = nonnegative_integer(arguments[3])
    local job = current_job()
    if not generation(arguments[1]) or epoch == nil
        or protocol ~= M.protocol or ACTIONS[job] == nil
    then
        return false, 'invalid or unsupported controller probe'
    end
    capability = {
        generation=arguments[1], epoch=epoch, protocol=protocol,
    }
    windower.send_command(('pt __controller_ready genmei %s %d %d')
        :format(arguments[1], epoch, protocol))
    return true, 'ready'
end

local function report_lost()
    if not capability then return end
    windower.send_command(('pt __controller_lost genmei %s %d %d')
        :format(capability.generation, capability.epoch,
            capability.protocol))
    capability = nil
end

local function dispatch(semantic, action, id)
    local key = current_job()..':'..semantic..':'..tostring(id)
    local now = os.clock()
    if now - (last_dispatch[key] or -100000) < MIN_REPEAT then
        return true, 'recently submitted'
    end
    last_dispatch[key] = now

    if action.command == '/attack' then
        windower.chat.input(action.off and '/attack off'
            or ('/attack '..tostring(id)))
    elseif action.command == '/ra' then
        windower.chat.input('/ra '..tostring(id))
    else
        local target = action.self_target and '<me>' or tostring(id)
        windower.chat.input(action.command..' "'..action.name..'" '..target)
    end
    dispatched = dispatched + 1
    return true, 'submitted'
end

local function recover(semantic, ids, arguments, id)
    local token = arguments[4]
    if type(token) ~= 'string' or token == '' or #token > 64
        or token:match('^[A-Za-z0-9_-]+$') == nil
    then
        return false, 'recovery request requires one bounded event token'
    end
    local key = current_job()..':'..semantic..':'..token
    if recovery_seen[key] then return true, 'already submitted' end
    recovery_seen[key] = true
    if type(windower.ffxi.cancel_buff) == 'function' then
        local current, live = current_player()
        local buffs = current and current.buffs or live and live.buffs or {}
        local present = {}
        for _, buff_id in ipairs(buffs or {}) do
            present[tonumber(buff_id)] = true
        end
        for _, buff_id in ipairs(ids) do
            if present[buff_id] then windower.ffxi.cancel_buff(buff_id) end
        end
    end
    dispatched = dispatched + 1
    return true, 'support refresh requested'
end

function M.activate()
    active = true
    return true
end

function M.deactivate(reason)
    active = false
    report_lost()
    last_dispatch = {}
    recovery_seen = {}
    return true
end

function M.handle_action(controller, semantic, arguments)
    if controller ~= M.controller or type(semantic) ~= 'string' then
        rejected = rejected + 1
        return false, 'unsupported controller or semantic'
    end
    arguments = type(arguments) == 'table' and arguments or {}
    semantic = semantic:lower()
    if semantic == 'probe' then return report_ready(arguments) end
    if semantic == 'cancel' then return true, 'nothing reserved' end
    if not active then
        rejected = rejected + 1
        return false, 'adapter is inactive'
    end

    local id = uint32(arguments[1])
    if not id or not valid_authority(arguments) then
        rejected = rejected + 1
        return false, 'exact Genbu ID and current authority are required'
    end
    local job = current_job()
    if semantic == 'disengage' and job == 'COR' then
        return dispatch(semantic, ACTIONS.COR.disengage, id)
    end
    if not exact_target(id) then
        rejected = rejected + 1
        return false, 'exact live unclaimed or party-claimed Genbu is required'
    end

    local recovery = RECOVERY[job] and RECOVERY[job][semantic]
    if recovery then return recover(semantic, recovery, arguments, id) end
    local action = ACTIONS[job] and ACTIONS[job][semantic]
    if not action then
        rejected = rejected + 1
        return false, tostring(job or 'unknown job')
            ..' cannot perform '..semantic
    end
    return dispatch(semantic, action, id)
end

-- Explicit pass-through hooks are regression guards: no manual action is ever
-- owned by this profile, including while an automatic request is submitted.
function M.filter_pretarget(spell, spell_map, event_args)
    return false
end

function M.filter_precast(spell, spell_map, event_args)
    return false
end

function M.status()
    return ('best-effort manual-pass-through dispatched=%d rejected=%d')
        :format(dispatched, rejected)
end

function M.file_unload(...)
    return M.deactivate('GearSwap job file unloaded')
end

function M.logout(...)
    return M.deactivate('logout')
end

function M.unload(...)
    return M.deactivate('GearSwap unloaded')
end

return M
