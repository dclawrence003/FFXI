local M = {}

local OLD_RDM_SELF_BUFFS = {
    'Temper II','Temper','Gain-STR','Gain-MND','Aquaveil','Phalanx','Reraise',
}
local OLD_RDM_DEBUFFS = {
    'Frazzle III','Frazzle II','Frazzle','Dia III','Dia II','Dia',
    'Distract III','Distract II','Distract','Slow II','Slow',
    'Paralyze II','Paralyze','Blind II','Blind','Addle II','Addle','Silence',
}
local OLD_BRD_SONGS = {
    'Victory March','Valor Minuet V','Blade Madrigal',
    "Mage's Ballad III","Sentinel's Scherzo",
}

local function append(commands, command)
    commands[#commands + 1] = command
end

local function autows_exclusion_token(values)
    return values and #values > 0 and table.concat(values, ',') or 'none'
end

local function healbot_cure_na(commands)
    append(commands, 'hb deactivateindoors off; hb enable cure; hb enable na; '
        ..'hb disable buff; hb db off; hb as off; hb as attack off; hb on')
end

local function combat_command(util, profile)
    local combat = profile.combat
    local priority = combat.priority_target
        and combat.priority_target:gsub(' ', '_') or '-'
    return ('pc policy %s %s %s %s %s %s %s %s %s'):format(
        profile.policy_id, combat.leader, combat.puller,
        util.csv(combat.attackers), util.csv(combat.targeters), combat.movement,
        priority, util.csv(combat.priority_attackers or {}),
        util.csv(combat.target_exclusions))
end

local function compile_cor(commands, policy)
    -- Keep the profile's ranged weapon authoritative before Roller2 can act.
    -- `unset` is Selindrile's boolean-off command for UnlockWeapons.
    append(commands,
        'gs c set CompensatorMode Never; gs c unset UnlockWeapons')
    append(commands, ('r2 policy conservative; r2 engaged off; '
        ..'r2 randomdeal off; '
        ..'r2 roll1 %s; r2 roll2 %s; r2 on')
        :format(policy.rolls[1], policy.rolls[2]))
    append(commands, 'gs c unset AutoWSMode')
    append(commands, 'hb db off; hb as off; hb as attack off; hb off')
end

local function compile_brd(commands, name, policy)
    -- Narrow contract: PartyTactics selects an already-reviewed controller
    -- preset. GearSwap remains the sole owner of instruments, gear sets,
    -- precast/midcast, and the native song scheduler.
    append(commands, ('hb cancelbuff %s %s'):format(
        name, table.concat(OLD_BRD_SONGS, ',')))
    for _, spell in ipairs{'Carnage Elegy','Battlefield Elegy','Pining Nocturne'} do
        append(commands, 'hb db rm '..spell)
    end
    if policy.healbot == 'cure-na' then
        healbot_cure_na(commands)
    else
        append(commands, 'hb db off; hb as off; hb as attack off; hb off')
    end
    append(commands, ('gs c pstartbrd %s %s')
        :format(policy.preset, policy.target_source))
end

local function compile_rdm(util, commands, name, policy)
    for _, spell in ipairs(OLD_RDM_SELF_BUFFS) do
        append(commands, ('hb cancelbuff %s %s'):format(name, spell))
    end
    for _, spell in ipairs(OLD_RDM_DEBUFFS) do append(commands, 'hb db rm '..spell) end
    append(commands, 'gs c set AutoBuffMode Off')
    append(commands, ('gs c pstartrdm %s %s %s %s %s %s'):format(
        policy.preset, policy.target_source, util.csv(policy.haste),
        util.csv(policy.refresh), util.csv(policy.phalanx),
        util.csv(policy.defense)))
    for _, debuff in ipairs{
        'STR Down','DEX Down','VIT Down','AGI Down','MND Down','CHR Down',
    } do
        append(commands, 'hb unignore_debuff always '..debuff)
    end
    append(commands, 'hb reset debuffs')
    if policy.healbot == 'cure-na' then
        healbot_cure_na(commands)
    else
        append(commands,
            'hb deactivateindoors off; hb disable cure; hb enable na; '
                ..'hb disable buff; hb db off; hb as off; '
                ..'hb as attack off; hb on')
    end
end

local function compile_geo(commands, policy)
    append(commands, 'gs c pstartgeo '..policy.mode)
    append(commands, policy.zerg and 'gs c set AutoZergMode'
        or 'gs c unset AutoZergMode')
    if policy.combat_entrust_only ~= nil then
        append(commands, policy.combat_entrust_only
            and 'gs c set CombatEntrustOnly'
            or 'gs c unset CombatEntrustOnly')
    end
    append(commands, ('gs c autoindi %s; gs c autogeo %s; '
        ..'gs c autoentrust %s; gs c autoentrustee %s; '
        ..'gs c set AutoBuffMode Auto'):format(
        policy.indi, policy.geo, policy.entrust, policy.entrustee))
    if policy.healbot == 'cure-na' then
        healbot_cure_na(commands)
    else
        append(commands, 'hb db off; hb as off; hb as attack off; hb off')
    end
end

local function compile_pld(commands, policy)
    if policy.native_buffs == false or policy.native_tank == false then
        append(commands,
            (policy.native_buffs == false
                and 'gs c set AutoBuffMode Off'
                or 'gs c set AutoBuffMode Auto')
            ..'; '
            ..(policy.native_tank == false
                and 'gs c unset AutoTankMode'
                or 'gs c set AutoTankMode')
            ..'; gs c unset AutoTankFull; gs c set HybridMode Tank; '
            ..'gs c unset AutoWSMode')
    else
        -- Compatibility path: keep every established profile's command plan
        -- byte-identical when the additive native-automation flags are absent.
        append(commands, 'gs c set AutoBuffMode Auto; gs c set AutoTankMode; '
            ..'gs c unset AutoTankFull; gs c set HybridMode Tank; '
            ..'gs c unset AutoWSMode')
    end
    append(commands, 'hb disable cure; hb disable na; hb db off; '
        ..'hb as off; hb as attack off; hb off')
    append(commands, ('gs c pstartpld %s %s')
        :format(policy.preset, policy.leader))
    if policy.weapon_mode then
        -- A tank can be intentionally absent from PartyCombat while still
        -- receiving a deterministic GearSwap-owned weapon mode.  This is a
        -- loadout selection only; it does not grant offense or targeting.
        append(commands, 'gs c weapons '..policy.weapon_mode)
    end
end

local function compile_dnc(commands, policy)
    append(commands, 'gs c set AutoBuffMode Off; gs c unset AutoPrestoMode; '
        ..'gs c set AutoSambaMode Off; gs c set DanceStance None; '
        ..'gs c unset AutoWSMode; cancel 410')
    append(commands, ('gs c pstartdnc %s %s')
        :format(policy.preset, policy.target_source))
    append(commands, 'hb db off; hb as off; hb as attack off; hb off')
end

local function compile_offense(commands, offense)
    local native_off = offense.disable_native_autows == true
        and 'gs c unset AutoWSMode; ' or ''
    if offense.automatic == false then
        append(commands, (native_off..'gs c weapons %s; wait 1; aws2 off')
            :format(offense.weapon_mode))
    else
        local ws_command = offense.session_ws == true
            and 'aws2 sessionws' or 'aws2 use'
        append(commands, (native_off..'gs c weapons %s; wait 1; '
            ..'aws2 aftermath off; '
            ..'%s %s; aws2 tp %d; aws2 hp %d %d; aws2 on'):format(
            offense.weapon_mode, ws_command, offense.ws,
            tonumber(offense.tp) or 1000,
            tonumber(offense.hp_min) or 0, tonumber(offense.hp_max) or 100))
    end
end

local function compile_disabled(commands, job)
    if job == 'COR' then
        append(commands, 'r2 off; gs c unset AutoWSMode')
    elseif job == 'BRD' then
        append(commands, 'gs c pstartbrd off')
    elseif job == 'RDM' then
        append(commands, 'gs c pstartrdm off; gs c set AutoBuffMode Off')
    elseif job == 'GEO' then
        append(commands, 'gs c pstartgeo idle; gs c unset AutoZergMode; '
            ..'gs c set AutoBuffMode Off')
    elseif job == 'PLD' then
        append(commands, 'gs c pstartpld off; gs c set AutoBuffMode Off; '
            ..'gs c unset AutoTankMode; gs c unset AutoTankFull; '
            ..'gs c unset AutoWSMode')
    elseif job == 'DNC' then
        append(commands, 'gs c pstartdnc off; gs c set AutoBuffMode Off; '
            ..'gs c unset AutoPrestoMode; gs c set AutoSambaMode Off; '
            ..'gs c set DanceStance None; gs c unset AutoWSMode; cancel 410')
    end
    append(commands, 'hb db off; hb as off; hb as attack off; hb off; aws2 off')
end

function M.compile(util, schema, profile)
    local errors = schema.validate(util, profile)
    if #errors > 0 then return nil, errors end
    local plan = {
        id=profile.id, version=profile.version, label=profile.label,
        members={}, policy_command=combat_command(util, profile),
    }
    for _, name in ipairs(util.sorted_keys(profile.members)) do
        local member = profile.members[name]
        local commands = {plan.policy_command,
            'aws2 exclude '..autows_exclusion_token(
                profile.combat.target_exclusions),
            'hb follow off; hb as off; hb as attack off'}
        if profile.gearswap_adapter then
            -- The stable GearSwap host loads only the immutable adapter pinned
            -- by this profile. Adding a different fight never edits or
            -- activates this adapter.
            commands[#commands + 1] = ('gs c ptgs activate %s %s'):format(
                profile.gearswap_adapter.id,
                profile.gearswap_adapter.version)
        else
            -- This is also a recovery baseline. If PartyTactics previously
            -- crashed or reloaded while GearSwap retained a fight adapter,
            -- an adapter-free profile must revoke that stale callback owner
            -- before any legacy support preset is allowed to start.
            commands[#commands + 1] = 'gs c ptgs off'
        end
        local job = member.main_job
        local support = profile.support[job:lower()]
        if support and support.enabled == false then
            compile_disabled(commands, job)
        elseif job == 'COR' then compile_cor(commands, profile.support.cor)
        elseif job == 'BRD' then compile_brd(commands, name, profile.support.brd)
        elseif job == 'RDM' then
            compile_rdm(util, commands, name, profile.support.rdm)
        elseif job == 'GEO' then compile_geo(commands, profile.support.geo)
        elseif job == 'PLD' then compile_pld(commands, profile.support.pld)
        elseif job == 'DNC' then compile_dnc(commands, profile.support.dnc)
        end
        local offense = profile.offense[name]
        if offense then
            compile_offense(commands, offense)
        elseif not (support and support.enabled == false) then
            -- A target-only/support character still needs one explicit inert
            -- AutoWS2 baseline. This prevents a user-owned prior session from
            -- leaking offense into a profile that declares none, without the
            -- repeated off/on command bursts older orchestration produced.
            append(commands, 'aws2 off')
        end
        plan.members[name] = {
            main_job=job,
            commands=commands,
            owns_autows2=offense ~= nil,
            summary=(job..' | combat '
                ..(util.contains_name(profile.combat.attackers, name)
                    and 'attacker' or (util.contains_name(
                        profile.combat.targeters, name) and 'target-only' or 'off'))
                ..' | AutoWS2 '..(offense and (offense.automatic == false
                    and 'manual' or 'owned') or 'off')),
        }
    end
    return plan, {}
end

function M.teardown(job, owns_autows2, local_only, transitioning)
    local commands = {
        local_only and 'pc localinvalidate partytactics'
            or 'pc invalidate partytactics',
        -- Safe for legacy profiles too: an idle PartyTactics host delegates
        -- immediately and an active profile adapter is revoked before any
        -- legacy support state is changed.
        'gs c ptgs off',
        'aws2 exclude none',
        'hb follow off; hb db off; hb as off; hb as attack off; hb off',
    }
    if job == 'COR' then commands[#commands + 1] = 'r2 off' end
    if job == 'BRD' then commands[#commands + 1] = 'gs c pstartbrd off' end
    if job == 'RDM' then
        commands[#commands + 1] = transitioning
            and 'gs c pstartrdm transition' or 'gs c pstartrdm off'
    end
    if job == 'PLD' then commands[#commands + 1] = 'gs c pstartpld off' end
    if job == 'DNC' then commands[#commands + 1] = 'gs c pstartdnc off' end
    if job == 'GEO' then
        commands[#commands + 1] = 'gs c pstartgeo idle'
        -- Locus may opt into pre-combat Entrust. Restore Selindrile's native
        -- safe default before another profile is allowed to take ownership.
        commands[#commands + 1] = 'gs c set CombatEntrustOnly'
    end
    if job == 'RDM' or job == 'PLD' or job == 'DNC' or job == 'GEO' then
        commands[#commands + 1] = 'gs c set AutoBuffMode Off'
    end
    if owns_autows2 then commands[#commands + 1] = 'aws2 off' end
    return commands
end

return M
