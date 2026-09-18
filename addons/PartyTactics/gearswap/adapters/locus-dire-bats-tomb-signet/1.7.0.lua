-- PartyTactics GearSwap adapter for the isolated Locus Signet profile.
--
-- This module owns no equipment set and exposes no arbitrary action surface.
-- It binds three companion add-ons to one PartyTactics generation, suppresses
-- automatic GearSwap callbacks only during the Signet staff transaction, and
-- gives Tackleberry's Flash opener one independently bounded automatic-action
-- reservation. It also keeps the generic native AutoTank loop off on Tackle
-- so LocusPuller is the sole owner of Flash. This revision owns one narrow,
-- low-frequency Majesty cure lane on Tackle instead of activating the frozen
-- shared PLD helper. Manual actions always pass through.

local M = {
    id='locus-dire-bats-tomb-signet',
    version='1.7.0',
    controller='locus-signet',
    protocol=2,
}

local PROFILE_ID = M.id
local PROFILE_VERSION = M.version
local ENGINE_VERSION = '0.13.3'
local ZONE = 190
local LEADER = 'Dolomedes'
local ROSTER = 'Achoo,Barneystinson,Dolomedes,Kickpuncher,Smalls,Tackleberry'
-- LocusPuller legally waits up to eight seconds for Flash confirmation and
-- twenty more for a distant flashed bat to reach first melee. PartyOps
-- observed a 16.462-second Flash-to-melee maximum at this camp, so the
-- adapter's outer reservation must outlive that complete helper window while
-- remaining independently bounded.
local OPENER_TTL = 30
local RELOAD_HANDOFF_TTL = 20
local KEEPER_RECOVERY_RETRY_INTERVAL = 3
local AUTHORIZATION_TTL = 12
local TERMINAL_REASSERT_DELAY = 2
local COMPANION_LOAD_RETRY_INTERVAL = 6

-- PartyOps measured 402,136 HP restored by 283 Cure III casts against only
-- 34,203 HP of actual party damage across 118 kills. The old shared 82/90
-- thresholds were reacting primarily to max-HP equipment changes. This
-- profile-local policy waits for meaningful damage while retaining a separate
-- emergency lane. Thresholds are strict: exactly 65/70/55 is held.
local PLD_ROUTINE_HPP = 65
local PLD_CLUSTER_HPP = 70
local PLD_CLUSTER_COUNT = 3
local PLD_EMERGENCY_HPP = 55
local PLD_ROUTINE_MP_FLOOR = 30
local PLD_PARTY_RANGE = 20.5
local PLD_PENDING_TTL = 5
local PLD_RETRY_AFTER_INTERRUPT = 1.5
local PLD_RETRY_AFTER_CURE = 1
local PLD_MAJESTY_ACTION_ID = 394
local PLD_MAJESTY_RECAST_ID = 150
local PLD_SPELLS = {
    ['Cure III']={id=3, mp_cost=46},
    ['Cure IV']={id=4, mp_cost=88},
}

local EXPECTED = {
    Achoo={job='GEO'},
    Barneystinson={job='BRD'},
    Dolomedes={job='COR'},
    Kickpuncher={job='DNC'},
    Smalls={job='RDM'},
    Tackleberry={job='PLD'},
}

local HELPER = {
    BRD='pstartbrd', RDM='pstartrdm', GEO='pstartgeo',
    PLD='pstartpld', DNC='pstartdnc',
}

local state = {
    active=false,
    authority=nil,
    suspended=false,
    opener=nil,
    maintenance_cycle=nil,
    cycle_phase=nil,
    reload_handoff=nil,
    keeper_instance_nonce=nil,
    keeper_recovery=nil,
    authorization=nil,
    companion_ready={},
    companion_load_attempts={},
    companion_generation=nil,
    companion_epoch=nil,
    next_companion_load_at=0,
    controller_announced=false,
    terminal_reassert_at=nil,
    terminal_job=nil,
    retired_tuples={},
    retired_generations={},
    operator_revision=0,
    operator_armed=false,
    accepted=0,
    rejected=0,
    opener_timeouts=0,
    native_tank_commanded=false,
    pld_pending=nil,
    pld_retry_at=0,
    pld_cures=0,
    pld_majesty=0,
    pld_timeouts=0,
    pld_last='idle',
    last='inactive',
}

if rawget(_G, 'PARTYTACTICS_LOCUS_SIGNET_TEST_MODE') == true then
    M._test_state = state
end

local function now()
    return os.clock()
end

local function chat(message, color)
    if type(add_to_chat) == 'function' then
        add_to_chat(color or 207, '[PartyTactics Locus Signet] '..message)
    end
end

local function issue(command)
    if type(windower) == 'table'
        and type(windower.send_command) == 'function'
    then
        windower.send_command(command)
        return true
    end
    return false
end

local function valid_generation(value)
    if type(value) ~= 'string' or #value < 5 or #value > 64 then
        return false
    end
    local first, second, third = value:match('^(%d+)%-(%d+)%-(%d+)$')
    local function canonical(part)
        return part and (part == '0' or part:sub(1, 1) ~= '0')
    end
    return canonical(first) and canonical(second) and canonical(third)
end

local function valid_epoch(value)
    if type(value) ~= 'string' or #value < 1 or #value > 12
        or value:match('^%d+$') == nil
    then
        return nil
    end
    local number = tonumber(value)
    return number and number >= 0 and number == math.floor(number)
        and number or nil
end

