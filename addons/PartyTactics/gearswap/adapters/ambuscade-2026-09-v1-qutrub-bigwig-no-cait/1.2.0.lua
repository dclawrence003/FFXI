-- PartyTactics GearSwap adapter: no-Cait Qutrub best-effort fixed actions.
--
-- This revision has no action-ownership layer. It submits only fixed,
-- profile-named actions through Windower's normal input path so each character
-- GearSwap file remains the sole equipment/instrument owner. It never filters,
-- cancels, reserves, delays, or replaces a manual action.

local M = {
    id = 'ambuscade-2026-09-v1-qutrub-bigwig-no-cait',
    version = '1.2.0',
    controller = 'qutrub-bigwig-no-cait',
    protocol = 1,
}

local BOSS_NAMES = {
    bozzettobigwig=true,
}
local ADD_NAMES = {
    bozzettoastrologer=true,
    bozzettoastrol=true,
    bozzettotormentor=true,
    bozzettotormenter=true,
    bozzettotorment=true,
    bozzettotormen=true,
}
local ZONES = {[183]=true, [287]=true}
local MIN_REPEAT = 0.75
local SAFE_ADD_CONTROL_SEPARATION = 20
local AREA_CONTROL = {
    ['sheep-song-add']=true,
    ['geist-wall-add']=true,
    ['jettatura-add']=true,
}

local ACTIONS = {
    COR = {
        food={command='/item', name='Grape Daifuku', target='self'},
        ['shadow-ni']={command='/ma', name='Utsusemi: Ni', target='self'},
        ['shadow-ichi']={command='/ma', name='Utsusemi: Ichi', target='self'},
        pull={command='/ja', name='Light Shot', target='boss'},
    },
    DNC = {
        food={command='/item', name='Grape Daifuku', target='self'},
        ['shadow-ni']={command='/ma', name='Utsusemi: Ni', target='self'},
        ['shadow-ichi']={command='/ma', name='Utsusemi: Ichi', target='self'},
        ['stun-add']={
            command='/ja', name='Violent Flourish', target='encounter',
        },
    },
    PLD = {
        cocoon={command='/ma', name='Cocoon', target='self'},
        ['blank-gaze-add']={
            command='/ma', name='Blank Gaze', target='add',
        },
        ['flash-add']={command='/ma', name='Flash', target='add'},
        ['sheep-song-add']={
            command='/ma', name='Sheep Song', target='add',
        },
        ['geist-wall-add']={
            command='/ma', name='Geist Wall', target='add',
        },
        ['jettatura-add']={command='/ma', name='Jettatura', target='add'},
    },
    BRD = {
        food={command='/item', name='Grape Daifuku', target='self'},
        ['shadow-ni']={command='/ma', name='Utsusemi: Ni', target='self'},
        ['shadow-ichi']={command='/ma', name='Utsusemi: Ichi', target='self'},
        clarion={command='/ja', name='Clarion Call', target='self'},
        ['fourth-song']={
            command='/ma', name="Knight's Minne V", target='self',
        },
    },
    RDM = {
        ['lowhp-cure']={command='/ma', name='Cure II', target='party'},
        ['support-cure']={command='/ma', name='Cure IV', target='party'},
        ['silence-add']={command='/ma', name='Silence', target='add'},
        ['dispel-ice-spikes']={command='/ma', name='Dispel', target='add'},
        diaga={command='/ma', name='Diaga', target='boss'},
        ['silence-boss']={command='/ma', name='Silence', target='boss'},
        ['slow-ii']={command='/ma', name='Slow II', target='boss'},
        ['paralyze-ii']={command='/ma', name='Paralyze II', target='boss'},
        ['dia-iii']={command='/ma', name='Dia III', target='boss'},
        ['cure-iv']={command='/ma', name='Cure IV', target='party'},
        poisona={command='/ma', name='Poisona', target='party'},
        paralyna={command='/ma', name='Paralyna', target='party'},
        silena={command='/ma', name='Silena', target='party'},
        cursna={command='/ma', name='Cursna', target='party'},
        erase={command='/ma', name='Erase', target='party'},
    },
    GEO = {
        entrust={command='/ja', name='Entrust', target='self'},
        ['indi-wilt']={command='/ma', name='Indi-Wilt', target='party'},
        setup={command='/ma', name='Geo-Frailty', target='boss'},
        ['cure-iv']={command='/ma', name='Cure IV', target='party'},
        poisona={command='/ma', name='Poisona', target='party'},
        paralyna={command='/ma', name='Paralyna', target='party'},
        silena={command='/ma', name='Silena', target='party'},
        cursna={command='/ma', name='Cursna', target='party'},
        erase={command='/ma', name='Erase', target='party'},
    },
}

local capability
local active = false
local last_dispatch = {}
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

local function normalized_name(name)
    return type(name) == 'string'
        and name:lower():gsub('[^%w]', '') or nil
end

local function has_name(target, names)
    local name = normalized_name(target and target.name)
    return name ~= nil and names[name] == true
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

local function exact_boss(id)
    local info = windower.ffxi.get_info()
    local target = windower.ffxi.get_mob_by_id(id)
    local claim = target and tonumber(target.claim_id) or nil
    return info and info.logged_in and ZONES[tonumber(info.zone)] == true
        and type(target) == 'table'
        and has_name(target, BOSS_NAMES)
        and tonumber(target.spawn_type) == 16
        and target.valid_target == true
        and (tonumber(target.hpp) or 0) > 0
        and (claim == 0 or party_claimed(target))
        and target or nil
