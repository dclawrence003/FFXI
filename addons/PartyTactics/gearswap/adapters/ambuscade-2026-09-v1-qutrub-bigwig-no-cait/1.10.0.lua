-- PartyTactics GearSwap adapter: no-Cait Qutrub best-effort fixed actions.
-- Manual callbacks always pass through; this adapter only submits named
-- profile actions through Windower's ordinary input path.

local M = {
    id = 'ambuscade-2026-09-v1-qutrub-bigwig-no-cait',
    version = '1.10.0',
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
local FINISHING_MOVE_BUFF_IDS = {
    [381]=true, [382]=true, [383]=true,
    [384]=true, [385]=true, [588]=true,
}
local BOX_STEP_RECAST_ID = 220
local VIOLENT_FLOURISH_RECAST_ID = 221
local VIOLENT_FLOURISH_ACTION_ID = 207
local NO_FINISHING_MOVES_MESSAGE = 524
local VIOLENT_FLOURISH_FAILURE_BACKOFF = 10
-- Smalls owns the primary exact-target cure lane below 75% HP. The adapter
-- keeps it live outside encounter bind; the runtime mirrors it while bound,
-- and this final edge de-duplicates and revalidates both request paths.
local SUPPORT_CURE_MAX_HPP = 74
local FINAL_TOPUP_MAX_HPP = 20
local TACKLE_EMERGENCY_MAX_HPP = 40
local RDM_ROUTINE_MP_FLOOR = 35
local RDM_CONVERT_MPP = 30
local RDM_CONVERT_RECOVERY_HPP = 90
local RDM_CONVERT_RECOVERY_SECONDS = 20
local RDM_PENDING_TIMEOUT = 8
local RDM_NAME = 'Smalls'
local RDM_DEFENSE = {
    'Achoo','Barneystinson','Dolomedes','Kickpuncher','Tackleberry',
}
local RDM_SPELLS = {
    ['Cure']={id=1, mp_cost=8},
    ['Cure II']={id=2, mp_cost=24},
    ['Cure III']={id=3, mp_cost=46},
    ['Cure IV']={id=4, mp_cost=88},
    ['Protect']={id=43, mp_cost=9},
    ['Protect II']={id=44, mp_cost=28},
    ['Protect III']={id=45, mp_cost=46},
    ['Protect IV']={id=46, mp_cost=65},
    ['Protect V']={id=47, mp_cost=84},
    ['Shell']={id=48, mp_cost=18},
    ['Shell II']={id=49, mp_cost=37},
    ['Shell III']={id=50, mp_cost=56},
    ['Shell IV']={id=51, mp_cost=75},
    ['Shell V']={id=52, mp_cost=93},
    ['Shellra']={id=130, mp_cost=18},
    ['Shellra II']={id=131, mp_cost=37},
    ['Shellra III']={id=132, mp_cost=56},
    ['Shellra IV']={id=133, mp_cost=75},
    ['Shellra V']={id=134, mp_cost=93},
}
local RDM_SHELLRA = {
    'Shellra V','Shellra IV','Shellra III','Shellra II','Shellra',
}
local RDM_SHELL = {'Shell V','Shell IV','Shell III','Shell II','Shell'}
local RDM_PROTECT = {
    'Protect V','Protect IV','Protect III','Protect II','Protect',
}
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
        ['box-step-add']={command='/ja', name='Box Step', target='encounter'},
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
local violent_flourish_backoff_until = 0
local rdm_support = {
    opening_shell_done=false,
    individual_shell=false,
    shell_timers={},
    protect_timers={},
    pending=nil,
    convert_recovery_until=0,
}

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

local function has_finishing_move()
    for id in pairs(FINISHING_MOVE_BUFF_IDS) do
        if has_buff_id(id) then return true end
    end
    return false
end

local function current_tp()
    local current, live = current_player()
    for _, source in ipairs{current,live} do
        local value = type(source) == 'table'
            and (tonumber(source.tp)
                or tonumber(source.vitals and source.vitals.tp)) or nil
        if value then return value end
    end
    return 0
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

local function ability_ready(id)
    if type(windower.ffxi.get_ability_recasts) ~= 'function' then return true end
    local ok, recasts = pcall(windower.ffxi.get_ability_recasts)
    if not ok or type(recasts) ~= 'table' then return true end
    local recast = tonumber(recasts[id])
    return recast == nil or recast <= 0
end

local function current_vital(field, fallback)
    local current, live = current_player()
    for _, source in ipairs{current,live} do
        local value = type(source) == 'table'
            and (tonumber(source[field])
                or tonumber(source.vitals and source.vitals[field])) or nil
        if value ~= nil then return value end
    end
    return fallback
end

local function local_rdm()
    local current, live = current_player()
    local name = current and current.name or live and live.name
    return current_job() == 'RDM' and type(name) == 'string'
        and name:lower() == RDM_NAME:lower()
end

local function automatic_action_ready()
    local current = current_player()
    return current and (tonumber(current.hpp) or 0) > 0
        and not (type(midaction) == 'function' and midaction())
        and not moving
        and not (type(silent_check_disable) == 'function'
            and silent_check_disable())
        and (not tickdelay or os.clock() >= tickdelay)
end

local function learned_spell(spec)
    if not spec then return false end
    local learned = type(windower.ffxi.get_spells) == 'function'
        and windower.ffxi.get_spells() or nil
    if type(learned) == 'table' and learned[spec.id] ~= true then
        return false
    end
    if type(silent_can_use) == 'function' and not silent_can_use(spec.id) then
        return false
    end
    return true
end

local function ready_rdm_spell(choices)
    local mp = current_vital('mp', math.huge)
    for _, name in ipairs(choices) do
        local spec = RDM_SPELLS[name]
        if learned_spell(spec) and spell_ready(spec.id)
            and mp >= (spec.mp_cost or 0)
        then
            return {id=spec.id, en=name, mp_cost=spec.mp_cost or 0}
        end
    end
    return nil
end

local function cure_choices(hpp)
    if hpp < 25 then
        return {'Cure IV','Cure III','Cure II','Cure'}
    elseif hpp < 40 then
        return {'Cure III','Cure IV','Cure II','Cure'}
    end
    return {'Cure III','Cure II','Cure IV','Cure'}
end

local function stop_shadow_watch()
    shadow_watch_enabled = false
    shadow_encounter_id = nil
    shadow_last_count = nil
    next_shadow_observation = 0
    next_shadow_restore = 0
    shadow_pending_until = 0
end

local function reset_rdm_support()
    rdm_support.opening_shell_done = false
    rdm_support.individual_shell = false
    rdm_support.shell_timers = {}
    rdm_support.protect_timers = {}
    rdm_support.pending = nil
    rdm_support.convert_recovery_until = 0
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

local function party_spell_target_in_range(id)
    local mob = type(windower.ffxi.get_mob_by_id) == 'function'
        and windower.ffxi.get_mob_by_id(id) or nil
    if type(mob) ~= 'table' then return false end
    if mob.valid_target == false or (tonumber(mob.hpp) or 0) <= 0 then
        return false
    end
    local distance = tonumber(mob.distance)
    if distance and distance >= 0 then return distance <= 20.5^2 end
    local separation = squared_separation(local_entity(), mob)
    return separation ~= nil and separation <= 20.5^2
end

local function party_member_named(wanted)
    local party = windower.ffxi.get_party() or {}
    for index=0,5 do
        local member = party['p'..tostring(index)]
        if type(member) == 'table' and type(member.name) == 'string'
            and member.name:lower() == wanted:lower()
        then
            local id = tonumber(member.mob and member.mob.id)
            local hpp = tonumber(member.hpp)
            if id and id >= 1 and id <= 4294967295
                and hpp and hpp > 0 and party_spell_target_in_range(id)
            then
                return member, id
            end
        end
    end
    return nil
end

local function lowest_living_party_member(max_hpp)
    local selected, selected_id
    local party = windower.ffxi.get_party() or {}
    for index=0,5 do
        local member = party['p'..tostring(index)]
        local hpp = tonumber(member and member.hpp)
        local id = tonumber(member and member.mob and member.mob.id)
        if type(member) == 'table' and type(member.name) == 'string'
            and hpp and hpp > 0 and hpp <= max_hpp
            and id and id >= 1 and id <= 4294967295
            and party_spell_target_in_range(id)
            and (not selected or hpp < selected.hpp)
        then
            selected = {name=member.name, hpp=hpp}
            selected_id = id
        end
    end
    return selected, selected_id
end

local function post_cast_mpp(spell)
    local mp = current_vital('mp', nil)
    local max_mp = current_vital('max_mp', nil)
    if not mp or not max_mp or max_mp <= 0 then return current_mpp() end
    return math.max(0, mp-(spell.mp_cost or 0))/max_mp*100
end

local function submit_rdm_support_spell(
    semantic, spell, target_id, pending_kind, pending_key, duration, mp_floor)
    local mp = current_vital('mp', nil)
    if not spell or (mp and mp < (spell.mp_cost or 0))
        or not automatic_action_ready() or not spell_ready(spell.id)
        or post_cast_mpp(spell) < (mp_floor or 0)
    then
        return false
    end
    local target = target_id and tostring(target_id) or '<me>'
    local now = os.clock()
    rdm_support.pending = {
        semantic=semantic, spell_id=spell.id, spell_name=spell.en,
        kind=pending_kind, key=pending_key, duration=duration or 0,
        deadline=now+RDM_PENDING_TIMEOUT,
    }
    windower.chat.input('/ma "'..spell.en..'" '..target)
    tickdelay = now + 3
    dispatched = dispatched + 1
    return true
end

local function opening_spell(choices)
    for _, name in ipairs(choices) do
        local spec = RDM_SPELLS[name]
        if learned_spell(spec) then
            return {id=spec.id, en=name, mp_cost=spec.mp_cost or 0}
        end
    end
    return nil
end

local function rdm_opening_defense_tick(now)
    local pending = rdm_support.pending
    if pending then
        if now < (pending.deadline or 0) then return true end
        rdm_support.pending = nil
    end

    -- Let the immutable sortieacuex helper spend its next legal action on
    -- Convert below 30% MP. At 30-34%, reserve the helper tick so its ordinary
    -- maintenance cannot violate this profile's reviewed 35% opening floor.
    if current_mpp() < RDM_CONVERT_MPP then return false end

    if not rdm_support.opening_shell_done then
        local shellra = opening_spell(RDM_SHELLRA)
        if shellra then
            submit_rdm_support_spell(
                'opening-shellra', shellra, nil, 'shellra', nil, 1650, 0)
            return true
        end
        rdm_support.opening_shell_done = true
        rdm_support.individual_shell = true
    end

    if rdm_support.individual_shell then
        for _, name in ipairs(RDM_DEFENSE) do
            if now >= (rdm_support.shell_timers[name:lower()] or 0) then
                local member, id = party_member_named(name)
                local shell = opening_spell(RDM_SHELL)
                if member and shell then
                    submit_rdm_support_spell('opening-shell', shell, id,
                        'shell', name:lower(), 1650, 0)
                    return true
                end
            end
        end
    end

    for _, name in ipairs(RDM_DEFENSE) do
        if now >= (rdm_support.protect_timers[name:lower()] or 0) then
            local member, id = party_member_named(name)
            local protect = opening_spell(RDM_PROTECT)
            if member and protect then
                if current_mpp() < RDM_ROUTINE_MP_FLOOR then return true end
                submit_rdm_support_spell('opening-protect', protect, id,
                    'protect', name:lower(), 1800, RDM_ROUTINE_MP_FLOOR)
                return true
            end
        end
    end
    return current_mpp() >= RDM_CONVERT_MPP
        and current_mpp() < RDM_ROUTINE_MP_FLOOR
end

local function rdm_convert_recovery_tick(now)
    if now > (rdm_support.convert_recovery_until or 0) then return false end
    local hpp = current_vital('hpp', 100)
    if hpp >= RDM_CONVERT_RECOVERY_HPP then
        rdm_support.convert_recovery_until = 0
        return false
    end
    local pending = rdm_support.pending
    if pending then
        if now >= (pending.deadline or 0) then rdm_support.pending = nil end
        return true
    end
    local cure = ready_rdm_spell(cure_choices(hpp))
    if cure then
        submit_rdm_support_spell(
            'convert-recovery', cure, nil, 'convert-recovery', nil, 0, 0)
    end
    -- Recovery owns only this automatic tick. Manual input remains unfiltered.
    return true
end

local function rdm_support_tick()
    if not active or not local_rdm() then return false end
    local info = type(windower.ffxi.get_info) == 'function'
        and windower.ffxi.get_info() or nil
    if not info or not info.logged_in or not ZONES[tonumber(info.zone)] then
        return false
    end
    local now = os.clock()
    if rdm_convert_recovery_tick(now) then return true end

    local pending = rdm_support.pending
    if pending then
        if now >= (pending.deadline or 0) then
            rdm_support.pending = nil
        else
            return true
        end
    end

    local injured, injured_id =
        lowest_living_party_member(SUPPORT_CURE_MAX_HPP)
    if injured then
        -- This local edge preserves support before arm/bind and after finish;
        -- the encounter runtime emits the same exact request while fighting.
        -- A pending record de-duplicates those two entry paths. If no Cure is
        -- usable below 30% MP, yield once so sortieacuex can issue Convert.
        local cure = ready_rdm_spell(cure_choices(injured.hpp))
        if cure then
            submit_rdm_support_spell('support-cure', cure, injured_id,
                'support-cure', injured.name:lower(), 0, 0)
            return true
        end
        return current_mpp() >= RDM_CONVERT_MPP
    end
    return rdm_opening_defense_tick(now)
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
    reset_rdm_support()
    violent_flourish_backoff_until = 0
    return true
end

function M.deactivate(reason)
    active = false
    stop_shadow_watch()
    reset_rdm_support()
    report_lost()
    last_dispatch = {}
    violent_flourish_backoff_until = 0
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
            if not party_spell_target_in_range(subject_id) then
                return true, 'Tackle emergency target is out of range'
            end
        elseif semantic == 'support-cure' then
            if not hpp or hpp <= 0 or hpp > SUPPORT_CURE_MAX_HPP then
                return true, 'support cure target is no longer injured'
            end
            if os.clock() <= (rdm_support.convert_recovery_until or 0) then
                return true, 'post-Convert self recovery has priority'
            end
            local lowest, lowest_id =
                lowest_living_party_member(SUPPORT_CURE_MAX_HPP)
            if not lowest or lowest_id ~= subject_id then
                return true, 'support cure target is no longer the lowest'
            end
            if rdm_support.pending then
                return true, 'profile-local RDM support cast is pending'
            end
            local cure = ready_rdm_spell(cure_choices(hpp))
            if not cure then
                return true, 'support cure is temporarily unavailable'
            end
            if submit_rdm_support_spell('support-cure', cure, subject_id,
                'support-cure', lowest.name:lower(), 0, 0)
            then
                return true, 'submitted'
            end
            return true, 'support cure is waiting for the next legal action'
        elseif semantic == 'lowhp-cure'
            and (not hpp or hpp <= 0 or hpp > FINAL_TOPUP_MAX_HPP)
        then
            return true, 'final-phase top-up target is outside its band'
        end
    elseif action.target == 'self' then
        subject_id = nil
    end
    -- Routine pickup uses Box Step, which both tags the exact add and creates
    -- the finishing move that the old loop incorrectly assumed existed.
    -- Violent Flourish is reserved for reactive stuns and is never submitted
    -- without local stock or while its recast is unavailable. Both outcomes
    -- are successful best-effort no-ops so no other lane or manual input is
    -- delayed by a missing resource.
    if semantic == 'box-step-add' then
        if current_tp() < 100 then
            return true, 'Box Step held: less than 100 TP'
        end
        if not ability_ready(BOX_STEP_RECAST_ID) then
            return true, 'Box Step held: ability is on recast'
        end
    elseif semantic == 'stun-add' then
        if os.clock() < violent_flourish_backoff_until then
            return true, 'Violent Flourish held after no-finishing-move result'
        end
        if not has_finishing_move() then
            return true, 'Violent Flourish held: no finishing move'
        end
        if not ability_ready(VIOLENT_FLOURISH_RECAST_ID) then
            return true, 'Violent Flourish held: ability is on recast'
        end
    end
    return dispatch(semantic, action, subject_id)
end

function M.action_event(action)
    if not active or type(action) ~= 'table'
        or tonumber(action.category) ~= 6
        or tonumber(action.param) ~= VIOLENT_FLOURISH_ACTION_ID
    then return end
    local current, live = current_player()
    local player_id = tonumber(current and current.id)
        or tonumber(live and live.id)
    if tonumber(action.actor_id) ~= player_id then return end
    for _, target in ipairs(action.targets or {}) do
        for _, result in ipairs(target.actions or {}) do
            if tonumber(result.message) == NO_FINISHING_MOVES_MESSAGE then
                -- The buff snapshot can lag the server rejection. Hold this
                -- automatic reaction long enough for local state to settle;
                -- the normal finishing-move check still applies afterward.
                violent_flourish_backoff_until =
                    os.clock() + VIOLENT_FLOURISH_FAILURE_BACKOFF
                return
            end
        end
    end
end

function M.pre_tick()
    return rdm_support_tick()
end

function M.user_job_tick()
    return rdm_support_tick()
end

function M.job_aftercast(spell, spell_map, event_args)
    local name = type(spell) == 'table'
        and (spell.english or spell.en or spell.name) or nil
    if name == 'Convert' and not spell.interrupted and local_rdm() then
        rdm_support.convert_recovery_until =
            os.clock() + RDM_CONVERT_RECOVERY_SECONDS
    end

    local pending = rdm_support.pending
    if not pending or type(spell) ~= 'table'
        or (tonumber(spell.id) ~= pending.spell_id
            and name ~= pending.spell_name)
    then
        return
    end
    if not spell.interrupted then
        if pending.kind == 'shellra' then
            rdm_support.opening_shell_done = true
        elseif pending.kind == 'shell' and pending.key then
            rdm_support.shell_timers[pending.key] =
                os.clock() + (pending.duration or 1650)
        elseif pending.kind == 'protect' and pending.key then
            rdm_support.protect_timers[pending.key] =
                os.clock() + (pending.duration or 1800)
        end
    end
    rdm_support.pending = nil
end

function M.prerender()
    rdm_support_tick()
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
    return ('best-effort manual-pass-through shadows=%s/%d rdm-opening=%s '
        ..'rdm-recovery=%s dispatched=%d rejected=%d')
        :format(shadow_watch_enabled and 'reactive' or 'off',
            copy_image_count(), rdm_support.opening_shell_done and 'shell' or 'pending',
            os.clock() <= (rdm_support.convert_recovery_until or 0)
                and 'active' or 'off', dispatched, rejected)
end

function M.file_unload(...) return M.deactivate('GearSwap job file unloaded') end
function M.zone_change(...)
    last_dispatch = {}
    violent_flourish_backoff_until = 0
    stop_shadow_watch()
    reset_rdm_support()
end
function M.logout(...) return M.deactivate('logout') end
function M.unload(...) return M.deactivate('GearSwap unloaded') end

return M
