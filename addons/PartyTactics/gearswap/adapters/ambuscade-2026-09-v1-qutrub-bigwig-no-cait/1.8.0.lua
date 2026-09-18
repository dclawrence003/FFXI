-- PartyTactics GearSwap adapter: no-Cait Qutrub best-effort fixed actions.
-- Manual callbacks always pass through; this adapter only submits named
-- profile actions through Windower's ordinary input path.

local M = {
    id = 'ambuscade-2026-09-v1-qutrub-bigwig-no-cait',
    version = '1.8.0',
    controller = 'qutrub-bigwig-no-cait',
    protocol = 1,
}

local BOSS_NAMES = {bozzettobigwig=true}
local ADD_NAMES = {
    bozzettoastrologer=true, bozzettoastrol=true,
    bozzettotormentor=true, bozzettotormenter=true,
    bozzettotorment=true, bozzettotormen=true,
}
local ZONES = {[183]=true, [287]=true}
local MIN_REPEAT = .75
local SAFE_ADD_CONTROL_SEPARATION = 15
local SAFE_ADD_CONTROL_ARRIVAL = 4.5
local COPY_IMAGE_COUNTS = {[66]=1,[444]=2,[445]=3,[446]=4}
local SHADOW_OBSERVE_INTERVAL = .10
local SHADOW_RESTORE_RETRY = .75
local SHADOW_SPELL_IDS = {['shadow-ichi']=338, ['shadow-ni']=339}
local SUPPORT_CURE_MAX_HPP = 60
local FINAL_TOPUP_MAX_HPP = 20
local TACKLE_EMERGENCY_MAX_HPP = 40
local SUPPORT_MP_FLOOR = 15
local AREA_CONTROL = {
    ['sheep-song-add']=true,
    ['geist-wall-add']=true,
    ['jettatura-add']=true,
}
local RERAISE_ITEMS = {
    {id=6697, name='Instant Reraise III'},
    {id=5770, name='Super Reraiser'},
    {id=4173, name='Hi-Reraiser'},
    {id=4182, name='Instant Reraise'},
    {id=4172, name='Reraiser'},
}