end

local function squared_separation(left, right)
    if type(left) ~= 'table' or type(right) ~= 'table'
        or type(left.x) ~= 'number' or type(left.y) ~= 'number'
        or type(right.x) ~= 'number' or type(right.y) ~= 'number'
    then
        return nil
    end
    local dx, dy = left.x - right.x, left.y - right.y
    return dx * dx + dy * dy
end

local function local_entity()
    local current, live = current_player()
    local target = type(windower.ffxi.get_mob_by_target) == 'function'
        and windower.ffxi.get_mob_by_target('me') or nil
    if target then return target end
    local id = tonumber(current and current.id) or tonumber(live and live.id)
    return id and windower.ffxi.get_mob_by_id(id) or nil
end

local function safe_area_control(boss, add)
    local actor = local_entity()
    local boss_add = squared_separation(boss, add)
    local actor_add = squared_separation(actor, add)
    return boss_add ~= nil and actor_add ~= nil
        and boss_add >= SAFE_ADD_CONTROL_SEPARATION
            * SAFE_ADD_CONTROL_SEPARATION
        and actor_add <= 9 * 9
end

local function exact_add(boss, id)
    local target = windower.ffxi.get_mob_by_id(id)
    if type(target) ~= 'table'
        or not has_name(target, ADD_NAMES)
        or tonumber(target.spawn_type) ~= 16
        or target.valid_target ~= true
        or (tonumber(target.hpp) or 0) <= 0
    then
        return nil
    end
    local claim = tonumber(target.claim_id) or 0
    if claim ~= 0 and not party_claimed(target) then return nil end
    local separation = squared_separation(boss, target)
    if separation and separation > 35 * 35 then return nil end
    return target
end

local function party_subject(id)
    local party = windower.ffxi.get_party() or {}
    for index = 0, 5 do
        local member = party['p'..tostring(index)]
        if tonumber(member and member.mob and member.mob.id) == id then
            return member
        end
    end
    return nil
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
    windower.send_command(
        ('pt __controller_ready qutrub-bigwig-no-cait %s %d %d')
            :format(arguments[1], epoch, protocol))
    return true, 'ready'
end

local function report_lost()
    if not capability then return end
    windower.send_command(
        ('pt __controller_lost qutrub-bigwig-no-cait %s %d %d')
            :format(capability.generation, capability.epoch,
                capability.protocol))
    capability = nil
end

local function dispatch(semantic, action, subject_id)
    local key = tostring(current_job())..':'..semantic..':'
        ..tostring(subject_id or 'self')
    local now = os.clock()
    if now - (last_dispatch[key] or -100000) < MIN_REPEAT then
        return true, 'recently submitted'
    end
    last_dispatch[key] = now

    local target = action.target == 'self' and '<me>'
        or tostring(subject_id)
    if action.command == '/ra' then
        windower.chat.input('/ra '..target)
    else
        windower.chat.input(action.command..' "'..action.name..'" '..target)
    end
    dispatched = dispatched + 1
    return true, 'submitted'
end

function M.activate()
    active = true
    return true
end

function M.deactivate(reason)
    active = false
    report_lost()
    last_dispatch = {}
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
    if semantic == 'lowhp-on' or semantic == 'lowhp-off'
        or semantic == 'capture-on' or semantic == 'capture-off'
    then
        return true, 'advisory control ignored'
    end
    if not active then
        rejected = rejected + 1
        return false, 'adapter is inactive'
    end

    local encounter_id = uint32(arguments[1])
    if not encounter_id or not valid_authority(arguments) then
        rejected = rejected + 1
        return false, 'exact Bigwig ID and current authority are required'
    end
    local boss = exact_boss(encounter_id)
    if not boss then
        rejected = rejected + 1
        return false, 'exact live unclaimed or party-claimed Bigwig is required'
    end

    local job = current_job()
    local action = ACTIONS[job] and ACTIONS[job][semantic]
    if not action then
        rejected = rejected + 1
        return false, tostring(job or 'unknown job')
            ..' cannot perform '..semantic
    end

    local subject_id = uint32(arguments[5]) or encounter_id
    if action.target == 'boss' then
        if subject_id ~= encounter_id then
            rejected = rejected + 1
            return false, semantic..' requires exact Bigwig'
        end
    elseif action.target == 'add' then
        local add = exact_add(boss, subject_id)
        if not add then
            rejected = rejected + 1
            return false, semantic..' requires an exact live Qutrub add'
        end
        if AREA_CONTROL[semantic] and not safe_area_control(boss, add) then
            rejected = rejected + 1
            return false, semantic..' skipped: current area geometry is unsafe'
        end
    elseif action.target == 'encounter' then
        if subject_id ~= encounter_id and not exact_add(boss, subject_id) then
            rejected = rejected + 1
            return false, semantic..' requires Bigwig or an exact live add'
        end
    elseif action.target == 'party' then
        if not party_subject(subject_id) then
            rejected = rejected + 1
            return false, semantic..' requires an exact party member'
        end
    elseif action.target == 'self' then
        subject_id = nil
    end
    return dispatch(semantic, action, subject_id)
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

function M.zone_change(...)
    last_dispatch = {}
end

function M.logout(...)
    return M.deactivate('logout')
end

function M.unload(...)
    return M.deactivate('GearSwap unloaded')
end

return M
