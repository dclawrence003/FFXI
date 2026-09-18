-- PartyStart GEO controller for Selindrile-style GearSwap files.
-- Integration target: https://github.com/Selindrile/GearSwap
--
-- GEO's native Auto mode maintains Haste, Refresh, Aurorastorm, and Reraise
-- in addition to colures. PartyStart's RDM already supplies stronger Haste II
-- and Refresh III, so the sustained profile replaces that self-buff list with
-- either an empty list or Reraise-only list while leaving native
-- Indi/Geo/Entrust logic untouched.
-- Load at the end of a participating character's GEO gear file:
--     include('Common/PartyStart_GEO.lua')

local pstart_geo_packets = require('packets')
local pstart_geo_saved_auto = nil
local pstart_geo_active = false
local pstart_geo_fishfly = false
local pstart_geo_managed = false
local pstart_geo_leader = 'Dolomedes'
local pstart_geo_retry_at = 0
local pstart_geo_last_action = 'none'
local pstart_geo_last_heal_at = 0
local PSTART_GEO_HELPER_VERSION = '1.0.0'

local function pstart_geo_prove_helper(generation, epoch_text, version)
    local epoch = type(epoch_text) == 'string'
        and epoch_text:match('^%d+$') and tonumber(epoch_text) or nil
    if version ~= PSTART_GEO_HELPER_VERSION
        or type(generation) ~= 'string' or #generation > 64
        or generation:match('^%d+%-%d+%-%d+$') == nil
        or not epoch or epoch < 0 or epoch ~= math.floor(epoch)
    then return false end
    windower.send_command(('pt __legacy_helper_ready %s GEO %s %d')
        :format(PSTART_GEO_HELPER_VERSION, generation, epoch))
    return true
end

local function pstart_geo_set_autobuff(value)
    if state and state.AutoBuffMode then
        state.AutoBuffMode:set(value)
    end
end