local ACTIONS = {
    COR = {
        food={command='/item', name='Grape Daifuku', target='self'},
        ['shadow-ni']={command='/ma', name='Utsusemi: Ni', target='self'},
        ['shadow-ichi']={command='/ma', name='Utsusemi: Ichi', target='self'},
        pull={command='/ja', name='Light Shot', target='boss'},
        ['light-shot-target']={
            command='/ja', name='Light Shot', target='encounter',
        },
    },
    DNC = {
        food={command='/item', name='Grape Daifuku', target='self'},
        ['shadow-ni']={command='/ma', name='Utsusemi: Ni', target='self'},
        ['shadow-ichi']={command='/ma', name='Utsusemi: Ichi', target='self'},
        ['stun-add']={command='/ja', name='Violent Flourish', target='encounter'},
    },
    PLD = {
        food={command='/item', name='Grape Daifuku', target='self'},
        cocoon={command='/ma', name='Cocoon', target='self'},
        crusade={command='/ma', name='Crusade', target='self'},
        reprisal={command='/ma', name='Reprisal', target='self'},
        ['sentinel-add']={command='/ja', name='Sentinel', target='self'},
        ['palisade-add']={command='/ja', name='Palisade', target='self'},
        ['blank-gaze-add']={command='/ma', name='Blank Gaze', target='add'},
        ['flash-add']={command='/ma', name='Flash', target='add'},
        ['sheep-song-add']={command='/ma', name='Sheep Song', target='add'},
        ['geist-wall-add']={command='/ma', name='Geist Wall', target='add'},
        ['jettatura-add']={command='/ma', name='Jettatura', target='add'},
        ['emergency-cure']={command='/ma', name='Cure IV', target='party'},
    },
    BRD = {
        food={command='/item', name='Grape Daifuku', target='self'},
        ['shadow-ni']={command='/ma', name='Utsusemi: Ni', target='self'},
        ['shadow-ichi']={command='/ma', name='Utsusemi: Ichi', target='self'},
        clarion={command='/ja', name='Clarion Call', target='self'},
        ['fourth-song']={command='/ma', name="Knight's Minne V", target='self'},
    },
    RDM = {
        reraise={command='/ma', name='Reraise', target='self'},
        ['wake-pack']={command='/ma', name='Curaga II', target='party'},
        ['lowhp-cure']={command='/ma', name='Cure II', target='party'},
        ['support-cure']={command='/ma', name='Cure IV', target='party'},
        ['silence-add']={command='/ma', name='Silence', target='add'},
        ['dispel-ice-spikes']={command='/ma', name='Dispel', target='add'},
        diaga={command='/ma', name='Diaga', target='boss'},
        ['silence-boss']={command='/ma', name='Silence', target='boss'},
        ['slow-ii']={command='/ma', name='Slow II', target='boss'},
        ['paralyze-ii']={command='/ma', name='Paralyze II', target='boss'},
        ['dia-iii']={command='/ma', name='Dia III', target='encounter'},
        ['cure-iv']={command='/ma', name='Cure IV', target='party'},
        poisona={command='/ma', name='Poisona', target='party'},
        paralyna={command='/ma', name='Paralyna', target='party'},
        silena={command='/ma', name='Silena', target='party'},
        cursna={command='/ma', name='Cursna', target='party'},
        erase={command='/ma', name='Erase', target='party'},
    },
    GEO = {
        reraise={command='/ma', name='Reraise', target='self'},
        ['wake-pack']={command='/ma', name='Curaga II', target='party'},
        entrust={command='/ja', name='Entrust', target='self'},
        ['indi-wilt']={command='/ma', name='Indi-Wilt', target='party'},
        setup={command='/ma', name='Geo-Frailty', target='boss'},
        ['frailty-target']={
            command='/ma', name='Geo-Frailty', target='encounter',
        },
        ['flash-add']={command='/ma', name='Flash', target='add'},
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
local shadow_watch_enabled = false
local shadow_encounter_id
local shadow_last_count
local next_shadow_observation = 0
local next_shadow_restore = 0
local shadow_pending_until = 0

local function nonnegative_integer(value)
    if type(value) ~= 'string' or value == '' or #value > 12
        or value:match('^%d+$') == nil
    then return nil end
    local number = tonumber(value)
    return number and number >= 0 and number == math.floor(number)
        and number or nil
end

local function uint32(value)
    if type(value) ~= 'string' or value == '' or #value > 10
        or value:match('^%d+$') == nil
    then return nil end
    local number = tonumber(value)
    return number and number >= 1 and number <= 4294967295
        and number == math.floor(number) and number or nil
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

local function has_buff_id(wanted)
    local current, live = current_player()
    for _, source in ipairs{current,live} do
        if type(source) == 'table' then
            for key, value in pairs(source.buffs or {}) do
                if tonumber(value) == wanted
                    or tonumber(key) == wanted and value
                then return true end
            end
        end
    end
    return false
end

local function copy_image_count()
    local count = 0
    for id, copies in pairs(COPY_IMAGE_COUNTS) do
        if has_buff_id(id) then count = math.max(count, copies) end
    end
    return count
end

local function current_mpp()
    local current, live = current_player()
    for _, source in ipairs{current,live} do
        local value = type(source) == 'table'
            and (tonumber(source.mpp)
                or tonumber(source.vitals and source.vitals.mpp)) or nil
        if value then return value end
    end
    return 100
end

local function spell_ready(id)
    if type(windower.ffxi.get_spell_recasts) ~= 'function' then return true end
    local ok, recasts = pcall(windower.ffxi.get_spell_recasts)
    if not ok or type(recasts) ~= 'table' then return true end
    local recast = tonumber(recasts[id])
    return recast == nil or recast <= 0
end

local function stop_shadow_watch()
    shadow_watch_enabled = false
    shadow_encounter_id = nil
    shadow_last_count = nil
    next_shadow_observation = 0
    next_shadow_restore = 0
    shadow_pending_until = 0
end

local function has_inventory_item(id)
    if type(windower.ffxi.get_items) ~= 'function' then return false end
    local ok, inventory = pcall(windower.ffxi.get_items, 0)
    if not ok or type(inventory) ~= 'table' then return false end
    for key, item in pairs(inventory) do
        if key ~= 'max' and key ~= 'count' and type(item) == 'table'
            and tonumber(item.id) == id and (tonumber(item.count) or 0) > 0
        then return true end
    end
    return false
end

local function reraise_action(job)
    if (job == 'RDM' or job == 'GEO') and ACTIONS[job] then
        return ACTIONS[job].reraise
    end
    for _, item in ipairs(RERAISE_ITEMS) do
        if has_inventory_item(item.id) then
            return {command='/item', name=item.name, target='self'}
        end
    end
    return nil
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
    then return false end
    local current, live = current_player()
    if tonumber(current and current.id) == claim
        or tonumber(live and live.id) == claim
    then return true end
    local party = windower.ffxi.get_party() or {}
    for index=0,5 do
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
        and type(target) == 'table' and has_name(target, BOSS_NAMES)
        and tonumber(target.spawn_type) == 16 and target.valid_target == true
        and (tonumber(target.hpp) or 0) > 0
        and (claim == 0 or party_claimed(target)) and target or nil
end

local function squared_separation(left, right)
    if type(left) ~= 'table' or type(right) ~= 'table'
        or type(left.x) ~= 'number' or type(left.y) ~= 'number'
        or type(right.x) ~= 'number' or type(right.y) ~= 'number'
    then return nil end
    local dx, dy = left.x-right.x, left.y-right.y
    return dx*dx + dy*dy
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
        and boss_add >= SAFE_ADD_CONTROL_SEPARATION^2
        and actor_add <= SAFE_ADD_CONTROL_ARRIVAL^2
end

local function exact_add(boss, id)
    local target = windower.ffxi.get_mob_by_id(id)
    if type(target) ~= 'table' or not has_name(target, ADD_NAMES)
        or tonumber(target.spawn_type) ~= 16 or target.valid_target ~= true
        or (tonumber(target.hpp) or 0) <= 0
    then return nil end
    local claim = tonumber(target.claim_id) or 0
    if claim ~= 0 and not party_claimed(target) then return nil end
    local separation = squared_separation(boss, target)
    if separation and separation > 35^2 then return nil end
    return target
end

local function party_subject(id)
    local party = windower.ffxi.get_party() or {}
    for index=0,5 do
        local member = party['p'..tostring(index)]
        if tonumber(member and member.mob and member.mob.id) == id then
            return member
        end
    end
    return nil
end

local function party_subject_hpp(member, id)
    local hpp = tonumber(member and member.hpp)
    if hpp then return hpp end
    local mob = windower.ffxi.get_mob_by_id(id)
    return tonumber(mob and mob.hpp)
end

local function valid_authority(arguments)
    return type(arguments) == 'table' and generation(arguments[2])
        and nonnegative_integer(arguments[3]) ~= nil
end

local function report_ready(arguments)
    local epoch = nonnegative_integer(arguments[2])
    local protocol = nonnegative_integer(arguments[3])
    local job = current_job()
    if not generation(arguments[1]) or epoch == nil
        or protocol ~= M.protocol or ACTIONS[job] == nil
    then return false, 'invalid or unsupported controller probe' end
    capability = {generation=arguments[1],epoch=epoch,protocol=protocol}
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
    if now-(last_dispatch[key] or -100000) < MIN_REPEAT then
        return true, 'recently submitted'
    end
    last_dispatch[key] = now
    local target = action.target == 'self' and '<me>' or tostring(subject_id)
    windower.chat.input(action.command..' "'..action.name..'" '..target)
    if semantic == 'shadow-ni' then
        shadow_pending_until = now + 2.5
    elseif semantic == 'shadow-ichi' then
        shadow_pending_until = now + 5
    end
    dispatched = dispatched+1
    return true, 'submitted'
end

local function submit_shadow(job, copies, preferred)
    local actions = ACTIONS[job]
    if not actions or not actions['shadow-ni'] then
        return false, tostring(job or 'unknown job')..' cannot restore shadows'
    end
    local now = os.clock()
    if copies >= 3 then return true, 'at least three Copy Images remain' end
    if now < shadow_pending_until then
        return true, 'shadow restore already submitted'
    end

    local ni_ready = spell_ready(SHADOW_SPELL_IDS['shadow-ni'])
    local ichi_ready = spell_ready(SHADOW_SPELL_IDS['shadow-ichi'])
    if preferred == 'shadow-ichi' and copies == 0 and ichi_ready then
        return dispatch('shadow-ichi', actions['shadow-ichi'])
    end
    if ni_ready then return dispatch('shadow-ni', actions['shadow-ni']) end
    if copies == 0 and ichi_ready then
        -- This closes the live failure window: if the last image disappears
        -- while Ni is still on recast, start the slower Ichi immediately
        -- instead of waiting for the controller's next ten-second pass.
        return dispatch('shadow-ichi', actions['shadow-ichi'])
    end
    return true, copies == 0 and 'both Utsusemi tiers are on recast'
        or 'Ni is on recast; existing Copy Image retained'
end

function M.activate()
    active = true
    stop_shadow_watch()
    return true
end

function M.deactivate(reason)
    active = false
    stop_shadow_watch()
    report_lost()
    last_dispatch = {}
    return true
end

function M.handle_action(controller, semantic, arguments)
    if controller ~= M.controller or type(semantic) ~= 'string' then
        rejected = rejected+1
        return false, 'unsupported controller or semantic'
    end
    arguments = type(arguments) == 'table' and arguments or {}
    semantic = semantic:lower()
    if semantic == 'probe' then return report_ready(arguments) end
    if semantic == 'cancel' then
        stop_shadow_watch()
        return true, 'local shadow watch stopped'
    end
    if semantic == 'lowhp-on' or semantic == 'lowhp-off'
        or semantic == 'capture-on' or semantic == 'capture-off'
    then return true, 'advisory control ignored' end
    if not active then
        rejected = rejected+1
        return false, 'adapter is inactive'
    end

    local encounter_id = uint32(arguments[1])
    if not encounter_id or not valid_authority(arguments) then
        rejected = rejected+1
        return false, 'exact Bigwig ID and current authority are required'
    end
    local boss = exact_boss(encounter_id)
    if not boss then
        rejected = rejected+1
        return false, 'exact live unclaimed or party-claimed Bigwig is required'
    end

    local job = current_job()
    local action = semantic == 'reraise' and reraise_action(job)
        or ACTIONS[job] and ACTIONS[job][semantic]
    if semantic == 'reraise' and has_buff_id(113) then
        return true, 'Reraise already active'
    end
    if semantic == 'shadow-ni' or semantic == 'shadow-ichi' then
        shadow_watch_enabled = true
        shadow_encounter_id = encounter_id
        shadow_last_count = copy_image_count()
        if semantic == 'shadow-ichi' and shadow_last_count >= 1 then
            return true, 'Copy Image still active; Ichi held in reserve'
        end
        return submit_shadow(job, shadow_last_count, semantic)
    end
    if semantic == 'food' and has_buff_id(251) then
        return true, 'Food already active'
    end
    if not action then
        rejected = rejected+1
        return false, semantic == 'reraise'
            and 'no usable Reraise source in Inventory'
            or tostring(job or 'unknown job')..' cannot perform '..semantic
    end

    local subject_id = uint32(arguments[5]) or encounter_id
    if action.target == 'boss' then
        if subject_id ~= encounter_id then
            rejected = rejected+1
            return false, semantic..' requires exact Bigwig'
        end
    elseif action.target == 'add' then
        local add = exact_add(boss, subject_id)
        if not add then
            rejected = rejected+1
            return false, semantic..' requires an exact live Qutrub add'
        end
        if AREA_CONTROL[semantic] and not safe_area_control(boss, add) then
            rejected = rejected+1
            return false, semantic..' skipped: current area geometry is unsafe'
        end
    elseif action.target == 'encounter' then
        if subject_id ~= encounter_id and not exact_add(boss, subject_id) then
            rejected = rejected+1
            return false, semantic..' requires Bigwig or an exact live add'
        end
    elseif action.target == 'party' then
        local member = party_subject(subject_id)
        if not member then
            rejected = rejected+1
            return false, semantic..' requires an exact party member'
        end
        local hpp = party_subject_hpp(member, subject_id)
        if semantic == 'emergency-cure' then
            if not hpp or hpp <= 0 or hpp > TACKLE_EMERGENCY_MAX_HPP then
                return true, 'Tackle emergency target is no longer critical'
            end
        elseif semantic == 'support-cure' then
            if not hpp or hpp <= 0 or hpp > SUPPORT_CURE_MAX_HPP then
                return true, 'support cure target is no longer injured'
            end
            if current_mpp() < SUPPORT_MP_FLOOR and hpp > 30 then
                return true, 'support MP floor preserved'
            end
        elseif semantic == 'lowhp-cure'
            and (not hpp or hpp <= 0 or hpp > FINAL_TOPUP_MAX_HPP)
        then
            return true, 'final-phase top-up target is outside its band'
        end
    elseif action.target == 'self' then
        subject_id = nil
    end
    return dispatch(semantic, action, subject_id)
end

function M.prerender()
    local now = os.clock()
    if not active or not shadow_watch_enabled
        or now < next_shadow_observation
    then
        return
    end
    next_shadow_observation = now + SHADOW_OBSERVE_INTERVAL

    local job = current_job()
    local action = ACTIONS[job] and ACTIONS[job]['shadow-ni'] or nil
    local boss = shadow_encounter_id and exact_boss(shadow_encounter_id)
        or nil
    if not action or not boss then return end

    local copies = copy_image_count()
    local previous = shadow_last_count
    shadow_last_count = copies
    if previous ~= nil and copies > previous then
        shadow_pending_until = 0
    end
    if copies < 3 and ((previous ~= nil and copies < previous)
        or now >= next_shadow_restore)
    then
        -- React to the loss immediately, then keep checking live recasts while
        -- the stack is low. At zero, Ichi is selected without delay whenever
        -- Ni is unavailable. A rejected attempt never disables this watcher.
        submit_shadow(job, copies, 'shadow-ni')
        next_shadow_restore = now + SHADOW_RESTORE_RETRY
    end
end

function M.filter_pretarget(spell, spell_map, event_args) return false end
function M.filter_precast(spell, spell_map, event_args) return false end

function M.status()
    return ('best-effort manual-pass-through shadows=%s/%d dispatched=%d rejected=%d')
        :format(shadow_watch_enabled and 'reactive' or 'off',
            copy_image_count(), dispatched, rejected)
end

function M.file_unload(...) return M.deactivate('GearSwap job file unloaded') end
function M.zone_change(...)
    last_dispatch = {}
    stop_shadow_watch()
end
function M.logout(...) return M.deactivate('logout') end
function M.unload(...) return M.deactivate('GearSwap unloaded') end

return M