local function valid_revision(value)
    if type(value) ~= 'string' or #value < 1 or #value > 10
        or value:match('^%d+$') == nil
        or (#value > 1 and value:sub(1, 1) == '0')
    then
        return nil
    end
    local revision = tonumber(value)
    return revision and revision >= 0 and revision <= 2147483647
        and revision == math.floor(revision) and revision or nil
end

local function valid_cycle(value)
    local cycle = valid_epoch(value)
    return cycle and cycle >= 1 and cycle <= 2147483647 and cycle or nil
end

local function valid_signature(value)
    return type(value) == 'string' and #value == 8
        and value:match('^[0-9a-f]+$') ~= nil
end

local function valid_instance_nonce(value)
    if type(value) ~= 'string' or #value < 3 or #value > 33 then
        return nil
    end
    local wall_text, clock_text = value:match('^(%d+)%-(%d+)$')
    local function canonical(part)
        return part and #part <= 16
            and (part == '0' or part:sub(1, 1) ~= '0')
    end
    if not canonical(wall_text) or not canonical(clock_text) then return nil end
    local wall, clock = tonumber(wall_text), tonumber(clock_text)
    local max_exact_integer = 9007199254740991
    if not wall or not clock or wall < 0 or clock < 0
        or wall > max_exact_integer or clock > max_exact_integer
        or wall ~= math.floor(wall) or clock ~= math.floor(clock)
    then
        return nil
    end
    return {token=value, wall=wall, clock=clock}
end

local function compare_instance_nonce(left, right)
    if left.clock ~= right.clock then
        return left.clock < right.clock and -1 or 1
    end
    if left.wall ~= right.wall then
        return left.wall < right.wall and -1 or 1
    end
    return 0
end

local function uint32(value)
    if type(value) ~= 'string' or #value < 1 or #value > 10
        or value:match('^%d+$') == nil
    then
        return nil
    end
    local number = tonumber(value)
    return number and number >= 1 and number <= 4294967295
        and number == math.floor(number) and number or nil
end

local function player()
    local live = type(windower) == 'table' and windower.ffxi
        and type(windower.ffxi.get_player) == 'function'
        and windower.ffxi.get_player() or nil
    if type(live) == 'table' then return live end
    return type(_G.player) == 'table' and _G.player or nil
end

local function in_tomb()
    local info = type(windower) == 'table' and windower.ffxi
        and type(windower.ffxi.get_info) == 'function'
        and windower.ffxi.get_info() or nil
    return type(info) == 'table' and info.logged_in ~= false
        and tonumber(info.zone) == ZONE
end

local function local_identity()
    local current = player()
    local name = current and current.name or nil
    local expected = name and EXPECTED[name] or nil
    if not expected or current.main_job ~= expected.job then
        return nil, nil, nil
    end
    return name, expected.job, current.sub_job
end

local function reserve_flash_for_puller()
    local name, job = local_identity()
    if name ~= 'Tackleberry' or job ~= 'PLD' then return end
    local gearswap_state = rawget(_G, 'state')
    local tank_mode = type(gearswap_state) == 'table'
        and gearswap_state.AutoTankMode or nil
    if type(tank_mode) ~= 'table' then
        if not state.native_tank_commanded then
            issue('gs c unset AutoTankMode')
            state.native_tank_commanded = true
        end
        return
    end

    state.native_tank_commanded = true
    if tank_mode.value ~= true then return end
    -- Mutate only Selindrile's boolean mode object. This is silent, immediate,
    -- and equipment-neutral; the profile-local PLD helper, AutoBuffMode, and
    -- every manual action remain untouched.
    if type(tank_mode.unset) == 'function' then
        tank_mode:unset()
    elseif type(tank_mode.set) == 'function' then
        tank_mode:set(false)
    else
        issue('gs c unset AutoTankMode')
    end
end

local function reset_pld_sustain()
    state.pld_pending = nil
    state.pld_retry_at = 0
    state.pld_cures = 0
    state.pld_majesty = 0
    state.pld_timeouts = 0
    state.pld_last = 'idle'
end

local function current_vital(field, fallback)
    local current = player()
    local direct = current and tonumber(current[field]) or nil
    if direct ~= nil then return direct end
    local vitals = current and current.vitals or nil
    local nested = type(vitals) == 'table' and tonumber(vitals[field]) or nil
    if nested ~= nil then return nested end
    if field == 'mpp' then
        local mp = current_vital('mp', nil)
        local max_mp = current_vital('max_mp', nil)
        if mp and max_mp and max_mp > 0 then return mp / max_mp * 100 end
    end
    return fallback
end

local function pld_input(command)
    local chat_api = type(windower) == 'table' and windower.chat or nil
    if type(chat_api) == 'table' and type(chat_api.input) == 'function' then
        chat_api.input(command)
        return true
    end
    return false
end

local function pld_member_id(member)
    return tonumber(member and member.mob and member.mob.id)
        or tonumber(member and member.mob_id)
        or tonumber(member and member.id)
end

local function pld_member_in_range(member, local_name)
    if type(member) ~= 'table' or type(member.name) ~= 'string' then
        return false
    end
    if member.name:lower() == local_name:lower() then return true end
    local mob = type(member.mob) == 'table' and member.mob or nil
    local id = pld_member_id(member)
    if (not mob or tonumber(mob.distance) == nil) and id
        and type(windower.ffxi.get_mob_by_id) == 'function'
    then
        mob = windower.ffxi.get_mob_by_id(id)
    end
    if (not mob or tonumber(mob.distance) == nil)
        and type(windower.ffxi.get_mob_by_name) == 'function'
    then
        mob = windower.ffxi.get_mob_by_name(member.name)
    end
    local distance = tonumber(mob and mob.distance)
    return distance ~= nil and distance >= 0
        and math.sqrt(distance) <= PLD_PARTY_RANGE
end

local function pld_scan_party(local_name)
    local lowest, cluster = nil, 0
    local party = type(windower.ffxi.get_party) == 'function'
        and windower.ffxi.get_party() or {}
    for slot=0,5 do
        local member = party['p'..tostring(slot)]
        local hpp = tonumber(member and member.hpp)
        local id = pld_member_id(member)
        if type(member) == 'table' and type(member.name) == 'string'
            and hpp and hpp > 0 and id and id >= 1 and id <= 4294967295
            and pld_member_in_range(member, local_name)
        then
            if hpp < PLD_CLUSTER_HPP then cluster = cluster + 1 end
            if not lowest or hpp < lowest.hpp then
                lowest = {
                    name=member.name,
                    hpp=hpp,
                    id=id,
                    token=slot == 0 and '<me>' or ('<p%d>'):format(slot),
                }
            end
        end
    end
    return lowest, cluster
end

local function pld_learned_spell(spec)
    if not spec then return false end
    local learned = type(windower.ffxi.get_spells) == 'function'
        and windower.ffxi.get_spells() or nil
    if type(learned) == 'table'
        and learned[spec.id] ~= true and learned[spec.id] ~= 1
    then
        return false
    end
    return type(silent_can_use) ~= 'function' or silent_can_use(spec.id)
end

local function pld_ready_spell(choices)
    local recasts = type(windower.ffxi.get_spell_recasts) == 'function'
        and windower.ffxi.get_spell_recasts() or {}
    local threshold = tonumber(rawget(_G, 'spell_latency')) or 0.5
    local mp = current_vital('mp', 0)
    for _, spell_name in ipairs(choices) do
        local spec = PLD_SPELLS[spell_name]
        if pld_learned_spell(spec)
            and (tonumber(recasts[spec.id]) or 0) < threshold
            and mp >= spec.mp_cost
        then
            return {id=spec.id, name=spell_name, mp_cost=spec.mp_cost}
        end
    end
    return nil
end

local function pld_known_majesty()
    local abilities = type(windower.ffxi.get_abilities) == 'function'
        and windower.ffxi.get_abilities() or nil
    if type(abilities) ~= 'table'
        or type(abilities.job_abilities) ~= 'table'
    then
        return true
    end
    for _, id in ipairs(abilities.job_abilities) do
        if tonumber(id) == PLD_MAJESTY_ACTION_ID then return true end
    end
    return false
end

local function pld_has_majesty()
    local buffs = rawget(_G, 'buffactive')
    return type(buffs) == 'table'
        and (buffs.Majesty or buffs['Majesty']) and true or false
end

local function pld_majesty_ready()
    if not pld_known_majesty()
        or type(silent_check_amnesia) == 'function' and silent_check_amnesia()
    then
        return false
    end
    local recasts = type(windower.ffxi.get_ability_recasts) == 'function'
        and windower.ffxi.get_ability_recasts() or {}
    local threshold = tonumber(rawget(_G, 'latency')) or 0.5
    return (tonumber(recasts[PLD_MAJESTY_RECAST_ID]) or 999) < threshold
end

local function expire_pld_pending()
    local pending = state.pld_pending
    if not pending or now() < (pending.expires or 0) then
        return pending ~= nil
    end
    state.pld_pending = nil
    state.pld_retry_at = now() + PLD_RETRY_AFTER_INTERRUPT
    state.pld_timeouts = state.pld_timeouts + 1
    state.pld_last = (pending.name or 'PLD sustain action')
        ..' dispatch unconfirmed; bounded retry armed'
    return false
end

local function pld_claim(kind, id, name, target)
    state.pld_pending = {
        kind=kind, id=id, name=name, target=target,
        expires=now() + PLD_PENDING_TTL,
    }
end

local function pld_automatic_ready()
    local name, job = local_identity()
    local current = player()
    return state.active and state.authority ~= nil
        and name == 'Tackleberry' and job == 'PLD' and in_tomb()
        and current and (current.status == 1 or current.status == 'Engaged')
        and current_vital('hpp', 0) > 0
        and not (type(midaction) == 'function' and midaction())
        and not rawget(_G, 'moving')
        and not (type(silent_check_disable) == 'function'
            and silent_check_disable())
        and (not rawget(_G, 'tickdelay') or now() >= tickdelay)
        and now() >= (state.pld_retry_at or 0)
end

local function pld_submit_majesty()
    if not pld_majesty_ready() then return false end
    pld_claim('majesty', PLD_MAJESTY_ACTION_ID, 'Majesty')
    if not pld_input('/ja "Majesty" <me>') then
        state.pld_pending = nil
        return false
    end
    tickdelay = now() + 1.5
    state.pld_majesty = state.pld_majesty + 1
    state.pld_last = 'Majesty for profile-local sustain cure'
    return true
end

local function pld_cure_choices(reason)
    if reason == 'emergency' then
        return {'Cure IV','Cure III'}
    end
    return {'Cure III'}
end

local function pld_submit_cure(target, reason)
    local spell = pld_ready_spell(pld_cure_choices(reason))
    if not spell then return false end
    pld_claim('cure', spell.id, spell.name, target.id)
    if not pld_input(('/ma "%s" %s'):format(spell.name, target.token)) then
        state.pld_pending = nil
        return false
    end
    tickdelay = now() + 2.5
    state.pld_last = ('%s -> %s (%d%%, %s)')
        :format(spell.name, target.name, target.hpp, reason)
    return true
end

local function pld_sustain_tick()
    if expire_pld_pending() then return true end
    if not pld_automatic_ready() then return false end
    if now() < (state.pld_retry_at or 0) then return false end

    local name = local_identity()
    local lowest, cluster = pld_scan_party(name)
    if not lowest then return false end
    local reason
    if lowest.hpp < PLD_EMERGENCY_HPP then
        reason = 'emergency'
    elseif current_vital('mpp', 0) < PLD_ROUTINE_MP_FLOOR then
        return false
    elseif lowest.hpp < PLD_ROUTINE_HPP then
        reason = 'routine'
    elseif cluster >= PLD_CLUSTER_COUNT then
        reason = 'cluster'
    else
        return false
    end

    if not pld_has_majesty() then
        if pld_submit_majesty() then return true end
        -- A cluster-only top-up has no reason to become a single-target cure.
        -- Routine and emergency recovery still fail soft when Majesty is down.
        if reason == 'cluster' then return false end
    end
    return pld_submit_cure(lowest, reason)
end

local function pld_aftercast(spell)
    local pending = state.pld_pending
    if not pending or type(spell) ~= 'table' then return end
    local spell_name = spell.english or spell.en or spell.name
    local matches = tonumber(spell.id) == pending.id
        or pending.kind == 'majesty'
            and (tonumber(spell.recast_id) == PLD_MAJESTY_RECAST_ID
                or spell_name == 'Majesty')
        or spell_name == pending.name
    if not matches then return end
    local target_id = tonumber(type(spell.target) == 'table' and spell.target.id)
    if pending.kind == 'cure' and target_id and target_id ~= pending.target then
        return
    end

    state.pld_pending = nil
    if spell.interrupted then
        state.pld_retry_at = now() + PLD_RETRY_AFTER_INTERRUPT
        state.pld_last = pending.name..' interrupted; bounded retry armed'
    elseif pending.kind == 'cure' then
        state.pld_cures = state.pld_cures + 1
        state.pld_retry_at = now() + PLD_RETRY_AFTER_CURE
    else
        state.pld_retry_at = now() + 0.5
    end
end

local function terminal_baseline(job)
    -- This profile can be re-applied best-effort after a zone event. Its
    -- rejection therefore needs a complete local OFF baseline instead of
    -- assuming a later compiler teardown will run.
    local commands = {
        'pc localstop',
        'aws2 off',
        'hb follow off',
        'hb db off',
        'hb as off',
        'hb as attack off',
        'hb off',
        'gs c unset AutoWSMode',
    }
    if job == 'COR' then
        commands[#commands + 1] = 'r2 off'
    end
    local helper = HELPER[job]
    if helper then
        commands[#commands + 1] = 'gs c '..helper..' off'
    end
    if job == 'RDM' or job == 'PLD' or job == 'DNC' or job == 'GEO' then
        commands[#commands + 1] = 'gs c set AutoBuffMode Off'
    end
    if job == 'PLD' then
        commands[#commands + 1] = 'gs c unset AutoTankMode'
        commands[#commands + 1] = 'gs c unset AutoTankFull'
    elseif job == 'DNC' then
        commands[#commands + 1] = 'gs c unset AutoPrestoMode'
        commands[#commands + 1] = 'gs c set AutoSambaMode Off'
        commands[#commands + 1] = 'gs c set DanceStance None'
    elseif job == 'GEO' then
        commands[#commands + 1] = 'gs c set CombatEntrustOnly'
    end
    return table.concat(commands, '; ')
end

local function cancel_terminal_reassert()
    state.terminal_reassert_at = nil
    state.terminal_job = nil
end

local function terminal_off(job, reason)
    local baseline = terminal_baseline(job)
    state.authorization = nil
    reset_pld_sustain()
    -- Offense compilation intentionally waits one second after changing a
    -- weapon mode before enabling AutoWS2, and an armed commit can queue PC ON
    -- immediately after its controller probe. Apply now, then let this exact
    -- adapter instance reassert once after those older queued commands drain.
    -- The retry is adapter-owned rather than embedded in a raw Windower wait:
    -- profile replacement/deactivation cancels it, so it cannot turn a later
    -- unrelated profile back off.
    issue(baseline)
    state.terminal_job = job
    state.terminal_reassert_at = now() + TERMINAL_REASSERT_DELAY
    state.last = reason or 'terminal local automation baseline applied'
end

local function expire_terminal_reassert()
    if not state.terminal_reassert_at
        or now() < state.terminal_reassert_at
    then
        return false
    end
    local job = state.terminal_job
    cancel_terminal_reassert()
    issue(terminal_baseline(job))
    state.last = 'terminal local automation baseline reasserted'
    return true
end

local function same_authority(generation, epoch_value, protocol_value)
    local authority = state.authority
    return authority ~= nil
        and generation == authority.generation
        and valid_epoch(epoch_value) == authority.epoch
        and tonumber(protocol_value) == M.protocol
end

local function authority_key(generation, epoch)
    return tostring(generation)..'/'..tostring(epoch)
end

local function retire_authority(authority)
    if not authority then return end
    state.retired_tuples[authority_key(
        authority.generation, authority.epoch)] = true
end

local function authority_retired(generation, epoch)
    return state.retired_generations[generation] == true
        or state.retired_tuples[authority_key(generation, epoch)] == true
end

local function valid_reload_handoff(current, generation, epoch)
    local handoff = state.reload_handoff
    return type(handoff) == 'table' and now() <= handoff.expires
        and epoch == 0 and generation ~= handoff.generation
        and (not current or current.generation == handoff.generation
            and current.epoch == handoff.epoch)
end

local function announce_lost(authority, reason)
    if not authority then return end
    issue(('pt __controller_lost %s %s %d %d'):format(
        M.controller, authority.generation, authority.epoch, M.protocol))
    state.last = reason or 'controller authority released'
end

local function companion_detach(authority, keep_automatic_off)
    if not authority then return end
    -- Raw logout/zone callbacks may run after Windower has already removed
    -- the live player object. The identity captured by the validated probe is
    -- the teardown authority; never guess from a later client snapshot.
    local name = authority.name
    if name == 'Dolomedes' then
        issue(('jk detach %s %d'):format(
            authority.generation, authority.epoch))
    elseif name == 'Tackleberry' then
        issue(('lp unbindpt %s %d%s'):format(
            authority.generation, authority.epoch,
            keep_automatic_off and ' keepoff' or ''))
    end
    -- Detach the local slot/puller owner first. In particular, Tackle's
    -- keepoff release must be queued before a distributed SK detach can retire
    -- the authority used to validate it.
    issue(('sk detach %s %d'):format(
        authority.generation, authority.epoch))
end

local function release_opener(reason, restore_automatic)
    if not state.opener then return false end
    state.opener = nil
    if restore_automatic ~= false and not state.suspended
        and not state.reload_handoff
    then
        issue('aws2 on')
    end
    state.last = reason or 'PLD opener released'
    return true
end

local function clear_local(reason, notify_lost, restore_automatic)
    local authority = state.authority
    retire_authority(authority)
    companion_detach(authority, not restore_automatic)
    if restore_automatic and (state.opener or state.suspended) then
        -- Only a genuine adapter exception fails open. Normal profile stop,
        -- replacement, zone/logout, and GearSwap teardown must leave the
        -- compiler's later OFF commands authoritative.
        issue('aws2 on')
    end
    if restore_automatic and state.suspended then
        local job = authority and authority.job or nil
        if job == 'COR' then issue('r2 on') end
        if job == 'RDM' then
            issue('hb deactivateindoors off; hb disable cure; hb enable na; '
                ..'hb disable buff; hb db off; hb as off; '
                ..'hb as attack off; hb on')
        end
    end
    state.opener = nil
    state.suspended = false
    state.maintenance_cycle = nil
    state.cycle_phase = nil
    state.reload_handoff = nil
    state.keeper_recovery = nil
    state.companion_ready = {}
    state.companion_load_attempts = {}
    state.companion_generation = nil
    state.companion_epoch = nil
    state.next_companion_load_at = 0
    state.controller_announced = false
    state.native_tank_commanded = false
    reset_pld_sustain()
    state.authority = nil
    if notify_lost then announce_lost(authority, reason) end
    state.last = reason or 'local state cleared'
end

local function companion_is_required(name, helper)
    return helper == 'sk'
        or helper == 'lp' and name == 'Tackleberry'
        or helper == 'jk' and name == 'Dolomedes'
end

local function companions_are_ready(name)
    if not state.companion_ready.sk then return false end
    if name == 'Tackleberry' and not state.companion_ready.lp then
        return false
    end
    if name == 'Dolomedes' and not state.companion_ready.jk then
        return false
    end
    return true
end

local function prepare_companion_tuple(generation, epoch)
    if state.companion_generation == generation
        and state.companion_epoch == epoch
    then
        return
    end
    local first_tuple = state.companion_generation == nil
    state.companion_generation = generation
    state.companion_epoch = epoch
    state.companion_ready = {}
    if not first_tuple then
        state.companion_load_attempts = {}
        state.next_companion_load_at = 0
    end
    state.controller_announced = false
end

local function announce_controller_ready(force)
    local authority = state.authority
    if not authority or state.keeper_recovery
        or not companions_are_ready(authority.name)
    then
        return false
    end
    if force or not state.controller_announced then
        issue(('pt __controller_ready %s %s %d %d'):format(
            M.controller, authority.generation, authority.epoch, M.protocol))
        state.controller_announced = true
    end
    return true
end

local function apply_keeper_recovery_off(authority)
    if not authority then return end
    release_opener('SignetKeeper instance changed; automatic lanes held', false)
    state.pld_pending = nil
    state.pld_retry_at = 0
    terminal_off(authority.job,
        'SignetKeeper instance changed; automatic lanes held')
end

local function request_keeper_recovery(recovery)
    local authority = state.authority
    if not recovery or not authority
        or authority.generation ~= recovery.generation
        or authority.epoch ~= recovery.epoch
    then
        return false
    end
    -- A raw SignetKeeper reload occurs independently on all six clients. Bind
    -- each fresh local instance back to the exact old authority, then use the
    -- keeper's existing reload-request IPC. That path coalesces every request
    -- at the configured leader before exactly one PartyTactics successor is
    -- created. Calling PartyTactics directly here would let six simultaneous
    -- reloads race six replacement generations against one another.
    issue(('sk armpt %s %d %s %s %s %s %s %s %d %s; '
            ..'sk __ackpt %s %d; sk gsreload %s %d')
        :format(authority.generation, authority.epoch, LEADER, ROSTER,
            PROFILE_ID, PROFILE_VERSION, ENGINE_VERSION,
            authority.signature,
            tonumber(authority.operator_revision) or 0,
            authority.operator_armed and '1' or '0',
            authority.generation, authority.epoch,
            authority.generation, authority.epoch))
    recovery.next_attempt = now() + KEEPER_RECOVERY_RETRY_INTERVAL
    return true
end

local function begin_keeper_recovery(nonce)
    local authority = state.authority
    if not authority then return false end

    -- A second raw keeper reload while recovery is already pending advances
    -- only the process-local nonce high-water. It must not prolong the fixed
    -- twenty-second authority window or create a second recovery transaction.
    if state.keeper_recovery then
        state.keeper_recovery.nonce = nonce
        state.last = 'newer SignetKeeper instance coalesced into pending recovery'
        return true
    end

    apply_keeper_recovery_off(authority)
    state.reload_handoff = {
        generation=authority.generation,
        epoch=authority.epoch,
        operator_revision=tonumber(authority.operator_revision) or 0,
        operator_armed=authority.operator_armed == true,
        expires=now() + RELOAD_HANDOFF_TTL,
    }
    state.keeper_recovery = {
        generation=authority.generation,
        epoch=authority.epoch,
        nonce=nonce,
        expires=state.reload_handoff.expires,
        next_attempt=now(),
    }
    request_keeper_recovery(state.keeper_recovery)
    state.last = 'new SignetKeeper instance detected; full-profile recovery pending'
    return true
end

local function tick_keeper_recovery()
    local recovery = state.keeper_recovery
    if not recovery then return end
    local clock = now()
    if clock >= recovery.expires then
        local authority = state.authority
        clear_local('SignetKeeper recovery expired; automatic lanes remain off',
            true, false)
        state.keeper_instance_nonce = nil
        terminal_off(authority and authority.job or nil,
            'SignetKeeper recovery expired; old authority terminally fenced')
        state.active = false
        state.last = authority
            and 'SignetKeeper recovery expired; old authority terminally fenced'
            or 'SignetKeeper recovery expired with no current authority'
        return
    end
    if not state.authority
        or state.authority.generation ~= recovery.generation
        or state.authority.epoch ~= recovery.epoch
    then
        state.keeper_recovery = nil
        return
    end
    if clock >= recovery.next_attempt then
        request_keeper_recovery(recovery)
    end
end

local function observe_keeper_instance(nonce)
    local prior = state.keeper_instance_nonce
    if not prior then
        state.keeper_instance_nonce = nonce
        return true, false, 'SignetKeeper instance baseline recorded'
    end
    local ordering = compare_instance_nonce(nonce, prior)
    if ordering < 0 then
        return false, false, 'delayed SignetKeeper instance nonce ignored'
    elseif ordering == 0 then
        return true, false, 'SignetKeeper instance already recorded'
    end
    state.keeper_instance_nonce = nonce
    begin_keeper_recovery(nonce)
    return true, true, 'new SignetKeeper instance recovery requested'
end

local function keeper_instance(arguments)
    local nonce = #arguments == 1 and valid_instance_nonce(arguments[1]) or nil
    local authority = state.authority
    local name, job = local_identity()
    if not nonce or not state.active or not authority or not name
        or not in_tomb() or authority.name ~= name or authority.job ~= job
    then
        return false, 'keeper instance requires current local profile authority'
    end
    local accepted, _, reason = observe_keeper_instance(nonce)
    return accepted, reason
end

local function companion_ready(arguments)
    local generation = arguments[1]
    local epoch = valid_epoch(arguments[2])
    local protocol = tonumber(arguments[3])
    local helper = arguments[4]
    local name, job = local_identity()
    local authority = state.authority
    local nonce = helper == 'sk' and valid_instance_nonce(arguments[11]) or nil
    local exact_arity = helper == 'sk' and #arguments == 11
        or helper ~= 'sk' and #arguments == 10
    if not exact_arity or helper == 'sk' and not nonce
        or not authority or not name or not in_tomb()
        or authority_retired(generation, epoch)
        or not companion_is_required(name, helper)
        or generation ~= authority.generation or epoch ~= authority.epoch
        or protocol ~= M.protocol
        or arguments[5] ~= PROFILE_ID
        or arguments[6] ~= PROFILE_VERSION
        or arguments[7] ~= ENGINE_VERSION
        or arguments[8] ~= authority.signature
        or arguments[9] ~= name or arguments[10] ~= job
        or authority.name ~= name or authority.job ~= job
        or state.companion_generation ~= generation
        or state.companion_epoch ~= epoch
    then
        return false, 'companion ACK does not match current local authority'
    end
    if helper == 'sk' then
        local accepted, _, reason = observe_keeper_instance(nonce)
        if not accepted then return false, reason end
    end
    state.companion_ready[helper] = true
    announce_controller_ready(false)
    return true, 'companion readiness recorded'
end

local function request_missing_companion_loads(name)
    if now() < (state.next_companion_load_at or 0) then return end
    local issued = false
    if not state.companion_ready.sk
        and (state.companion_load_attempts.sk or 0) < 2
    then
        issue('lua load SignetKeeper')
        state.companion_load_attempts.sk =
            (state.companion_load_attempts.sk or 0) + 1
        issued = true
    end
    if name == 'Dolomedes' and not state.companion_ready.jk
        and (state.companion_load_attempts.jk or 0) < 2
    then
        issue('lua load JubileeKeeper')
        state.companion_load_attempts.jk =
            (state.companion_load_attempts.jk or 0) + 1
        issued = true
    elseif name == 'Tackleberry' and not state.companion_ready.lp
        and (state.companion_load_attempts.lp or 0) < 2
    then
        issue('lua load LocusPuller')
        state.companion_load_attempts.lp =
            (state.companion_load_attempts.lp or 0) + 1
        issued = true
    end
    if issued then
        state.next_companion_load_at = now()
            + COMPANION_LOAD_RETRY_INTERVAL
    end
end

local function bootstrap_companions(authority, name)
    -- Helpers were loaded inert during adapter activation. Rechecking the
    -- exact zone here makes the authority handoff atomic with respect to a
    -- zoning event; no delayed `wait` can arm ownership after Tomb departure.
    if not in_tomb() then return false end
    local keeper = ('sk armpt %s %d %s %s %s %s %s %s %d %s; '
            ..'sk __ackpt %s %d'):format(
            authority.generation, authority.epoch, LEADER, ROSTER,
            PROFILE_ID, PROFILE_VERSION, ENGINE_VERSION,
            authority.signature, tonumber(authority.operator_revision) or 0,
            authority.operator_armed and '1' or '0',
            authority.generation, authority.epoch)
    if name == 'Tackleberry' then
        -- Bind the puller before SignetKeeper observes/replays the initial
        -- PartyTactics operator bit. One Windower command queue makes this
        -- ordering deterministic even when both add-ons were initially off.
        issue(('lp bindpt %s %d %s %s %s %s %s %s %d %s; '
                ..'lp __ackpt %s %d; %s')
            :format(authority.generation, authority.epoch,
                PROFILE_ID, PROFILE_VERSION, ENGINE_VERSION,
                authority.signature, LEADER, ROSTER,
                tonumber(authority.operator_revision) or 0,
                authority.operator_armed and '1' or '0',
                authority.generation, authority.epoch, keeper))
    else
        issue(keeper)
    end
    if name == 'Dolomedes' then
        issue(('jk armpt %s %d %s %s %s %s %s %s; jk __ackpt %s %d')
            :format(authority.generation, authority.epoch,
                PROFILE_ID, PROFILE_VERSION, ENGINE_VERSION,
                authority.signature, LEADER, ROSTER,
                authority.generation, authority.epoch))
    end
    return true
end

local function authorize(arguments)
    local generation = arguments[1]
    local epoch = valid_epoch(arguments[2])
    local protocol = tonumber(arguments[3])
    local signature = arguments[6]
    local operator_revision = valid_revision(arguments[9])
    local operator_bit = arguments[10]
    local name = local_identity()
    if #arguments ~= 10 or not name or not in_tomb()
        or not valid_generation(generation) or epoch == nil
        or protocol ~= M.protocol
        or arguments[4] ~= PROFILE_ID
        or arguments[5] ~= PROFILE_VERSION
        or not valid_signature(signature)
        or arguments[7] ~= LEADER or arguments[8] ~= ROSTER
        or operator_revision == nil
        or (operator_bit ~= '0' and operator_bit ~= '1')
        or authority_retired(generation, epoch)
    then
        return false, 'exact committed profile authorization required'
    end
    local current = state.authority
    if current and generation == current.generation
        and epoch < current.epoch
    then
        return false, 'authorization epoch predates current authority'
    end
    if current and generation ~= current.generation
        and not valid_reload_handoff(current, generation, epoch)
    then
        return false, 'different generation lacks bounded reload handoff'
    elseif not current and state.reload_handoff
        and not valid_reload_handoff(nil, generation, epoch)
    then
        return false, 'reload handoff requires a fresh generation at epoch zero'
    end
    local prior_revision, prior_bit, prior_conflict = nil, nil, false
    local function consider_prior(revision, bit)
        revision = tonumber(revision)
        if revision == nil then return end
        bit = bit == true
        if prior_revision == nil or revision > prior_revision then
            prior_revision, prior_bit = revision, bit
            prior_conflict = false
        elseif revision == prior_revision and prior_bit ~= bit then
            prior_conflict = true
        end
    end
    consider_prior(current and current.operator_revision,
        current and current.operator_armed)
    consider_prior(state.reload_handoff
            and state.reload_handoff.operator_revision,
        state.reload_handoff and state.reload_handoff.operator_armed)
    if state.authorization
        and state.authorization.generation == generation
        and state.authorization.epoch == epoch
    then
        consider_prior(state.authorization.operator_revision,
            state.authorization.operator_armed)
    end
    if prior_conflict or prior_revision ~= nil and (
        operator_revision < prior_revision
        or operator_revision == prior_revision
            and (operator_bit == '1') ~= (prior_bit == true)
    ) then
        return false, 'authorization operator state predates current high-water'
    end
    state.authorization = {
        generation=generation, epoch=epoch, protocol=protocol,
        signature=signature, expires=now() + AUTHORIZATION_TTL,
        operator_revision=operator_revision,
        operator_armed=operator_bit == '1',
    }
    prepare_companion_tuple(generation, epoch)
    -- Authorization retries carry the current Ctrl-P/Alt-P tuple. Merge that
    -- high-water into an already-established authority as data only; the
    -- eventual controller-ready callback remains the sole path that lets
    -- PartyTactics apply its effective PartyCombat edge.
    if current and current.generation == generation
        and current.epoch == epoch
    then
        current.operator_revision = operator_revision
        current.operator_armed = operator_bit == '1'
        state.operator_revision = operator_revision
        state.operator_armed = operator_bit == '1'
    end
    request_missing_companion_loads(name)
    issue(('sk authorize %s %d %s %s %s %s %s %s'):format(
        generation, epoch, LEADER, ROSTER, PROFILE_ID, PROFILE_VERSION,
        ENGINE_VERSION, signature))
    if name == 'Dolomedes' then
        issue(('jk authorize %s %d %s %s %s %s %s %s'):format(
            generation, epoch, PROFILE_ID, PROFILE_VERSION,
            ENGINE_VERSION, signature, LEADER, ROSTER))
    elseif name == 'Tackleberry' then
        issue(('lp authorize %s %d %s %s %s %s %s %s'):format(
            generation, epoch, PROFILE_ID, PROFILE_VERSION,
            ENGINE_VERSION, signature, LEADER, ROSTER))
    end
    state.last = 'exact committed controller lifecycle authorized'
    return true, 'controller lifecycle authorized'
end

local function retire_generation(arguments)
    local generation = arguments[1]
    local source = arguments[6]
    if #arguments ~= 6 or not valid_generation(generation)
        or arguments[2] ~= ENGINE_VERSION
        or arguments[3] ~= PROFILE_ID
        or arguments[4] ~= PROFILE_VERSION
        or not valid_signature(arguments[5])
        or EXPECTED[source] == nil
    then
        return false, 'retire requires exact stopped profile lifecycle'
    end

    -- This terminal fence deliberately does not depend on current adapter
    -- authority. A validated PartyTactics stop can overtake an already queued
    -- authorize/probe during profile application; remembering the generation
    -- here makes both delayed messages inert and gives each local companion
    -- the same no-loopback tombstone before any armpt/bindpt can arrive.
    state.retired_generations[generation] = true
    if state.authorization
        and state.authorization.generation == generation
    then
        state.authorization = nil
    end

    local authority = state.authority
    local current = player()
    local name = authority and authority.name
        or current and current.name or nil
    if authority and authority.generation == generation then
        -- A stop can overtake helper ACK commands already queued by the same
        -- frame. Revoke the local tuple before those callbacks can arrive;
        -- the direct stop fences below then retire each standalone helper.
        clear_local('stopped controller generation retired locally', false)
        state.active = false
    end
    issue(('sk stoppt %s %s %s %s %s %s'):format(
        generation, ENGINE_VERSION, PROFILE_ID, PROFILE_VERSION,
        arguments[5], source))
    if name == 'Dolomedes' then
        issue(('jk stoppt %s %s %s %s %s %s'):format(
            generation, ENGINE_VERSION, PROFILE_ID, PROFILE_VERSION,
            arguments[5], source))
    elseif name == 'Tackleberry' then
        issue(('lp retirept %s %s %s %s %s %s'):format(
            generation, ENGINE_VERSION, PROFILE_ID, PROFILE_VERSION,
            arguments[5], source))
    end
    state.keeper_instance_nonce = nil
    state.keeper_recovery = nil
    state.last = 'stopped controller generation retired locally'
    return true, 'stopped controller generation retired locally'
end

local function probe_authorized(generation, epoch, protocol)
    local authorization = state.authorization
    return type(authorization) == 'table'
        and now() <= authorization.expires
        and generation == authorization.generation
        and epoch == authorization.epoch
        and protocol == authorization.protocol
end

local function probe(arguments)
    local generation = arguments[1]
    local epoch_value = valid_epoch(arguments[2])
    local protocol_value = tonumber(arguments[3])
    local name, job, sub_job = local_identity()
    if #arguments ~= 3 then
        return false, 'probe requires exact generation, epoch, and protocol'
    end
    if not name or not in_tomb() then
        local authority = state.authority
        local current = player()
        local terminal_job = authority and authority.job
            or current and current.main_job
        if authority then
            retire_authority(authority)
            clear_local('controller probe left owned zone/identity', true)
        end
        terminal_off(terminal_job,
            'controller probe refused outside owned zone/identity')
        state.active = false
        return false, 'Tomb zone and exact name/main job required'
    end
    if not valid_generation(generation) or epoch_value == nil
        or protocol_value ~= M.protocol
    then
        return false, 'generation, epoch, and protocol required'
    end
    if authority_retired(generation, epoch_value) then
        return false, 'retired controller authority cannot be reclaimed'
    end
    local current = state.authority
    local idempotent = current and current.generation == generation
        and current.epoch == epoch_value
    if not idempotent
        and not probe_authorized(generation, epoch_value, protocol_value)
    then
        return false, 'probe lacks exact committed lifecycle authorization'
    end
    if current then
        local identity_matches = current.profile_id == PROFILE_ID
            and current.profile_version == PROFILE_VERSION
            and current.name == name and current.job == job
        if not identity_matches then
            return false, 'probe identity differs from current pinned authority'
        end
        if generation == current.generation
            and epoch_value < current.epoch
        then
            return false, 'stale controller probe cannot replace current authority'
        end
        if generation ~= current.generation
            and not valid_reload_handoff(current, generation, epoch_value)
        then
            return false, 'different generation requires GearSwap reload handoff'
        end
    elseif state.reload_handoff
        and not valid_reload_handoff(nil, generation, epoch_value)
    then
        return false, 'reload handoff requires a fresh generation at epoch zero'
    end
    if current and current.generation == generation
        and current.epoch == epoch_value
    then
        -- The stable host deliberately retains an inert adapter after an
        -- outside-zone activation. A later same-id activation short-circuits
        -- in the host, so the first accepted probe must also ensure the local
        -- companion add-ons exist before handing them authority.
        prepare_companion_tuple(generation, epoch_value)
        request_missing_companion_loads(name)
        if not bootstrap_companions(state.authority, name) then
            clear_local('companion rebind left the owned zone', true)
            terminal_off(job, 'companion rebind refused outside Tomb')
            state.active = false
            return false, 'companion rebind refused outside Tomb'
        end
        state.active = true
        cancel_terminal_reassert()
        if state.authorization
            and state.authorization.generation == generation
            and state.authorization.epoch == epoch_value
        then
            state.authorization = nil
        end
        local ready = announce_controller_ready(true)
        state.last = ready and 'same controller authority reasserted'
            or 'waiting for exact companion readiness acknowledgments'
        return true, state.last
    end
    if state.authority then
        if state.authority.generation ~= generation then
            retire_authority(state.authority)
        end
        clear_local('superseded by a fresh controller probe', false)
    end
    local authorization = state.authorization
    state.authority = {
        generation=generation,
        epoch=epoch_value,
        established_at=now(),
        profile_id=PROFILE_ID,
        profile_version=PROFILE_VERSION,
        name=name,
        job=job,
        sub_job=sub_job,
        signature=authorization.signature,
        operator_revision=authorization.operator_revision,
        operator_armed=authorization.operator_armed == true,
    }
    state.operator_revision = authorization.operator_revision
    state.operator_armed = authorization.operator_armed == true
    reset_pld_sustain()
    state.suspended = false
    state.opener = nil
    state.maintenance_cycle = nil
    state.cycle_phase = nil
    state.reload_handoff = nil
    prepare_companion_tuple(generation, epoch_value)
    request_missing_companion_loads(name)
    state.active = true
    if not bootstrap_companions(state.authority, name) then
        state.authority = nil
        terminal_off(job, 'companion bootstrap refused outside Tomb')
        state.active = false
        return false, state.last
    end
    state.authorization = nil
    cancel_terminal_reassert()
    local ready = announce_controller_ready(false)
    state.last = ready and 'controller ready; companion lifecycle armed'
        or 'waiting for exact companion readiness acknowledgments'
    return true, state.last
end

local function accept_operator_snapshot(revision_value, bit)
    local revision = valid_revision(revision_value)
    if revision == nil or (bit ~= '0' and bit ~= '1') then
        return false, 'operator requires canonical revision and bit'
    end
    local current = tonumber(state.operator_revision) or 0
    if revision < current then
        return false, 'operator revision is stale'
    end
    local desired = bit == '1'
    if revision == current and state.operator_armed ~= desired then
        return false, 'operator bit conflicts at current revision'
    end
    state.operator_revision = revision
    state.operator_armed = desired
    if state.authority then
        state.authority.operator_revision = revision
        state.authority.operator_armed = desired
    end
    return true, desired
end

local function operator(arguments)
    if #arguments ~= 5
        or not same_authority(arguments[1], arguments[2], arguments[3])
        or not in_tomb()
    then
        return false, 'operator requires current protocol-2 authority'
    end
    local accepted, desired = accept_operator_snapshot(
        arguments[4], arguments[5])
    if not accepted then return false, desired end

    -- The local SignetKeeper is the only relay to LocusPuller. It withholds
    -- that relay until the fresh six-client census is complete, so an initial
    -- all-missing load cannot begin another pull even when ON is already data.
    issue(('sk operator %s %d %d %s'):format(
        state.authority.generation, state.authority.epoch,
        state.operator_revision, state.operator_armed and '1' or '0'))
    if not state.operator_armed then
        issue('pc reconcile off')
        state.last = 'revisioned operator OFF applied immediately'
    elseif state.suspended or state.reload_handoff then
        state.last = 'revisioned operator ON recorded while automatic lanes are held'
    else
        issue('pc reconcile on')
        state.last = 'revisioned operator ON applied'
    end
    return true, state.last
end

local function suspend(arguments)
    local cycle = valid_cycle(arguments[4])
    if #arguments ~= 4
        or not same_authority(arguments[1], arguments[2], arguments[3])
        or not cycle or not in_tomb()
    then
        return false, 'suspend requires current authority and positive cycle'
    end
    if not state.maintenance_cycle and cycle ~= 1
        or state.maintenance_cycle and (
        cycle > state.maintenance_cycle + 1
        or cycle < state.maintenance_cycle
        or cycle == state.maintenance_cycle
            and state.cycle_phase == 'resumed') then
        return false, 'stale maintenance-cycle suspend'
    end
    local name, job = local_identity()
    if not name then return false, 'local profile identity changed' end
    state.maintenance_cycle = cycle
    state.cycle_phase = 'suspended'
    state.suspended = true
    state.pld_pending = nil
    state.pld_retry_at = 0
    release_opener('Signet suspension replaced PLD opener', false)
    local command = 'pc reconcile off; aws2 off; hb follow off; hb db off; '
        ..'hb as off; hb as attack off; hb off'
    if job == 'COR' then command = command..'; r2 off' end
    issue(command)
    -- GearSwap and SignetKeeper are different addons, so addon-scoped IPC
    -- cannot cross this boundary. Feed the exact-authority proof to the local
    -- keeper; SignetKeeper relays its resulting report to its peers.
    issue(('sk __adapter %s %s %d suspended %d'):format(
        state.authority.generation, name, state.authority.epoch, cycle))
    state.last = 'automatic lanes suspended for Signet staff'
    return true, 'automatic lanes suspended; manual actions pass through'
end

local function apply_resume_effects(job)
    -- Every retry reasserts the complete profile-owned running baseline. An
    -- interrupted first command batch therefore cannot leave AutoWS, rolls,
    -- RDM support, or PartyCombat in a half-resumed state.
    issue('aws2 on')
    if job == 'COR' then issue('r2 on') end
    if job == 'RDM' then
        issue('hb deactivateindoors off; hb disable cure; hb enable na; '
            ..'hb disable buff; hb db off; hb as off; '
            ..'hb as attack off; hb on')
    end
    issue(state.operator_armed
        and 'pc reconcile on' or 'pc reconcile off')
end

local function acknowledge_resume(name, cycle)
    issue(('sk __adapter %s %s %d resumed %d'):format(
        state.authority.generation, name, state.authority.epoch, cycle))
end

local function resume(arguments)
    local cycle = valid_cycle(arguments[6])
    if #arguments ~= 6
        or not same_authority(arguments[1], arguments[2], arguments[3])
        or not cycle or cycle ~= state.maintenance_cycle or not in_tomb()
    then
        return false, 'resume requires current authority, revision, bit, and active cycle'
    end
    if state.cycle_phase ~= 'suspended'
        and state.cycle_phase ~= 'resumed'
    then
        return false, 'maintenance cycle was not suspended'
    end
    if state.keeper_recovery then
        return false, 'SignetKeeper recovery keeps automatic lanes off'
    end
    local operator_ok, desired = accept_operator_snapshot(
        arguments[4], arguments[5])
    local resumed_from_stale = not operator_ok
        and desired == 'operator revision is stale'
    if not operator_ok and not resumed_from_stale then return false, desired end
    local name, job = local_identity()
    if not name then return false, 'local profile identity changed' end
    if state.cycle_phase == 'resumed' then
        -- Duplicate resume is a full repair channel, not merely an operator-bit
        -- replay. Reassert every lane before returning another exact ACK.
        apply_resume_effects(job)
        acknowledge_resume(name, cycle)
        return true, resumed_from_stale
            and 'stale resume reconciled from current operator state'
            or 'maintenance cycle already resumed'
    end

    state.suspended = false
    state.cycle_phase = 'resumed'
    -- A resume is only effective when its ordered snapshot is at least the
    -- adapter high-water. A delayed pre-Alt-P resume is rejected above.
    apply_resume_effects(job)
    acknowledge_resume(name, cycle)
    state.last = resumed_from_stale
        and 'automatic lanes resumed from newer current operator state'
        or 'automatic lanes resumed from current profile policy'
    return true, 'automatic lanes resumed from current operator state'
end

local function opener_arm(arguments)
    local id = uint32(arguments[1])
    if #arguments ~= 4 or not id or not same_authority(
        arguments[2], arguments[3], arguments[4])
    then
        return false, 'opener-arm requires exact target and current authority'
    end
    local name, job = local_identity()
    if name ~= 'Tackleberry' or job ~= 'PLD' or state.suspended
        or not state.operator_armed
    then
        return false,
            'only armed active unsuspended Tackleberry PLD owns the opener'
    end
    -- Target eligibility and distance belong to LocusPuller immediately before
    -- selection and again before Flash. This adapter issues no target/action
    -- command; it only reserves automatic callbacks for a bound helper. Do not
    -- duplicate a time-sensitive world-state check across the command hop.
    if state.opener and state.opener.id == id then
        issue(('lp __gate_armed %.0f %s %d'):format(
            id, state.authority.generation, state.authority.epoch))
        state.last = 'duplicate opener request re-acknowledged'
        return true, 'bounded PLD opener already armed'
    end
    if state.opener and state.opener.id ~= id then
        release_opener('new exact opener replaced the prior reservation')
    end
    issue('aws2 off')
    state.opener = {
        id=id,
        expires=now() + OPENER_TTL,
    }
    issue(('lp __gate_armed %.0f %s %d'):format(
        id, state.authority.generation, state.authority.epoch))
    state.last = 'bounded PLD opener armed for '..tostring(id)
    return true, 'bounded PLD opener armed'
end

local function opener_release(arguments)
    local id = uint32(arguments[1])
    local keepoff = arguments[5] == 'keepoff'
    if not id or not same_authority(
        arguments[2], arguments[3], arguments[4])
        or arguments[5] ~= nil and not keepoff
        or #arguments > 5
    then
        return false, 'opener-release requires exact target and current authority'
    end
    if state.opener and state.opener.id ~= id then
        return false, 'release target differs from active opener'
    end
    -- `keepoff` belongs only to terminal LocusPuller cleanup. It clears the
    -- reservation without racing the compiler's final AutoWS2 OFF. A later
    -- idempotent release after the adapter's own timeout also stays silent:
    -- that timeout already restored the lane exactly once.
    release_opener('PLD opener released', not keepoff)
    return true, 'PLD opener released'
end

local function expire_temporary_state()
    if state.opener and now() >= state.opener.expires then
        state.opener_timeouts = state.opener_timeouts + 1
        release_opener('PLD opener timed out fail-open')
        chat('Flash opener exceeded thirty seconds; AutoWS2 and PLD automation were released.', 123)
    end
end

function M.activate()
    local name = local_identity()
    if not name or not in_tomb() then
        local authority = state.authority
        local current = player()
        local job = authority and authority.job
            or current and current.main_job
        if authority then
            retire_authority(authority)
            clear_local('activation left owned zone/identity', true)
        end
        terminal_off(job,
            'activation refused outside Tomb or wrong main job')
        state.active = false
        -- Stay installed as an inert adapter so its prerender callback owns
        -- the one delayed terminal reassertion. A profile replacement invokes
        -- deactivate and cancels that retry before the new profile can run.
        return true, state.last
    end
    state.active = true
    state.native_tank_commanded = false
    reserve_flash_for_puller()
    request_missing_companion_loads(name)
    state.last = 'active and awaiting capability probe'
    return true
end

function M.deactivate(reason)
    cancel_terminal_reassert()
    state.authorization = nil
    if (reason == 'file-unload' or reason == 'unload')
        and state.reload_handoff
    then
        -- file_unload already transferred this exact authority to the
        -- reload-safe companions. The stable host must forget this adapter
        -- instance without converting a transient GearSwap outage into a
        -- profile teardown.
        local handoff = state.reload_handoff
        retire_authority(state.authority)
        state.active = false
        state.authority = nil
        state.suspended = false
        state.opener = nil
        state.pld_pending = nil
        state.pld_retry_at = 0
        state.maintenance_cycle = nil
        state.cycle_phase = nil
        state.reload_handoff = handoff
        state.native_tank_commanded = false
        state.last = 'GearSwap reload handoff preserved companion ownership'
        return true
    end
    if state.authority then
        retire_authority(state.authority)
        local fail_open = type(reason) == 'string'
            and reason:match('^error:') ~= nil
        clear_local(reason or 'adapter deactivated', true, fail_open)
    end
    state.companion_ready = {}
    state.companion_load_attempts = {}
    state.companion_generation = nil
    state.companion_epoch = nil
    state.next_companion_load_at = 0
    state.controller_announced = false
    state.native_tank_commanded = false
    reset_pld_sustain()
    state.keeper_instance_nonce = nil
    state.keeper_recovery = nil
    state.active = false
    state.last = reason or 'adapter deactivated'
    return true
end

function M.handle_action(controller, semantic, arguments)
    if controller ~= M.controller or type(semantic) ~= 'string'
        or type(arguments) ~= 'table'
    then
        state.rejected = state.rejected + 1
        return false, 'unsupported controller request'
    end
    semantic = semantic:lower()
    local accepted, reason
    if semantic == 'probe' then
        accepted, reason = probe(arguments)
    elseif semantic == 'authorize' then
        accepted, reason = authorize(arguments)
    elseif semantic == 'retire' then
        accepted, reason = retire_generation(arguments)
    elseif semantic == 'companion-ready' then
        accepted, reason = companion_ready(arguments)
    elseif semantic == 'keeper-instance' then
        accepted, reason = keeper_instance(arguments)
    elseif not state.active or not state.authority then
        accepted, reason = false, 'adapter has no current profile authority'
    elseif semantic == 'operator' then
        accepted, reason = operator(arguments)
    elseif semantic == 'suspend' then
        accepted, reason = suspend(arguments)
    elseif semantic == 'resume' then
        accepted, reason = resume(arguments)
    elseif semantic == 'opener-arm' then
        accepted, reason = opener_arm(arguments)
    elseif semantic == 'opener-release' then
        accepted, reason = opener_release(arguments)
    else
        accepted, reason = false, 'unsupported semantic'
    end
    if accepted then
        state.accepted = state.accepted + 1
    else
        state.rejected = state.rejected + 1
    end
    return accepted, reason
end

local function automatic_callback_reserved()
    expire_temporary_state()
    return state.active and (state.suspended or state.opener ~= nil
        or state.keeper_recovery ~= nil)
end

function M.pre_tick(...)
    if state.active then reserve_flash_for_puller() end
    return automatic_callback_reserved()
end

function M.user_job_tick(...)
    if state.active then reserve_flash_for_puller() end
    if automatic_callback_reserved() then return true end
    return pld_sustain_tick()
end

function M.user_job_self_command(command_args, event_args)
    local reserved = automatic_callback_reserved()
    if type(command_args) ~= 'table' or #command_args ~= 2
        or type(command_args[1]) ~= 'string'
        or type(command_args[2]) ~= 'string'
    then
        return false
    end
    local current = player()
    local helper = current and HELPER[current.main_job] or nil
    local command = command_args[1]:lower()
    local operation = command_args[2]:lower()
    if not helper or command ~= helper then return false end
    if operation == 'tick' then
        if reserved then return true end
        return pld_sustain_tick()
    end
    if not reserved then return false end
    -- A delayed frozen PLD subjob-enmity request is automatic work from the
    -- same helper lane. Consume only that exact token; typed /ma, /ja, /ws,
    -- and every other self-command remain untouched.
    return current.main_job == 'PLD' and operation == 'subjobenmity'
end

function M.prerender(...)
    expire_temporary_state()
    expire_pld_pending()
    expire_terminal_reassert()
    tick_keeper_recovery()
    return false
end

function M.job_aftercast(spell, spell_map, event_args)
    pld_aftercast(spell)
end

-- No maintenance state is permission to cancel an operator action.
function M.filter_pretarget(spell, spell_map, event_args)
    return false
end

function M.filter_precast(spell, spell_map, event_args)
    return false
end

function M.status()
    local authority = state.authority
    return ('manual-pass-through authority=%s operator=r%d/%s suspended=%s cycle=%s/%s keeper-recovery=%s opener=%s sustain=%d/%d/%d:%s accepted=%d rejected=%d timeouts=%d last=%s')
        :format(authority and (authority.generation..'/'..authority.epoch)
                or 'none',
            tonumber(state.operator_revision) or 0,
            state.operator_armed and 'on' or 'off',
            state.suspended and 'yes' or 'no',
            tostring(state.maintenance_cycle or 'none'),
            tostring(state.cycle_phase or 'none'),
            state.keeper_recovery and 'pending' or 'clear',
            state.opener and tostring(state.opener.id) or 'none',
            state.pld_cures, state.pld_majesty, state.pld_timeouts,
            state.pld_last,
            state.accepted, state.rejected, state.opener_timeouts,
            state.last)
end

function M.zone_change(...)
    local authority = state.authority
    local current = player()
    local job = authority and authority.job or current and current.main_job
    if state.authority then
        retire_authority(state.authority)
        clear_local('zone changed', true)
    end
    terminal_off(job, 'zone changed; local automation is terminally off')
    state.keeper_instance_nonce = nil
    state.keeper_recovery = nil
    state.active = false
    return true
end

function M.file_unload(...)
    local authority = state.authority
    if not authority or not in_tomb() then
        return M.deactivate('GearSwap job file unloaded')
    end

    -- A GearSwap reload clears disabled-slot and callback state before the
    -- new job file exists. Freeze automatic lanes during that gap, but leave
    -- the standalone keepers bound so they can raw-reassert owned equipment
    -- and coalesce one exact PartyTactics reapply after GearSwap returns.
    local command = 'pc reconcile off; aws2 off; hb follow off; hb db off; '
        ..'hb as off; hb as attack off; hb off'
    if authority.job == 'COR' then command = command..'; r2 off' end
    issue(command)
    if authority.name == 'Dolomedes' then
        issue(('jk gsreload %s %d'):format(
            authority.generation, authority.epoch))
    elseif authority.name == 'Tackleberry' then
        issue(('lp gsreload %s %d'):format(
            authority.generation, authority.epoch))
    end
    issue(('sk gsreload %s %d'):format(
        authority.generation, authority.epoch))
    announce_lost(authority, 'GearSwap reload handoff')
    state.opener = nil
    state.pld_pending = nil
    state.pld_retry_at = 0
    state.reload_handoff = {
        generation=authority.generation,
        epoch=authority.epoch,
        operator_revision=tonumber(authority.operator_revision) or 0,
        operator_armed=authority.operator_armed == true,
        expires=now() + RELOAD_HANDOFF_TTL,
    }
    state.last = 'GearSwap reload pending; companion ownership preserved'
    return true
end

function M.logout(...)
    local authority = state.authority
    local current = player()
    local job = authority and authority.job or current and current.main_job
    if authority then
        retire_authority(authority)
        clear_local('logout', true)
    end
    terminal_off(job, 'logout; local automation is terminally off')
    state.keeper_instance_nonce = nil
    state.keeper_recovery = nil
    if authority then
        -- The stable host immediately deactivates this adapter after returning
        -- from the raw logout callback, so its prerender timer cannot own the
        -- delayed durability pass. Route that one pass through PartyTactics;
        -- the core accepts it only while this exact generation/epoch and its
        -- pinned controller/protocol are still current. A switch or reapply
        -- therefore cancels it without leaving a raw delayed OFF command.
        issue(('wait 2; pt __controller_terminal %s %s %d %d'):format(
            M.controller, authority.generation, authority.epoch, M.protocol))
    end
    state.active = false
    return true
end

function M.unload(...)
    -- Depending on GearSwap/Windower teardown ordering, a reload can surface
    -- through either callback. Both enter the same bounded companion handoff;
    -- zone/logout callbacks remain terminal and never use this path.
    return M.file_unload(...)
end

return M
