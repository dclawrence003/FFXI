local M = {}

local RESERVED_COMMANDS = {
    use=true, preview=true, reapply=true, on=true, start=true, off=true,
    stop=true, arm=true, disarm=true, force=true, action=true, status=true,
    check=true, preflight=true, version=true, list=true, show=true,
    errors=true, audit=true, sleep=true,
    __reapply=true, __controller_ready=true, __controller_lost=true,
    __gearswap_host_ready=true, __gearswap_host_lost=true,
    __legacy_helper_ready=true,
}

local function add(errors, message)
    errors[#errors + 1] = message
end

local function valid_string(value, maximum)
    return type(value) == 'string' and value ~= '' and #value <= maximum
        and value:find('[|\r\n;]') == nil
end

local function valid_text(value, maximum)
    return type(value) == 'string' and value ~= '' and #value <= maximum
        and value:find('[|\r\n]') == nil
end

local function valid_token(value, maximum)
    return type(value) == 'string' and value ~= '' and #value <= maximum
        and value:match('^[A-Za-z][A-Za-z0-9_-]*$') ~= nil
end

-- The stable GearSwap host deliberately accepts a narrower grammar than
-- general PartyTactics tokens.  Validate that same grammar at catalog load so
-- a profile can never compile successfully and then be rejected by the host.
local function valid_adapter_identifier(value, maximum)
    return type(value) == 'string' and #value >= 1 and #value <= maximum
        and value:match('^[a-z0-9][a-z0-9%-]*$') ~= nil
end

local function valid_adapter_semantic(value, maximum)
    return type(value) == 'string' and #value >= 1 and #value <= maximum
        and value:match('^[a-z0-9][a-z0-9_%-]*$') ~= nil
end

local function valid_adapter_version(value)
    if not valid_string(value, 24) then return false end
    local major, minor, patch = value:match('^(%d+)%.(%d+)%.(%d+)$')
    if not major then return false end
    return (major == '0' or major:sub(1, 1) ~= '0')
        and (minor == '0' or minor:sub(1, 1) ~= '0')
        and (patch == '0' or patch:sub(1, 1) ~= '0')
end

local function valid_action_label(value, maximum)
    -- Colons are part of canonical FFXI action names such as Utsusemi: Ni.
    -- Shell metacharacters remain excluded; these labels are resource lookups,
    -- never raw command fragments.
    return type(value) == 'string' and value ~= '' and #value <= maximum
        and value:match("^[A-Za-z0-9][A-Za-z0-9 ._'+:-]*$") ~= nil
end

local function valid_action_target(value)
    return type(value) == 'string' and #value <= 18
        and (value:match('^<[A-Za-z0-9]+>$') ~= nil
            or value:match('^[A-Za-z][A-Za-z0-9_-]*$') ~= nil)
end

local function valid_exact_enemy_action(policy)
    if policy.kind ~= 'cast' and policy.kind ~= 'ability'
        and policy.kind ~= 'weaponskill' and policy.kind ~= 'item'
        or not valid_action_label(policy.name, 64)
        or type(policy.target_names) ~= 'table'
        or #policy.target_names == 0
        or policy.prefer_highest_hpp ~= nil
            and type(policy.prefer_highest_hpp) ~= 'boolean'
    then
        return false
    end
    local seen = {}
    for _, name in ipairs(policy.target_names) do
        local key = type(name) == 'string' and name:lower() or ''
        if not valid_action_label(name, 64) or seen[key] then return false end
        seen[key] = true
    end
    return true
end

local function member_requirement(profile, wanted)
    if type(wanted) ~= 'string' then return nil end
    for name, requirement in pairs(profile.members or {}) do
        if type(name) == 'string' and name:lower() == wanted:lower() then
            return requirement
        end
    end
    return nil
end

local function enabled(policy)
    return type(policy) == 'table' and policy.enabled ~= false
end

local function validate_names(util, errors, label, values, members)
    if type(values) ~= 'table' then
        add(errors, label..' must be an array.')
        return
    end
    local seen = {}
    for _, name in ipairs(values) do
        local key = type(name) == 'string' and name:lower() or ''
        if not util.valid_name(name) then
            add(errors, label..' contains invalid name '..tostring(name)..'.')
        elseif members and not members[key] then
            add(errors, label..' contains non-member '..name..'.')
        elseif seen[key] then
            add(errors, label..' contains duplicate '..name..'.')
        else
            seen[key] = true
        end
    end
end

local function validate_support(util, errors, profile, normalized_members)
    local support = profile.support
    if type(support) ~= 'table' then
        add(errors, 'support is required.')
        return
    end
    for _, key in ipairs{'cor','brd','rdm','geo','pld','dnc'} do
        if type(support[key]) ~= 'table' then
            add(errors, 'support.'..key..' is required for the fixed composition.')
        elseif support[key].enabled ~= nil
            and type(support[key].enabled) ~= 'boolean'
        then
            add(errors, 'support.'..key..'.enabled must be boolean.')
        end
    end
    if enabled(support.cor) then
        if type(support.cor.rolls) ~= 'table' or #support.cor.rolls ~= 2 then
            add(errors, 'support.cor.rolls must contain exactly two rolls.')
        else
            for _, roll in ipairs(support.cor.rolls) do
                if not valid_string(roll, 24) then add(errors, 'Invalid COR roll.') end
            end
        end
    end
    for _, key in ipairs{'brd','rdm','pld','dnc'} do
        local policy = support[key]
        if enabled(policy) then
            if not util.valid_id(policy.preset, 32) then
                add(errors, 'support.'..key..'.preset is invalid.')
            end
            local authority = policy.target_source or policy.leader
            if not util.valid_name(authority) then
                add(errors, 'support.'..key..' requires a valid target source/leader.')
            elseif not normalized_members[authority:lower()] then
                add(errors, 'support.'..key..' authority is not a member.')
            end
        end
    end
    if enabled(support.rdm) then
        for _, key in ipairs{'haste','refresh','phalanx','defense'} do
            validate_names(util, errors, 'support.rdm.'..key,
                support.rdm[key] or {}, normalized_members)
        end
    end
    if enabled(support.geo) then
        local geo = support.geo
        if not util.valid_id(geo.mode, 16) then add(errors, 'Invalid GEO mode.') end
        if type(geo.zerg) ~= 'boolean' then
            add(errors, 'support.geo.zerg must be explicitly true or false.')
        end
        if geo.combat_entrust_only ~= nil
            and type(geo.combat_entrust_only) ~= 'boolean'
        then
            add(errors, 'support.geo.combat_entrust_only must be boolean.')
        end
        for _, key in ipairs{'indi','geo','entrust'} do
            if not valid_action_label(geo[key], 32) then
                add(errors, 'support.geo.'..key..' is invalid.')
            end
        end
        if not util.valid_name(geo.entrustee) then
            add(errors, 'support.geo.entrustee is invalid.')
        elseif not normalized_members[geo.entrustee:lower()] then
            add(errors, 'support.geo.entrustee is not a member.')
        end
    end
    for _, key in ipairs{'brd','rdm','geo'} do
        local policy = support[key]
        if enabled(policy) and policy.healbot ~= nil
            and policy.healbot ~= 'off' and policy.healbot ~= 'cure-na'
        then
            add(errors, 'support.'..key
                ..'.healbot must be off or cure-na.')
        end
    end
    if enabled(support.pld) then
        if support.pld.weapon_mode ~= nil
            and not valid_token(support.pld.weapon_mode, 32)
        then
            add(errors, 'support.pld.weapon_mode is invalid.')
        end
        for _, key in ipairs{'native_buffs','native_tank'} do
            if support.pld[key] ~= nil
                and type(support.pld[key]) ~= 'boolean'
            then
                add(errors, 'support.pld.'..key..' must be boolean.')
            end
        end
    end
end

local function validate_offense(errors, name, offense)
    if type(offense) ~= 'table'
        or not valid_token(offense.weapon_mode, 32)
        or not valid_action_label(offense.ws, 40)
        or tonumber(offense.tp) == nil
        or tonumber(offense.tp) % 1 ~= 0
        or tonumber(offense.tp) < 1000
        or tonumber(offense.tp) > 3000
    then
        add(errors, 'Missing/invalid offense policy for '..name..'.')
    elseif offense.hp_min ~= nil and (tonumber(offense.hp_min) == nil
        or tonumber(offense.hp_min) < 0
        or tonumber(offense.hp_min) > 100)
        or offense.hp_max ~= nil and (tonumber(offense.hp_max) == nil
            or tonumber(offense.hp_max) < 0
            or tonumber(offense.hp_max) > 100)
    then
        add(errors, 'Invalid offense HP bounds for '..name..'.')
    elseif tonumber(offense.hp_min or 0)
        > tonumber(offense.hp_max or 100)
    then
        add(errors, 'Offense HP bounds are reversed for '..name..'.')
    elseif offense.automatic ~= nil
        and type(offense.automatic) ~= 'boolean'
    then
        add(errors, 'Offense automatic must be boolean for '..name..'.')
    elseif offense.disable_native_autows ~= nil
        and type(offense.disable_native_autows) ~= 'boolean'
    then
        add(errors, 'Offense disable_native_autows must be boolean for '
            ..name..'.')
    elseif offense.session_ws ~= nil
        and type(offense.session_ws) ~= 'boolean'
    then
        add(errors, 'Offense session_ws must be boolean for '..name..'.')
    end
end

local PREFLIGHT_SLOTS = {
    main=true, sub=true, range=true, ammo=true, head=true, body=true,
    hands=true, legs=true, feet=true, neck=true, waist=true, left_ear=true,
    right_ear=true, left_ring=true, right_ring=true, back=true,
}
local PREFLIGHT_ACTION_KINDS = {
    spell=true, ability=true, weaponskill=true,
}
local function valid_preflight_names(value)
    if valid_action_label(value, 64) then return true end
    if type(value) ~= 'table' or type(value.any_of) ~= 'table'
        or #value.any_of == 0
    then return false end
    for _, name in ipairs(value.any_of) do
        if not valid_action_label(name, 64) then return false end
    end
    return true
end

local function valid_positive_integer(value)
    value = tonumber(value)
    return value ~= nil and value >= 1 and value % 1 == 0
end

local function supported_controller_protocol(value)
    value = tonumber(value)
    return value == 1 or value == 2
end

local function validate_gearswap_adapter(errors, profile)
    local adapter = profile.gearswap_adapter
    if adapter == nil then return end
    if type(adapter) ~= 'table'
        or not valid_adapter_identifier(adapter.id, 64)
        or not valid_adapter_version(adapter.version)
        or not valid_adapter_identifier(adapter.controller, 32)
        or not supported_controller_protocol(adapter.protocol)
        or type(adapter.actions) ~= 'table' or #adapter.actions == 0
    then
        add(errors, 'gearswap_adapter must use GearSwap-host-compatible '
            ..'lower-case grammar and pin a valid id, canonical semantic '
            ..'version, controller, and supported protocol 1 or 2.')
        return
    end
    if adapter.id ~= profile.id then
        add(errors, 'gearswap_adapter.id must equal the owning profile id; '
            ..'fight adapters cannot be shared between profiles.')
    end
    if adapter.lifecycle_authorization ~= nil
        and adapter.lifecycle_authorization ~= true
    then
        add(errors, 'gearswap_adapter.lifecycle_authorization must be true '
            ..'when exact commit-bound probe authorization is requested.')
    end
    local fences = adapter.lifecycle_stop_fences
    if adapter.lifecycle_authorization == true then
        if type(fences) ~= 'table' or next(fences) == nil then
            add(errors, 'gearswap_adapter.lifecycle_stop_fences must declare '
                ..'safe local terminal commands for lifecycle authorization.')
        else
            for member, command in pairs(fences) do
                local known_member = member == '*'
                    or type(member) == 'string'
                        and type(profile.members) == 'table'
                        and profile.members[member] ~= nil
                local safe_command = type(command) == 'string'
                    and #command <= 65
                    and command:match('^[a-z0-9%-]+ [a-z0-9%-]+$') ~= nil
                if not known_member or not safe_command then
                    add(errors, 'gearswap_adapter.lifecycle_stop_fences must '
                        ..'map * or an exact member to two lower-case command tokens.')
                end
            end
        end
    elseif fences ~= nil then
        add(errors, 'gearswap_adapter.lifecycle_stop_fences requires '
            ..'lifecycle_authorization=true.')
    end
    local seen = {}
    for _, action in ipairs(adapter.actions) do
        if not valid_adapter_semantic(action, 32) or action == 'probe'
            or seen[action]
        then
            add(errors, 'gearswap_adapter.actions contains an invalid, '
                ..'reserved, or duplicate semantic.')
        else
            seen[action] = true
        end
    end
    if tonumber(adapter.protocol) == 2
        and (adapter.lifecycle_authorization ~= true or not seen.operator)
    then
        add(errors, 'GearSwap adapter protocol 2 requires exact lifecycle '
            ..'authorization and the revisioned operator semantic.')
    end
end

local function validate_preflight_policy(errors, label, policy)
    if type(policy) ~= 'table' then
        add(errors, label..' must be a table.')
        return
    end
    if policy.equipment ~= nil and type(policy.equipment) ~= 'table' then
        add(errors, label..'.equipment must be a table.')
    else
        for slot, expected in pairs(policy.equipment or {}) do
            if not PREFLIGHT_SLOTS[slot]
                or not valid_preflight_names(expected)
            then add(errors, label..'.equipment.'..tostring(slot)..' is invalid.') end
        end
    end
    if policy.controller ~= nil then
        local controller = policy.controller
        if type(controller) ~= 'table'
            or not valid_adapter_identifier(controller.name, 32)
            or not supported_controller_protocol(controller.protocol) then
            add(errors, label..'.controller is unsupported.')
        end
    end
    if policy.buffs ~= nil and type(policy.buffs) ~= 'table' then
        add(errors, label..'.buffs must be an array.')
    else
        local seen_buffs = {}
        for _, buff in ipairs(policy.buffs or {}) do
            local exact = type(buff) == 'table' and tonumber(buff.id) or nil
            local label_name = type(buff) == 'table' and buff.label or buff
            local key = exact and ('id:'..tostring(exact))
                or type(buff) == 'string' and ('name:'..buff:lower()) or ''
            local valid_exact = type(buff) == 'table'
                and valid_positive_integer(exact) and exact <= 65535
                and valid_action_label(label_name, 64)
                and buff.id ~= nil and buff.label ~= nil
            if (type(buff) == 'table' and not valid_exact)
                or (type(buff) ~= 'table'
                    and not valid_action_label(buff, 64))
                or seen_buffs[key]
            then
                add(errors, label..' contains an invalid or duplicate buff requirement.')
            else
                seen_buffs[key] = true
            end
        end
    end
    if policy.items ~= nil and type(policy.items) ~= 'table' then
        add(errors, label..'.items must be an array.')
    else
        for _, requirement in ipairs(policy.items or {}) do
            local names = type(requirement) == 'table' and (requirement.name
                or {any_of=requirement.any_of}) or nil
            if type(requirement) ~= 'table'
                or requirement.name ~= nil and requirement.any_of ~= nil
                or not valid_preflight_names(names)
                or not valid_positive_integer(requirement.minimum or 1)
                or requirement.warn_below ~= nil
                    and (not valid_positive_integer(requirement.warn_below)
                        or tonumber(requirement.warn_below)
                            < tonumber(requirement.minimum or 1))
                or requirement.bag_group ~= nil
                    and requirement.bag_group ~= 'equippable'
                    and requirement.bag_group ~= 'inventory'
                or requirement.optional ~= nil
                    and type(requirement.optional) ~= 'boolean'
            then add(errors, label..' contains an invalid item requirement.') end
        end
    end
    if policy.key_items ~= nil and type(policy.key_items) ~= 'table' then
        add(errors, label..'.key_items must be an array.')
    else
        for _, requirement in ipairs(policy.key_items or {}) do
            local one_id = type(requirement) == 'table'
                and valid_positive_integer(requirement.id)
            local ids = type(requirement) == 'table' and requirement.ids or nil
            local many_ids = type(ids) == 'table' and #ids > 0
            if many_ids then
                for _, id in ipairs(ids) do
                    if not valid_positive_integer(id) then many_ids = false; break end
                end
            end
            if type(requirement) ~= 'table'
                or (one_id and many_ids) or (not one_id and not many_ids)
                or not valid_text(requirement.label, 80)
                or requirement.optional ~= nil
                    and type(requirement.optional) ~= 'boolean'
            then add(errors, label..' contains an invalid key-item requirement.') end
        end
    end
    if policy.actions ~= nil and type(policy.actions) ~= 'table' then
        add(errors, label..'.actions must be an array.')
    else
        for _, requirement in ipairs(policy.actions or {}) do
            if type(requirement) ~= 'table'
                or not PREFLIGHT_ACTION_KINDS[requirement.kind]
                or not valid_action_label(requirement.name, 64)
                or requirement.optional ~= nil
                    and type(requirement.optional) ~= 'boolean'
            then add(errors, label..' contains an invalid action requirement.') end
        end
    end
end

local function validate_preflight(util, errors, profile, normalized_members)
    local policy = profile.preflight
    if policy == nil then return end
    if type(policy) ~= 'table' then
        add(errors, 'preflight must be a table.')
        return
    end
    if type(policy.required_before_combat) ~= 'boolean' then
        add(errors, 'preflight.required_before_combat must be boolean.')
    end
    if policy.zone ~= nil
        and (not valid_positive_integer(policy.zone)
            or tonumber(policy.zone) > 1024)
    then
        add(errors, 'preflight.zone must be a valid zone ID.')
    end
    if policy.auto_after_apply ~= nil
        and (tonumber(policy.auto_after_apply) == nil
            or tonumber(policy.auto_after_apply) < 0
            or tonumber(policy.auto_after_apply) > 30)
    then
        add(errors, 'preflight.auto_after_apply must be between 0 and 30 seconds.')
    end
    if policy.auto_retry_seconds ~= nil
        and (tonumber(policy.auto_retry_seconds) == nil
            or tonumber(policy.auto_retry_seconds) < 3
            or tonumber(policy.auto_retry_seconds) > 30)
    then
        add(errors, 'preflight.auto_retry_seconds must be between 3 and 30 seconds.')
    end
    if policy.max_age_seconds ~= nil
        and (tonumber(policy.max_age_seconds) == nil
            or tonumber(policy.max_age_seconds) < 30
            or tonumber(policy.max_age_seconds) > 600)
    then
        add(errors, 'preflight.max_age_seconds must be between 30 and 600 seconds.')
    end
    if policy.all ~= nil then
        validate_preflight_policy(errors, 'preflight.all', policy.all)
    end
    if type(policy.members) ~= 'table' then
        add(errors, 'preflight.members must be a table.')
        return
    end
    for name, member_policy in pairs(policy.members) do
        if not util.valid_name(name)
            or not normalized_members[(name or ''):lower()]
        then
            add(errors, 'Invalid preflight member '..tostring(name)..'.')
        else
            validate_preflight_policy(errors,
                'preflight.members.'..name, member_policy)
        end
    end
    if policy.all == nil then
        for name, _ in pairs(profile.members or {}) do
            local found = false
            for preflight_name, _ in pairs(policy.members) do
                if util.same_name(name, preflight_name) then found = true; break end
            end
            if not found then add(errors, 'Missing preflight member '..name..'.') end
        end
    end
end

function M.validate(util, profile, directory_id)
    local errors = {}
    if type(profile) ~= 'table' then return {'Profile did not return a table.'} end
    if profile.schema ~= 1 then add(errors, 'schema must equal 1.') end
    if not valid_adapter_identifier(profile.id, 64) then
        add(errors, 'Invalid profile id; canonical ids use lower-case letters, '
            ..'digits, and hyphens so they remain adapter-capable.')
    end
    if type(profile.id) == 'string' and RESERVED_COMMANDS[profile.id] then
        add(errors, 'Profile id is a reserved PartyTactics command.')
    end
    if directory_id and profile.id ~= directory_id then
        add(errors, 'Directory id and profile id differ.')
    end
    if not valid_string(profile.version, 24)
        or profile.version:match('^%d+%.%d+%.%d+$') == nil
    then
        add(errors, 'version must use semantic x.y.z form.')
    end
    if not valid_string(profile.label, 100) then add(errors, 'Invalid label.') end
    if not util.valid_id(profile.policy_id, 28) then add(errors, 'Invalid policy_id.') end
    if profile.runtime_owns_pull ~= nil
        and type(profile.runtime_owns_pull) ~= 'boolean'
    then
        add(errors, 'runtime_owns_pull must be boolean when declared.')
    end
    if type(profile.aliases) ~= 'table' then
        add(errors, 'aliases must be an array.')
    else
        local seen_aliases = {}
        for _, alias in ipairs(profile.aliases) do
            if not util.valid_id(alias, 48) then
                add(errors, 'Invalid alias.')
            elseif RESERVED_COMMANDS[alias] then
                add(errors, 'Alias '..alias..' is a reserved PartyTactics command.')
            elseif seen_aliases[alias] then
                add(errors, 'Duplicate alias '..alias..'.')
            else
                seen_aliases[alias] = true
            end
        end
    end

    if profile.auto_select ~= nil then
        local policy = profile.auto_select
        if type(policy) ~= 'table' then
            add(errors, 'auto_select must be a table when declared.')
        else
            if type(policy.zones) ~= 'table' then
                add(errors, 'auto_select.zones must be an integer-keyed set.')
            else
                local zone_count = 0
                for zone, enabled in pairs(policy.zones) do
                    zone_count = zone_count + 1
                    if type(zone) ~= 'number' or zone < 1 or zone > 1024
                        or zone ~= math.floor(zone) or enabled ~= true
                    then
                        add(errors, 'auto_select.zones contains an invalid zone.')
                    end
                end
                if zone_count == 0 then
                    add(errors, 'auto_select.zones must not be empty.')
                end
            end
            if type(policy.targets) ~= 'table' then
                add(errors, 'auto_select.targets must be an array.')
            else
                local seen_targets = {}
                if #policy.targets == 0 then
                    add(errors, 'auto_select.targets must not be empty.')
                end
                for _, target in ipairs(policy.targets) do
                    local key = type(target) == 'string' and target:lower() or nil
                    if not valid_string(target, 80)
                        or target:find('[|\r\n]')
                    then
                        add(errors, 'auto_select.targets contains an invalid exact name.')
                    elseif seen_targets[key] then
                        add(errors, 'Duplicate auto-select target '..target..'.')
                    else
                        seen_targets[key] = true
                    end
                end
            end
        end
    end

    if type(profile.members) ~= 'table' then
        add(errors, 'members is required.')
        return errors
    end
    local normalized_members = {}
    local member_count = 0
    for name, requirement in pairs(profile.members) do
        member_count = member_count + 1
        if not util.valid_name(name) or type(requirement) ~= 'table'
            or type(requirement.main_job) ~= 'string'
            or requirement.main_job:match('^[A-Z][A-Z][A-Z]$') == nil
        then
            add(errors, 'Invalid member requirement for '..tostring(name)..'.')
        else
            if normalized_members[name:lower()] then
                add(errors, 'Duplicate member name differing only by case: '..name..'.')
            end
            normalized_members[name:lower()] = true
        end
        if type(requirement) == 'table' and requirement.sub_jobs ~= nil
            and type(requirement.sub_jobs) ~= 'table'
        then
            add(errors, 'sub_jobs must be an array for '..tostring(name)..'.')
        end
        for _, sub_job in ipairs(
            type(requirement) == 'table'
                and type(requirement.sub_jobs) == 'table'
                and requirement.sub_jobs or {}) do
            if type(sub_job) ~= 'string'
                or sub_job:match('^[A-Z][A-Z][A-Z]$') == nil
            then
                add(errors, 'Invalid subjob for '..tostring(name)..'.')
            end
        end
    end
    if member_count ~= 6 then add(errors, 'Exactly six named members are required.') end

    if type(profile.roles) ~= 'table' then
        add(errors, 'roles is required.')
    else
        for role, name in pairs(profile.roles) do
            if not util.valid_id(role, 32) or not util.valid_name(name)
                or not normalized_members[(name or ''):lower()]
            then
                add(errors, 'Invalid role assignment '..tostring(role)..'.')
            end
        end
    end

    local combat = profile.combat
    if type(combat) ~= 'table' then
        add(errors, 'combat is required.')
    else
        if not util.valid_name(combat.leader)
            or not normalized_members[(combat.leader or ''):lower()]
        then add(errors, 'Invalid combat leader.') end
        if not util.valid_name(combat.puller)
            or not normalized_members[(combat.puller or ''):lower()]
        then add(errors, 'Invalid combat puller.') end
        if profile.runtime_owns_pull == true
            and not util.contains_name(combat.attackers or {}, combat.puller)
        then
            add(errors, 'A runtime-owned puller must be a configured attacker.')
        end
        if combat.movement ~= 'stationary' and combat.movement ~= 'mobile' then
            add(errors, 'combat.movement must be stationary or mobile.')
        end
        validate_names(util, errors, 'combat.attackers', combat.attackers,
            normalized_members)
        validate_names(util, errors, 'combat.targeters', combat.targeters,
            normalized_members)
        validate_names(util, errors, 'combat.priority_attackers',
            combat.priority_attackers or {}, normalized_members)
        -- An attacker omitted from targeters is a directed-only lane. It
        -- ignores broad target synchronization and may be moved only by an
        -- exact forceidto request from the encounter runtime.
        if (combat.priority_target == nil)
            ~= (#(combat.priority_attackers or {}) == 0)
        then
            add(errors, 'Priority target and attackers must be configured together.')
        end
        if combat.priority_target
            and not valid_action_label(combat.priority_target, 64)
        then
            add(errors, 'Invalid priority target.')
        end
        if combat.target_exclusions == nil then
            add(errors, 'combat.target_exclusions must be explicitly declared.')
        elseif type(combat.target_exclusions) ~= 'table' then
            add(errors, 'combat.target_exclusions must be an array.')
        else
            local seen_exclusions = {}
            for _, exclusion in ipairs(combat.target_exclusions) do
                if exclusion ~= 'elemental' then
                    add(errors, 'Unsupported target exclusion '
                        ..tostring(exclusion)..'.')
                elseif seen_exclusions[exclusion] then
                    add(errors, 'Duplicate target exclusion '..exclusion..'.')
                else
                    seen_exclusions[exclusion] = true
                end
            end
        end
    end

    validate_support(util, errors, profile, normalized_members)
    validate_gearswap_adapter(errors, profile)
    validate_preflight(util, errors, profile, normalized_members)

    local adapter = profile.gearswap_adapter
    if adapter then
        if type(profile.preflight) ~= 'table'
            or type(profile.preflight.members) ~= 'table'
        then
            add(errors, 'A pinned GearSwap adapter requires per-member '
                ..'controller routing metadata in preflight.members.')
        end
        for member_name, _ in pairs(profile.members or {}) do
            local policy
            for preflight_name, candidate in pairs(
                type(profile.preflight) == 'table'
                    and profile.preflight.members or {})
            do
                if util.same_name(member_name, preflight_name) then
                    policy = candidate
                    break
                end
            end
            local controller = type(policy) == 'table'
                and policy.controller or nil
            if type(controller) ~= 'table'
                or controller.name ~= adapter.controller
                or tonumber(controller.protocol)
                    ~= tonumber(adapter.protocol)
            then
                add(errors, 'Pinned GearSwap adapter requires matching '
                    ..'controller routing metadata for '..tostring(member_name)..'.')
            end
        end
    end

    if profile.preflight and type(profile.preflight.members) == 'table' then
        for name, policy in pairs(profile.preflight.members) do
            local controller = type(policy) == 'table' and policy.controller
                or nil
            if controller and (not adapter
                or controller.name ~= adapter.controller
                or tonumber(controller.protocol)
                    ~= tonumber(adapter.protocol))
            then
                add(errors, 'preflight controller for '..tostring(name)
                    ..' does not match the pinned GearSwap adapter.')
            end
        end
    end

    if type(profile.offense) ~= 'table' then
        add(errors, 'offense is required.')
    else
        for _, name in ipairs((combat and combat.attackers) or {}) do
            validate_offense(errors, name, profile.offense[name])
        end
        for name, offense in pairs(profile.offense) do
            if type(name) ~= 'string' then
                add(errors, 'Offense policy has a non-string member key.')
            elseif not normalized_members[name:lower()] then
                add(errors, 'Offense policy for non-member '..name..'.')
            elseif not util.contains_name(
                (combat and combat.attackers) or {}, name)
            then
                if type(offense) ~= 'table'
                    or offense.automatic ~= false
                then
                    add(errors, 'Non-attacker offense for '..name
                        ..' must be loadout-only (automatic=false).')
                else
                    validate_offense(errors, name, offense)
                end
            end
        end
    end

    for action, policy in pairs(profile.manual_actions or {}) do
        if RESERVED_COMMANDS[action] and action ~= 'sleep' then
            add(errors, 'Manual action '..tostring(action)
                ..' is a reserved PartyTactics command.')
        elseif not util.valid_id(action, 24) or type(policy) ~= 'table'
            or not util.valid_name(policy.character)
            or not normalized_members[(policy.character or ''):lower()]
            or not util.valid_id(policy.adapter, 32)
        then
            add(errors, 'Invalid manual action '..tostring(action)..'.')
        elseif action == 'sleep' and (policy.character ~= 'Barneystinson'
            or policy.adapter ~= 'brd-pack-sleep'
            or type(profile.members.Barneystinson) ~= 'table'
            or profile.members.Barneystinson.main_job ~= 'BRD')
        then
            add(errors, 'Manual action sleep is reserved for the '
                ..'Barneystinson brd-pack-sleep controller.')
        elseif (policy.adapter == 'typed-action'
            or policy.adapter == 'clarion-extra-song')
            and (policy.kind ~= 'cast' and policy.kind ~= 'ability'
                and policy.kind ~= 'weaponskill' and policy.kind ~= 'item'
                or not valid_action_label(policy.name, 64)
                or not valid_action_target(policy.target))
        then
            add(errors, 'Invalid typed manual action '..tostring(action)..'.')
        elseif policy.adapter == 'exact-enemy-action'
            and not valid_exact_enemy_action(policy)
        then
            add(errors, 'Invalid exact-enemy manual action '
                ..tostring(action)..'.')
        elseif policy.adapter == 'rdm-exact-silence'
            and ((member_requirement(profile, policy.character) or {}).main_job
                    ~= 'RDM'
                or policy.kind ~= nil or policy.name ~= nil
                or policy.target ~= nil
                or not valid_exact_enemy_action({
                    kind='cast', name='Silence',
                    target_names=policy.target_names,
                    prefer_highest_hpp=policy.prefer_highest_hpp,
                }))
        then
            add(errors, 'Invalid queued-Silence manual action '
                ..tostring(action)..'.')
        end
    end
    if profile.safety ~= nil then
        if type(profile.safety) ~= 'table'
            or profile.safety.reraise ~= nil
                and type(profile.safety.reraise) ~= 'boolean'
        then
            add(errors, 'safety must contain a boolean reraise policy.')
        end
    end
    if profile.easyfarm ~= nil then
        if type(profile.easyfarm) ~= 'table'
            or not util.valid_name(profile.easyfarm.character)
            or not normalized_members[(profile.easyfarm.character or ''):lower()]
            or profile.easyfarm.expected_target ~= nil
                and not valid_action_label(profile.easyfarm.expected_target, 64)
            or profile.easyfarm.artifact ~= nil
                and (type(profile.easyfarm.artifact) ~= 'string'
                    or profile.easyfarm.artifact:match(
                        '^easyfarm/[A-Za-z0-9_.-]+%.eup$') == nil)
            or profile.easyfarm.detection_distance ~= nil
                and (tonumber(profile.easyfarm.detection_distance) == nil
                    or tonumber(profile.easyfarm.detection_distance) <= 0
                    or tonumber(profile.easyfarm.detection_distance) > 50)
            or profile.easyfarm.pull_action ~= nil
                and not valid_action_label(profile.easyfarm.pull_action, 64)
            or profile.easyfarm.pull_distance ~= nil
                and (tonumber(profile.easyfarm.pull_distance) == nil
                    or tonumber(profile.easyfarm.pull_distance) <= 0
                    or tonumber(profile.easyfarm.pull_distance) > 50)
            or profile.easyfarm.pull_distance ~= nil
                and profile.easyfarm.detection_distance ~= nil
                and tonumber(profile.easyfarm.pull_distance)
                    < tonumber(profile.easyfarm.detection_distance)
        then
            add(errors, 'easyfarm policy is invalid.')
        end
    end
    if type(profile.advisories) ~= 'table' then
        add(errors, 'advisories must be an array.')
    else
        for _, advisory in ipairs(profile.advisories) do
            if not valid_text(advisory, 500) then
                add(errors, 'Invalid advisory text.')
            end
        end
    end
    if profile.commands or profile.setup or profile.teardown then
        add(errors, 'Profiles may not contain raw setup/teardown commands.')
    end
    return errors
end

return M