local function pstart_geo_reraise_only()
    local result = {}
    for _, task in pairs(pstart_geo_saved_auto or buff_spell_lists.Auto or {}) do
        if task.Buff == 'Reraise' then
            result[#result + 1] = task
        end
    end
    return result
end

local function pstart_geo_valid_name(name)
    return type(name) == 'string'
        and name:match('^[A-Za-z][A-Za-z0-9_-]*$') ~= nil
        and #name <= 15
end

local function pstart_geo_fishfly_target()
    local leader = windower.ffxi.get_mob_by_name(pstart_geo_leader)
    local target = leader and leader.target_index and leader.target_index ~= 0
        and windower.ffxi.get_mob_by_index(leader.target_index) or nil

    local function usable(mob)
        if not mob or mob.spawn_type ~= 16 or not mob.valid_target
            or not mob.hpp or mob.hpp <= 0
            or type(mob.name) ~= 'string'
            or mob.name:lower() ~= 'vermillion fishfly'
        then
            return false
        end
        local distance = mob.distance and math.sqrt(mob.distance) or math.huge
        local cast_range = (tonumber(mob.model_size) or 0) + 20.4
        return distance <= cast_range
    end

    -- Dolo's selected fly is authoritative when available.  Immediately after
    -- the junction activates, however, his target table may arrive a few frames
    -- later than the spawned pack.  Fall back to the closest exact Fishfly so
    -- Malaise never waits on PartyCombat or on Dolo engaging anything.
    if usable(target) then return target end
    local closest = nil
    for _, mob in pairs(windower.ffxi.get_mob_array() or {}) do
        if usable(mob)
            and (not closest or (mob.distance or math.huge)
                < (closest.distance or math.huge))
        then
            closest = mob
        end
    end
    return closest
end

local function pstart_geo_between_distance(left, right)
    if not left or not right or not left.x or not right.x
        or not left.y or not right.y
    then
        return math.huge
    end
    local x = left.x - right.x
    local y = left.y - right.y
    return math.sqrt(x * x + y * y)
end

local function pstart_geo_known_ability(ability)
    if not ability then return false end
    for _, id in ipairs((windower.ffxi.get_abilities() or {}).job_abilities or {}) do
        if id == ability.id then return true end
    end
    return false
end

local function pstart_geo_ability_ready(name)
    local ability = res.job_abilities:with('en', name)
    local recasts = windower.ffxi.get_ability_recasts() or {}
    return ability and pstart_geo_known_ability(ability)
        and not midaction() and not moving and not silent_check_disable()
        and (not silent_check_amnesia or not silent_check_amnesia())
        and (not tickdelay or os.clock() >= tickdelay)
        and (recasts[ability.recast_id] or 999) < latency
end

local function pstart_geo_full_circle_ready()
    return pstart_geo_ability_ready('Full Circle')
end

local function pstart_geo_spell_ready(spell)
    local learned = windower.ffxi.get_spells() or {}
    local recasts = windower.ffxi.get_spell_recasts() or {}
    return spell and learned[spell.id]
        and not midaction() and not moving and not silent_check_disable()
        and (not tickdelay or os.clock() >= tickdelay)
        and os.clock() >= pstart_geo_retry_at
        and (recasts[spell.id] or 999) < spell_latency
        and player.mp >= spell.mp_cost
        and silent_can_use(spell.id)
end

-- Select Dolo's target locally without engaging, turning, following, or
-- asking PartyCombat to own Achoo. This is the same observer-target packet
-- used by the isolated BRD mechanic controller.
local function pstart_geo_select_target(target)
    local current = windower.ffxi.get_player()
    if not current or not current.id or not current.index
        or not target or not target.id
    then
        return false
    end
    pstart_geo_packets.inject(pstart_geo_packets.new('incoming', 0x058, {
        ['Player'] = current.id,
        ['Target'] = target.id,
        ['Player Index'] = current.index,
    }))
    return true
end

local function pstart_geo_configure_fishfly()
    autoindi = 'Acumen'
    autogeo = 'Malaise'
    autoentrust = 'Languor'
    autoentrustee = pstart_geo_leader
    autogeotar = 'None'
    if state and state.CombatEntrustOnly then
        state.CombatEntrustOnly:set(false)
    end
    if state and state.AutoZergMode then state.AutoZergMode:set(false) end
    if state and state.AutoBubble then state.AutoBubble:set(true) end
    pstart_geo_set_autobuff('Auto')
end

local function pstart_geo_member_in_range(member)
    if not member or not member.name then return false end
    if member.name:lower() == player.name:lower() then return true end
    local mob = windower.ffxi.get_mob_by_name(member.name)
    return mob and mob.distance and math.sqrt(mob.distance) <= 20.5
end

local function pstart_geo_emergency_heal()
    if os.clock() - (pstart_geo_last_heal_at or 0) < 2 then return false end
    local target_name, target_token, target_hpp
    for key, member in pairs(windower.ffxi.get_party() or {}) do
        if type(key) == 'string' and key:match('^p[0-5]$')
            and type(member) == 'table' and type(member.hpp) == 'number'
            and member.hpp > 0 and member.hpp < 45
            and pstart_geo_member_in_range(member)
            and (not target_hpp or member.hpp < target_hpp)
        then
            target_name = member.name
            target_token = member.name:lower() == player.name:lower()
                and '<me>' or '<'..key..'>'
            target_hpp = member.hpp
        end
    end
    if not target_name then return false end

    local choices = target_hpp < 25
        and {'Cure IV', 'Cure III', 'Cure II', 'Cure'}
        or {'Cure III', 'Cure IV', 'Cure II', 'Cure'}
    for _, name in ipairs(choices) do
        local spell = res.spells:with('en', name)
        if pstart_geo_spell_ready(spell) then
            windower.chat.input('/ma "'..spell.en..'" '..target_token)
            tickdelay = os.clock() + 3
            pstart_geo_last_heal_at = os.clock()
            pstart_geo_last_action = ('emergency %s -> %s (%d%%)')
                :format(spell.en, target_name, target_hpp)
            add_to_chat(123, '[PartyStart GEO] '..pstart_geo_last_action)
            return true
        end
    end
    return false
end

local function pstart_geo_fishfly_action()
    if not pstart_geo_active or not pstart_geo_fishfly
        or player.main_job ~= 'GEO' or midaction() or moving
        or silent_check_disable()
        or (tickdelay and os.clock() < tickdelay)
        or os.clock() < pstart_geo_retry_at
    then
        return false
    end

    if pstart_geo_emergency_heal() then return true end

    local target = pstart_geo_fishfly_target()
    local luopan = windower.ffxi.get_mob_by_target('pet')
    local wrong_bubble = luopan and last_geo ~= 'Malaise'
    local misplaced_bubble = luopan and target
        and pstart_geo_between_distance(luopan, target) > 7

    if wrong_bubble or misplaced_bubble then
        if not pstart_geo_full_circle_ready() then return false end
        windower.chat.input('/ja "Full Circle" <me>')
        tickdelay = os.clock() + 1.2
        pstart_geo_last_action = wrong_bubble
            and 'removed non-Malaise luopan'
            or 'moved Malaise luopan to the current pack'
        add_to_chat(158, '[PartyStart GEO] '..pstart_geo_last_action)
        return true
    end

    -- The native GEO routine remains the authority for Indi-Acumen,
    -- entrusted Indi-Languor, Reraise, and luopan abilities. It does not cast an
    -- offensive bubble while Achoo is idle, so only that final gap is handled
    -- below.
    if check_geo and check_geo() then return true end
    if luopan or not target then return false end

    if not buffactive['Blaze of Glory']
        and pstart_geo_ability_ready('Blaze of Glory')
    then
        windower.chat.input('/ja "Blaze of Glory" <me>')
        tickdelay = os.clock() + 1.2
        pstart_geo_last_action = 'Blaze of Glory armed for Geo-Malaise'
        add_to_chat(158, '[PartyStart GEO] '..pstart_geo_last_action)
        return true
    end

    local selected = windower.ffxi.get_mob_by_target('t')
    if not selected or selected.id ~= target.id then
        if pstart_geo_select_target(target) then
            pstart_geo_retry_at = os.clock() + 0.45
            pstart_geo_last_action = 'selected '..target.name..' from '
                ..pstart_geo_leader
            return true
        end
        return false
    end

    local spell = res.spells:with('en', 'Geo-Malaise')
    if not pstart_geo_spell_ready(spell) then return false end
    windower.chat.input('/ma "Geo-Malaise" <t>')
    tickdelay = os.clock() + 3.1
    pstart_geo_last_action = 'Geo-Malaise -> '..target.name
    add_to_chat(158, '[PartyStart GEO] '..pstart_geo_last_action)
    return true
end

-- Selindrile normally reaches check_geo() through its own job heartbeat.  A
-- profile can opt into this second, guarded heartbeat when another coordinator
-- is responsible for guaranteeing maintenance.  It requests spells and job
-- abilities through GearSwap exactly as the native routine does; it never
-- equips or locks anything.
local function pstart_geo_managed_action()
    if not pstart_geo_active or pstart_geo_fishfly
        or not pstart_geo_managed or player.main_job ~= 'GEO'
        or midaction() or moving or silent_check_disable()
        or (tickdelay and os.clock() < tickdelay)
        or os.clock() < pstart_geo_retry_at
    then
        return false
    end
    if check_geo and check_geo() then
        pstart_geo_last_action = 'managed native colure heartbeat acted'
        return true
    end
    return false
end

-- Character/shared GEO setup files historically enabled AutoBuff one second
-- after every GearSwap load. Force an inert baseline after all setup has
-- completed, unless PartyStart has already activated a profile during that
-- window. This makes the delayed guard unable to undo a legitimate startup.
send_command('wait 2; gs c pstartgeo bootidle')

local pstart_geo_original_self_command = user_job_self_command
function user_job_self_command(commandArgs, eventArgs)
    local command = commandArgs[1] and commandArgs[1]:lower() or nil
    if command ~= 'pstartgeo' then
        if pstart_geo_original_self_command then
            return pstart_geo_original_self_command(commandArgs, eventArgs)
        end
        return
    end

    eventArgs.handled = true
    local requested = commandArgs[2] and commandArgs[2]:lower() or nil
    if requested == 'probe' then
        pstart_geo_prove_helper(
            commandArgs[3], commandArgs[4], commandArgs[5])
    elseif requested == 'tick' then
        if not pstart_geo_fishfly_action() then
            pstart_geo_managed_action()
        end
    elseif requested == 'fishfly'
        and pstart_geo_valid_name(commandArgs[3] or pstart_geo_leader)
    then
        if pstart_geo_saved_auto == nil then
            pstart_geo_saved_auto = buff_spell_lists.Auto
        end
        buff_spell_lists.Auto = pstart_geo_reraise_only()
        pstart_geo_active = true
        pstart_geo_fishfly = true
        pstart_geo_managed = false
        pstart_geo_leader = commandArgs[3] or pstart_geo_leader
        pstart_geo_retry_at = 0
        pstart_geo_last_heal_at = 0
        tickdelay = 0
        pstart_geo_configure_fishfly()
        add_to_chat(122,
            'PartyStart GEO: Fishfly magic support is On; automatic '
            ..'Indi-Acumen, Geo-Malaise, and entrusted Indi-Languor follow '
            ..pstart_geo_leader.."'s target without PartyCombat.")
        pstart_geo_fishfly_action()
    elseif requested == 'lean' then
        if pstart_geo_saved_auto == nil then
            pstart_geo_saved_auto = buff_spell_lists.Auto
        end
        buff_spell_lists.Auto = {}
        pstart_geo_active = true
        pstart_geo_fishfly = false
        pstart_geo_managed = false
        add_to_chat(122,
            'PartyStart GEO: redundant native Haste/Refresh/Aurorastorm/'
            ..'Reraise maintenance suppressed; colure automation unchanged.')
    elseif requested == 'leanrr' then
        if pstart_geo_saved_auto == nil then
            pstart_geo_saved_auto = buff_spell_lists.Auto
        end
        buff_spell_lists.Auto = pstart_geo_reraise_only()
        pstart_geo_active = true
        pstart_geo_fishfly = false
        pstart_geo_managed = false
        add_to_chat(122,
            'PartyStart GEO: lean mode retains self-Reraise; redundant native '
            ..'Haste/Refresh/Aurorastorm suppressed; colures unchanged.')
    elseif requested == 'leanmanaged' then
        if pstart_geo_saved_auto == nil then
            pstart_geo_saved_auto = buff_spell_lists.Auto
        end
        buff_spell_lists.Auto = {}
        pstart_geo_active = true
        pstart_geo_fishfly = false
        pstart_geo_managed = true
        add_to_chat(122,
            'PartyStart GEO: lean managed mode suppresses redundant native '
            ..'self buffs and guarantees the configured colure heartbeat.')
    elseif requested == 'leanrrmanaged' then
        if pstart_geo_saved_auto == nil then
            pstart_geo_saved_auto = buff_spell_lists.Auto
        end
        buff_spell_lists.Auto = pstart_geo_reraise_only()
        pstart_geo_active = true
        pstart_geo_fishfly = false
        pstart_geo_managed = true
        add_to_chat(122,
            'PartyStart GEO: lean managed mode retains self-Reraise, '
            ..'suppresses redundant native self buffs, and guarantees the '
            ..'configured colure heartbeat.')
    elseif requested == 'bootidle' then
        if not pstart_geo_active then
            pstart_geo_set_autobuff('Off')
            add_to_chat(122, 'PartyStart GEO: idle until a profile is started.')
        end
    elseif requested == 'idle' or requested == 'off' then
        if pstart_geo_saved_auto ~= nil then
            buff_spell_lists.Auto = pstart_geo_saved_auto
            pstart_geo_saved_auto = nil
        end
        pstart_geo_active = false
        pstart_geo_fishfly = false
        pstart_geo_managed = false
        pstart_geo_set_autobuff('Off')
        add_to_chat(122,
            'PartyStart GEO: idle; colure and native buff automation are Off.')
    elseif requested == 'restore' then
        if pstart_geo_saved_auto ~= nil then
            buff_spell_lists.Auto = pstart_geo_saved_auto
            pstart_geo_saved_auto = nil
        end
        pstart_geo_active = true
        pstart_geo_fishfly = false
        pstart_geo_managed = false
        add_to_chat(122, 'PartyStart GEO: native Auto self-buff list restored.')
    elseif requested == 'status' or not requested then
        add_to_chat(122, ('PartyStart GEO: %s; lean mode: %s; managed: %s; '
            ..'AutoBuff: %s; Fishfly: %s; leader: %s; last: %s')
            :format(
                pstart_geo_active and 'Active' or 'Idle',
                pstart_geo_saved_auto and 'On' or 'Off',
                pstart_geo_managed and 'On' or 'Off',
                state and state.AutoBuffMode and state.AutoBuffMode.value
                    or 'Unavailable',
                pstart_geo_fishfly and 'On' or 'Off',
                pstart_geo_leader,
                pstart_geo_last_action))
    else
        add_to_chat(123,
            'PartyStart GEO usage: gs c pstartgeo '
            ..'<fishfly leader|tick|lean|leanrr|leanmanaged|leanrrmanaged|'
            ..'restore|idle|off|status>')
    end
end

local pstart_geo_original_user_job_tick = user_job_tick
function user_job_tick()
    if pstart_geo_fishfly_action() then return true end
    if pstart_geo_original_user_job_tick then
        return pstart_geo_original_user_job_tick()
    end
    return false
end
