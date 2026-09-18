--[[
PartyTactics

A profile-isolated party orchestrator for a fixed local multibox composition.
It selects policies and requests actions; GearSwap remains the sole owner of
equipment, slot locks, precast/midcast sets, and native job callbacks.
]]

_addon.name = 'PartyTactics'
_addon.author = 'OpenAI Codex'
_addon.version = '0.13.3'
_addon.commands = {'partytactics', 'ptactics', 'pt'}

local res = require('resources')
require('tables')

local party_tactics_perf
do
    local ok, module = pcall(require, 'hotpath_profiler')
    if ok and type(module) == 'table' and type(module.new) == 'function' then
        local created, instance = pcall(module.new, {
            addon = _addon.name,
            path = windower.addon_path,
        })
        if created then party_tactics_perf = instance end
    end
end

local PREFIX = 'PARTYTACTICS1'
local PREPARE_TIMEOUT = 8
local PREPARE_RETRY_INTERVAL = 0.75
local COMMIT_RETRY_INTERVAL = 0.75
local COMMIT_RETRY_WINDOW = 5
local APPLY_ACK_TIMEOUT = 15
local PREFLIGHT_TIMEOUT = 8
local PREFLIGHT_RETRY_INTERVAL = 0.75
local TRANSITION_DELAY = 2
local STATE_SYNC_INTERVAL = 5
local CONTROLLER_PROBE_RETRY_INTERVAL = 2
local CONTROLLER_PROBE_WARN_AFTER = 10
local CONTROLLER_PROBE_SLOW_RETRY_INTERVAL = 12
local MAINTENANCE_INTERVAL = 0.75
local RERAISE_CHECK_INTERVAL = 1

local function load_module(relative_path)
    local loader, load_error = loadfile(windower.addon_path..relative_path)
    if not loader then error(load_error) end
    local ok, module = pcall(loader)
    if not ok then error(module) end
    if type(module) ~= 'table' then
        error(relative_path..' did not return a module table')
    end
    return module
end

local util = load_module('lib/util.lua')
local schema = load_module('lib/schema.lua')
local compiler = load_module('lib/compiler.lua')
local profile_loader = load_module('lib/profile_loader.lua')
local identity_extensions = load_module('lib/identity_extensions.lua')
local supplemental_aliases = load_module('lib/supplemental_aliases.lua')
local manual_loader = load_module('lib/manual_loader.lua')
local action_api = load_module('lib/action_api.lua')
local preflight = load_module('lib/preflight.lua')
local sandbox = load_module('lib/sandbox.lua')
local fingerprint = load_module('lib/fingerprint.lua')
local function sandboxed_loadfile(path)
    return sandbox.load(path, loadfile)
end

local base_identity_registry = load_module('data/profile_registry.lua')
local identity_registry, identity_extension_errors = identity_extensions.extend(
    util, base_identity_registry,
    windower.addon_path..'data/profile_identities/', windower.get_dir,
    windower.file_exists, sandboxed_loadfile)

local function chat(color, message)
    windower.add_to_chat(color or 207, '[PartyTactics] '..tostring(message))
end

local function issue(command)
    if type(command) == 'string' and command ~= '' then
        windower.send_command(command)
    end
end

local loaded_profiles, aliases, catalog_errors = profile_loader.discover(
    util, schema, windower.addon_path..'profiles/', windower.get_dir,
    windower.file_exists, sandboxed_loadfile, fingerprint.file,
    identity_registry)
local catalog_warnings = {}

local gearswap_maintenance_fast_lane = fingerprint.contains(
    windower.addon_path..'../GearSwap/gearswap.lua',
    'function party_tactics_maintenance_tick()')
if not gearswap_maintenance_fast_lane then
    catalog_warnings[#catalog_warnings + 1] =
        'GearSwap maintenance fast lane is unavailable; using compatible '
        ..'gs c maintenance ticks'
end
local MAINTENANCE_FALLBACK_COMMANDS = {
    BRD='gs c pstartbrd tick', RDM='gs c pstartrdm tick',
    PLD='gs c pstartpld tick', DNC='gs c pstartdnc tick',
    GEO='gs c pstartgeo tick', WHM='gs c pstartwhm tick',
}

for _, message in ipairs(identity_extension_errors) do
    catalog_errors[#catalog_errors + 1] = 'identity '..message
end
local manual_adapters, adapter_errors = manual_loader.discover(
    util, windower.addon_path..'adapters/manual/', windower.get_dir,
    windower.file_exists, sandboxed_loadfile, fingerprint.file)
for _, message in ipairs(adapter_errors) do
    catalog_errors[#catalog_errors + 1] = 'manual adapter '..message
end
local supplemental_sidecars, supplemental_discovery_errors =
    supplemental_aliases.discover(
        util, windower.addon_path..'data/supplemental_aliases/',
        windower.get_dir, windower.file_exists, sandboxed_loadfile)
for _, message in ipairs(supplemental_discovery_errors) do
    catalog_errors[#catalog_errors + 1] = 'supplemental alias '..message
end

-- Direct profile shortcuts resolve before active-profile manual actions. A
-- convenience name therefore may not reuse an action declared by any loaded
-- profile, even when that profile is not currently selected.
local loaded_manual_actions = {}
for _, id in ipairs(util.sorted_keys(loaded_profiles)) do
    for action, _ in pairs(loaded_profiles[id].manual_actions or {}) do
        loaded_manual_actions[action] = true
    end
end

-- The first migrated profiles still use five established GearSwap support
-- controllers. Their behavior is frozen as one immutable PartyTactics-owned
-- version. Source/live differences are reported, but never used as permission
-- to withhold an otherwise valid profile. A future fight uses a new pinned
-- adapter instead of editing this closure.
local LEGACY_GEARSWAP_VERSION = '1.0.0'
local GEARSWAP_HOST_REVISION = '1.2.1'
local LEGACY_GEARSWAP_FILES = {
    {source='PartyTactics_Legacy_BRD.lua', live='PartyStart_BRD.lua'},
    {source='PartyTactics_Legacy_RDM.lua', live='PartyStart_RDM.lua'},
    {source='PartyTactics_Legacy_GEO.lua', live='PartyStart_GEO.lua'},
    {source='PartyTactics_Legacy_PLD.lua', live='PartyStart_PLD.lua'},
    {source='PartyTactics_Legacy_DNC.lua', live='PartyStart_DNC.lua'},
}
local LEGACY_HELPER_PREFIX = {
    BRD='pstartbrd', RDM='pstartrdm', GEO='pstartgeo',
    PLD='pstartpld', DNC='pstartdnc',
}
local legacy_gearswap_digests = {}
local legacy_gearswap_ready = true
for _, file in ipairs(LEGACY_GEARSWAP_FILES) do
    local relative = 'legacy/'..LEGACY_GEARSWAP_VERSION..'/'..file.source
    local source = fingerprint.file(
        windower.addon_path..'gearswap/'..relative)
    local live = fingerprint.file(windower.addon_path
        ..'../GearSwap/data/common/'..file.live)
    legacy_gearswap_digests[#legacy_gearswap_digests + 1] = source
    legacy_gearswap_digests[#legacy_gearswap_digests + 1] = live
    if source == 'unavailable' or live == 'unavailable' or source ~= live then
        legacy_gearswap_ready = false
        catalog_warnings[#catalog_warnings + 1] =
            ('frozen GearSwap adapter %s@%s is missing or differs from Common')
                :format(file.source, LEGACY_GEARSWAP_VERSION)
    end
end

-- The host is dormant for adapter-free profiles, but it still wraps every
-- live job callback. It is therefore part of every profile's behavior
-- closure, not merely the closure of profiles that activate an adapter.
local gearswap_host_source_digest = fingerprint.file(
    windower.addon_path..'gearswap/PartyTactics_Host.lua')
local gearswap_host_live_digest = fingerprint.file(
    windower.addon_path
        ..'../GearSwap/data/common/PartyTactics/PartyTactics_Host.lua')
local gearswap_host_ready = gearswap_host_source_digest ~= 'unavailable'
    and gearswap_host_live_digest ~= 'unavailable'
    and gearswap_host_source_digest == gearswap_host_live_digest
if not gearswap_host_ready then
    catalog_warnings[#catalog_warnings + 1] =
        'stable GearSwap host is missing or differs from the Common copy'
end

local profiles, plans = {}, {}
for _, id in ipairs(util.sorted_keys(loaded_profiles)) do
    local ok, plan, compile_errors = pcall(
        compiler.compile, util, schema, loaded_profiles[id])
    if not ok then
        catalog_errors[#catalog_errors + 1] = id
            ..' compiler: '..tostring(plan)
    elseif not plan then
        catalog_errors[#catalog_errors + 1] = id..' compiler: '
            ..table.concat(compile_errors or {}, ' ')
    else
        profiles[id] = loaded_profiles[id]
        plans[id] = plan
    end
end

local engine_sources = {
    fingerprint.file(windower.addon_path..'PartyTactics.lua'),
    fingerprint.file(windower.addon_path..'lib/util.lua'),
    fingerprint.file(windower.addon_path..'lib/schema.lua'),
    fingerprint.file(windower.addon_path..'lib/compiler.lua'),
    fingerprint.file(windower.addon_path..'lib/fingerprint.lua'),
    fingerprint.file(windower.addon_path..'lib/action_api.lua'),
    fingerprint.file(windower.addon_path..'lib/preflight.lua'),
    fingerprint.file(windower.addon_path..'lib/profile_loader.lua'),
    fingerprint.file(windower.addon_path..'lib/identity_extensions.lua'),
    fingerprint.file(windower.addon_path..'lib/supplemental_aliases.lua'),
    fingerprint.file(windower.addon_path..'lib/manual_loader.lua'),
    fingerprint.file(windower.addon_path..'lib/sandbox.lua'),
    -- The fixed-roster emergency sleep fallback is available to every
    -- profile, so its reviewed adapter is part of every engine signature.
    fingerprint.file(windower.addon_path
        ..'adapters/manual/brd-pack-sleep.lua'),
    -- Integration code is part of the behavior contract too. These five
    -- frozen compatibility helpers serve the already-migrated profiles. New
    -- fight behavior must live in a profile-pinned PartyTactics adapter.
    fingerprint.file(windower.addon_path..'../PartyCombat/PartyCombat.lua'),
    fingerprint.file(windower.addon_path..'../AutoWS2/AutoWS2.lua'),
    fingerprint.file(windower.addon_path..'../Roller2/Roller2.lua'),
    fingerprint.file(windower.addon_path..'../HealBot/HealBot.lua'),
    gearswap_host_source_digest,
    gearswap_host_live_digest,
}
local engine_source_labels = {
    'PartyTactics.lua', 'lib/util.lua', 'lib/schema.lua',
    'lib/compiler.lua', 'lib/fingerprint.lua', 'lib/action_api.lua',
    'lib/preflight.lua', 'lib/profile_loader.lua',
    'lib/identity_extensions.lua', 'lib/supplemental_aliases.lua',
    'lib/manual_loader.lua', 'lib/sandbox.lua',
    'universal brd-pack-sleep adapter',
    'PartyCombat.lua', 'AutoWS2.lua', 'Roller2.lua', 'HealBot.lua',
    'GearSwap host source', 'GearSwap host live copy',
}
for _, digest in ipairs(legacy_gearswap_digests) do
    engine_sources[#engine_sources + 1] = digest
end
for _, file in ipairs(LEGACY_GEARSWAP_FILES) do
    engine_source_labels[#engine_source_labels + 1] =
        'frozen '..file.source..' source'
    engine_source_labels[#engine_source_labels + 1] =
        'frozen '..file.live..' live copy'
end
for index, digest in ipairs(engine_sources) do
    if digest == 'unavailable' then
        catalog_warnings[#catalog_warnings + 1] = 'engine dependency '
            ..tostring(engine_source_labels[index] or index)
            ..' is unavailable; affected actions will remain best-effort'
    end
end
local engine_signature = fingerprint.combine(engine_sources)
for _, id in ipairs(util.sorted_keys(plans)) do
    local profile_adapter = profiles[id].gearswap_adapter
    if profile_adapter then
        local relative = profile_adapter.id..'/'
            ..profile_adapter.version..'.lua'
        profiles[id].__gearswap_host_source_digest =
            gearswap_host_source_digest
        profiles[id].__gearswap_host_live_digest = gearswap_host_live_digest
        profiles[id].__gearswap_adapter_source_digest = fingerprint.file(
            windower.addon_path..'gearswap/adapters/'..relative)
        profiles[id].__gearswap_adapter_live_digest = fingerprint.file(
            windower.addon_path
                ..'../GearSwap/data/common/PartyTactics/adapters/'..relative)
    end
    local profile_adapter_ready = true
    if profile_adapter then
        profile_adapter_ready =
            profiles[id].__gearswap_host_source_digest ~= 'unavailable'
            and profiles[id].__gearswap_host_live_digest ~= 'unavailable'
            and profiles[id].__gearswap_host_source_digest
                == profiles[id].__gearswap_host_live_digest
            and profiles[id].__gearswap_adapter_source_digest ~= 'unavailable'
            and profiles[id].__gearswap_adapter_live_digest ~= 'unavailable'
            and profiles[id].__gearswap_adapter_source_digest
                == profiles[id].__gearswap_adapter_live_digest
    end
    if profile_adapter and not profile_adapter_ready then
        catalog_warnings[#catalog_warnings + 1] = id
            ..': pinned GearSwap host/adapter is missing or differs from Common; '
            ..'the profile remains selectable and unaffected lanes still run'
    end
    local ok, signature
    ok, signature = pcall(fingerprint.plan,
        profiles[id], plans[id], manual_adapters, engine_signature)
    if ok then
        plans[id].signature = signature
    else
        catalog_errors[#catalog_errors + 1] =
            id..' fingerprint: '..tostring(signature)
        profiles[id], plans[id] = nil, nil
    end
end

-- Friendly encounter names are optional overlays, not profile identities.
-- Install them only after compilation and dependency verification so a
-- missing or quarantined target cannot become a selectable shortcut. The
-- loader returns a copy, leaving every established alias intact on failure.
local supplemental_apply_errors
aliases, supplemental_apply_errors = supplemental_aliases.apply(
    util, supplemental_sidecars, profiles, aliases, identity_registry,
    loaded_manual_actions)
for _, message in ipairs(supplemental_apply_errors) do
    catalog_errors[#catalog_errors + 1] = 'supplemental alias '..message
end

-- An exact hostile target selects its encounter profile. Location is not part
-- of the decision, so the operator can choose the fastest valid camp. Any
-- duplicate zone/name declaration is removed from automatic selection while
-- both profiles remain available through the recovery command surface.
local auto_profile_targets = {}
for _, id in ipairs(util.sorted_keys(profiles)) do
    local policy = profiles[id].auto_select
    if type(policy) == 'table' then
        for zone, enabled in pairs(policy.zones or {}) do
            if enabled == true then
                auto_profile_targets[zone] = auto_profile_targets[zone] or {}
                for _, target_name in ipairs(policy.targets or {}) do
                    local key = target_name:lower()
                    local prior = auto_profile_targets[zone][key]
                    if prior and prior ~= id then
                        auto_profile_targets[zone][key] = false
                        catalog_errors[#catalog_errors + 1] =
                            ('automatic target %s in zone %d is declared by %s and %s')
                                :format(target_name, zone, prior, id)
                    elseif prior == nil then
                        auto_profile_targets[zone][key] = id
                    end
                end
            end
        end
    end
end

local sessions = {}
local applied_generations = {}
local retired_generations = {}
-- A distributed stop tombstones the exact profile generations known by the
-- caller. Exact tombstones are intentionally not ordered: generation nonces
-- contain a process-local player id and clock token, so comparing unrelated
-- initiators would let a stale stop suppress a legitimate later load.
local stop_tombstones = {}
local stop_seen = {}
local manual_seen = {}
local manual_result_seen = {}
-- Operator requests are ordered twice: each sender contributes a monotonic
-- source sequence, then the profile leader serializes accepted requests into
-- one authoritative revision.  Request nonces alone could only deduplicate;
-- they could not stop a delayed ON from overtaking a later OFF.
local operator_source_sequence = 0
local preflight_checks = {}
local active = nil
local pending_commit = nil
local pending_reapply = nil
local terminal_reassert = nil
local selected_id = nil
local next_state_sync = 0
local next_maintenance = 0
local nonce_counter = 0
local reapply_epoch = 0
local reraise_guard = {enabled=false, next_check=0, warned=false}
local recent_hostile_target = nil
local last_auto_profile_id = nil
local last_auto_profile_at = -10

local stop_local
local handle_commit
local finalize_session
local begin_preflight
local schedule_reapply
local announce_state
local request_operator_state
local process_operator_request
local process_operator_state
local set_operator_snapshot
local apply_operator_locally
local process_runtime_controller
local process_adapter_status
local fence_required_controller_stop

local function valid_nonce(nonce)
    return type(nonce) == 'string'
        and nonce:match('^%d+%-%d+%-%d+$') ~= nil
end

local function valid_epoch_token(value)
    if type(value) ~= 'string' or #value < 1 or #value > 10
        or value:match('^%d+$') == nil
        or (#value > 1 and value:sub(1, 1) == '0')
    then
        return nil
    end
    local epoch = tonumber(value)
    return epoch and epoch >= 0 and epoch <= 2147483647
        and epoch == math.floor(epoch) and epoch or nil
end

local function valid_operator_counter(value, allow_zero)
    if type(value) ~= 'string' or #value < 1 or #value > 10
        or value:match('^%d+$') == nil
        or (#value > 1 and value:sub(1, 1) == '0')
    then
        return nil
    end
    local number = tonumber(value)
    local floor = allow_zero and 0 or 1
    return number and number >= floor and number <= 2147483647
        and number == math.floor(number) and number or nil
end

local function generation_stopped(id, signature, nonce)
    local profile_stops = stop_tombstones[id]
    return profile_stops ~= nil
        and profile_stops[nonce] == signature
end

local function tombstone_generation(id, signature, nonce)
    stop_tombstones[id] = stop_tombstones[id] or {}
    stop_tombstones[id][nonce] = signature
end

local function valid_runtime_token(token)
    return token == nil or (type(token) == 'string'
        and #token >= 1 and #token <= 64
        and token:match('^[a-z0-9][a-z0-9_-]*$') ~= nil)
end

local function runtime_uint32(value)
    if type(value) == 'string' then
        if #value == 0 or #value > 10 or value:match('^%d+$') == nil then
            return nil
        end
        value = tonumber(value)
    elseif type(value) ~= 'number' then
        return nil
    end
    if value ~= value or value < 1 or value > 4294967295
        or value ~= math.floor(value)
    then
        return nil
    end
    return value
end

local function runtime_index(value)
    if type(value) == 'string' then
        if #value == 0 or #value > 5 or value:match('^%d+$') == nil then
            return nil
        end
        value = tonumber(value)
    elseif type(value) ~= 'number' then
        return nil
    end
    if value ~= value or value < 0 or value > 65535
        or value ~= math.floor(value)
    then
        return nil
    end
    return value
end

local function new_nonce(player)
    nonce_counter = nonce_counter + 1
    local clock_millis = math.floor((os.clock() % 1000) * 1000)
    local token = clock_millis * 1000 + nonce_counter % 1000
    return ('%d-%d-%d'):format(
        os.time(), player and player.id or 0, token)
end

local function send_ipc(fields)
    local encoded = {}
    for index, field in ipairs(fields) do
        encoded[index] = util.clean_field(field)
    end
    windower.send_ipc_message(table.concat(encoded, '|'))
end

local function find_member(values, wanted)
    for name, value in pairs(values or {}) do
        if util.same_name(name, wanted) then return value, name end
    end
    return nil
end

local UNIVERSAL_MANUAL_ACTIONS = {
    sleep={character='Barneystinson', adapter='brd-pack-sleep'},
}

local function manual_action_policy(profile, action)
    local fallback = UNIVERSAL_MANUAL_ACTIONS[action]
    if fallback then
        local member = profile
            and find_member(profile.members, fallback.character) or nil
        if member and member.main_job == 'BRD' then return fallback end
        return nil
    end
    return profile and profile.manual_actions
        and profile.manual_actions[action] or nil
end

local function expected_names(profile)
    return util.sorted_keys(profile and profile.members or {})
end

local function expected_names_token(profile)
    return table.concat(expected_names(profile), ',')
end

local function token_contains_name(token, wanted)
    return util.contains_name(util.split(token, ','), wanted)
end

local function local_readiness(profile, names_token)
    local errors = {}
    local player = windower.ffxi.get_player()
    if not player or not util.valid_name(player.name) then
        return false, 'no active local player', player
    end
    if names_token ~= expected_names_token(profile) then
        errors[#errors + 1] = 'profile roster token differs'
    end

    local party = util.party_name_set(windower.ffxi.get_party() or {})
    local expected = {}
    for _, name in ipairs(expected_names(profile)) do
        expected[name:lower()] = true
        if not party[name:lower()] then
            errors[#errors + 1] = name..' is absent'
        end
    end
    for name, _ in pairs(party) do
        if not expected[name] then errors[#errors + 1] = name..' is unexpected' end
    end
    if util.count(party) ~= util.count(expected) then
        errors[#errors + 1] = ('party has %d/%d required members')
            :format(util.count(party), util.count(expected))
    end

    local requirement = find_member(profile.members, player.name)
    if not requirement then
        errors[#errors + 1] = player.name..' has no profile assignment'
    elseif player.main_job ~= requirement.main_job then
        errors[#errors + 1] = ('%s is %s/%s; expected %s')
            :format(player.name, tostring(player.main_job),
                tostring(player.sub_job), requirement.main_job)
    elseif #(requirement.sub_jobs or {}) > 0
        and not util.contains_value(requirement.sub_jobs, player.sub_job)
    then
        errors[#errors + 1] = ('%s is %s/%s; required subjob is %s')
            :format(player.name, tostring(player.main_job),
                tostring(player.sub_job), table.concat(requirement.sub_jobs, '/'))
    end

    for action, policy in pairs(profile.manual_actions or {}) do
        if not manual_adapters[policy.adapter] then
            errors[#errors + 1] = ('manual action %s needs missing adapter %s')
                :format(action, policy.adapter)
        end
    end
    return #errors == 0, table.concat(errors, '; '), player
end

local function resolve_profile(value)
    if type(value) ~= 'string' then return nil end
    local normalized = value:lower()
    local id = aliases[normalized] or normalized
    return profiles[id] and id or nil
end

local function local_is_leader(profile)
    local player = windower.ffxi.get_player()
    return player and profile
        and util.same_name(player.name, profile.combat.leader)
end

local function local_is_profile_member(profile)
    local player = windower.ffxi.get_player()
    return player and profile
        and util.contains_name(expected_names(profile), player.name)
end

-- PartyTactics profiles include support members who deliberately have no
-- PartyCombat authority.  Raw `pc on` is valid only for the same role union
-- PartyCombat accepts: leader, puller, attackers, and targeters.  Keeping this
-- predicate here prevents profile-wide operator repair from turning a support
-- member into a noisy rejected controller request.
local function local_is_combat_participant(profile)
    local player = windower.ffxi.get_player()
    local combat = profile and profile.combat or nil
    local name = player and player.name or nil
    if not combat or not util.valid_name(name) then return false end
    return util.same_name(name, combat.leader)
        or util.same_name(name, combat.puller)
        or util.contains_name(combat.attackers or {}, name)
        or util.contains_name(combat.targeters or {}, name)
end

local function apply_legacy_combat_state_locally(profile, enabled)
    if not local_is_combat_participant(profile) then
        -- Fail closed and silently clear any authority left by a preceding
        -- profile.  A no-op would leave stale combat state possible when a
        -- policy command or IPC edge is lost.
        issue('pc reconcile off')
        return
    end
    issue(enabled and 'pc on' or 'pc off')
end

local function send_vote(session, ready, reason, player, kind)
    if not player or not util.valid_name(player.name) then return end
    -- Windower IPC is inter-process and does not promise delivery back to the
    -- sender. The initiating client must record its own validation vote before
    -- broadcasting it, while duplicate loopback delivery remains idempotent.
    if session.initiator and not session.decided
        and util.contains_name(session.names, player.name)
    then
        session.votes[player.name:lower()] = {
            ready=ready == true, main_job=player.main_job or 'NON',
            sub_job=player.sub_job or 'NON',
            reason=reason ~= '' and reason or '-',
        }
    end
    send_ipc{
        PREFIX, kind or 'vote', session.nonce, _addon.version,
        session.id, session.version, session.signature, player.name,
        ready and 'ready' or 'reject', player.main_job or 'NON',
        player.sub_job or 'NON', reason ~= '' and reason or '-',
    }
    if session.initiator then finalize_session(session, false) end
end

local function process_prepare(nonce, engine_version, id, version, signature,
    requester, names_token, preview, arm_after_apply, operator_revision,
    operator_bit, terminal_reapply)
    operator_revision = valid_operator_counter(
        tostring(operator_revision or ''), true)
    if not valid_nonce(nonce) or not util.valid_name(requester)
        or type(names_token) ~= 'string'
        or operator_revision == nil
        or (operator_bit ~= '0' and operator_bit ~= '1')
        or (arm_after_apply == true) ~= (operator_bit == '1')
        or (terminal_reapply ~= '0' and terminal_reapply ~= '1')
        or terminal_reapply == '1' and preview == true
    then return end
    local player = windower.ffxi.get_player()
    if not player or not util.valid_name(player.name)
        or not token_contains_name(names_token, player.name)
    then return end

    local profile, plan = profiles[id], plans[id]
    local adapter = profile and profile.gearswap_adapter or nil
    if terminal_reapply == '1' and (not adapter
        or adapter.lifecycle_authorization ~= true
        or tonumber(adapter.protocol) < 2)
    then return end
    -- Stop may arrive before the corresponding prepare. Preserve the exact
    -- tombstone so delayed prepare retries cannot recreate a cancelled load.
    if profile and plan and version == profile.version
        and signature == plan.signature
        and generation_stopped(id, signature, nonce)
    then
        return
    end
    local ready, reason = false, ''
    if engine_version ~= _addon.version then
        reason = 'PartyTactics version mismatch ('..tostring(engine_version)..')'
    elseif not profile or not plan then
        reason = 'profile is not installed'
    elseif version ~= profile.version or signature ~= plan.signature then
        reason = 'profile version/signature mismatch'
    elseif not util.contains_name(expected_names(profile), requester) then
        reason = 'requester is not a configured profile participant'
    else
        local matches, diagnostic = local_readiness(profile, names_token)
        -- Party/job/controller observations are useful setup diagnostics, not
        -- authority to withhold a profile from a named client. Version,
        -- signature, roster identity, and leader validation above remain the
        -- transport contract; everything fight-specific is best-effort.
        ready = true
        reason = matches and '' or ('setup warning: '..diagnostic)
    end

    local existing = sessions[nonce]
    if existing and (existing.id ~= id or existing.signature ~= signature
        or existing.terminal_reapply ~= (terminal_reapply == '1')) then
        ready, reason = false, 'nonce already belongs to another profile'
    else
        sessions[nonce] = existing or {
            nonce=nonce, id=id, version=version, signature=signature,
            requester=requester, names_token=names_token,
            names=util.split(names_token, ','), preview=preview == true,
            terminal_reapply=terminal_reapply == '1',
            arm_after_apply=arm_after_apply == true,
            operator_armed=operator_bit == '1',
            operator_revision=operator_revision,
            operator_sources={},
            votes={}, acks={}, created_at=os.clock(),
            apply_epoch=0,
        }
        sessions[nonce].local_ready = ready
        sessions[nonce].local_reason = reason
        local current_revision = tonumber(
            sessions[nonce].operator_revision) or 0
        if operator_revision > current_revision then
            sessions[nonce].operator_revision = operator_revision
            sessions[nonce].operator_armed = operator_bit == '1'
            sessions[nonce].arm_after_apply = operator_bit == '1'
        elseif operator_revision == current_revision
            and sessions[nonce].operator_armed ~= (operator_bit == '1')
        then
            sessions[nonce].local_ready = false
            sessions[nonce].local_reason =
                'conflicting operator state at the same revision'
        end
    end
    send_vote(sessions[nonce], sessions[nonce].local_ready,
        sessions[nonce].local_reason, player, 'vote')
end

local function announce_prepare(session)
    send_ipc{
        PREFIX, 'prepare', session.nonce, _addon.version, session.id,
        session.version, session.signature, session.requester,
        session.names_token, session.preview and '1' or '0',
        session.arm_after_apply and '1' or '0',
        tostring(session.operator_revision or 0),
        session.operator_armed and '1' or '0',
        session.terminal_reapply and '1' or '0',
    }
    session.next_prepare_at = os.clock() + PREPARE_RETRY_INTERVAL
end

local function begin(profile_name, preview, force_reapply, arm_after_apply,
    carried_operator_revision, terminal_reapply)
    local id = resolve_profile(profile_name)
    if not id then
        chat(123, 'Unknown or quarantined profile: '..tostring(profile_name))
        return
    end
    local profile, plan = profiles[id], plans[id]
    local player = windower.ffxi.get_player()
    if not player then chat(123, 'No active player.'); return end
    if not util.contains_name(expected_names(profile), player.name) then
        chat(123, 'Only a configured profile participant can load '..id..'.')
        return
    end
    if active and active.id == id and not preview and not force_reapply then
        if arm_after_apply == true then
            request_operator_state(true)
        else
            chat(207, id..' v'..profile.version..' is already active.')
        end
        return
    end

    for _, prior in pairs(sessions) do
        if prior.initiator and not prior.decided then
            prior.decided = 'superseded'
        end
    end

    local nonce = new_nonce(player)
    local initial_operator_revision = tonumber(carried_operator_revision) or 0
    if initial_operator_revision < 0
        or initial_operator_revision > 2147483647
        or initial_operator_revision ~= math.floor(initial_operator_revision)
    then
        initial_operator_revision = 0
    end
    local session = {
        nonce=nonce, id=id, version=profile.version,
        signature=plan.signature, requester=player.name,
        names_token=expected_names_token(profile),
        names=expected_names(profile), preview=preview == true,
        initiator=true, votes={}, acks={}, created_at=os.clock(),
        apply_epoch=0,
        deadline=os.clock() + PREPARE_TIMEOUT, next_prepare_at=0,
        arm_after_apply=arm_after_apply == true,
        -- Every fresh operator/auto selection of a lifecycle profile must
        -- fence any same-profile generation that a peer still owns. A full
        -- GearSwap/SK recovery carries a revision and its own bounded handoff
        -- instead, so that successor must not terminally fence its parent.
        terminal_reapply=not preview
            and (terminal_reapply == true
                or carried_operator_revision == nil)
            and profile.gearswap_adapter ~= nil
            and profile.gearswap_adapter.lifecycle_authorization == true
            and tonumber(profile.gearswap_adapter.protocol) >= 2,
        operator_armed=arm_after_apply == true,
        operator_revision=initial_operator_revision,
        operator_sources={},
    }
    sessions[nonce] = session
    selected_id = id
    announce_prepare(session)
    process_prepare(nonce, _addon.version, id, profile.version,
        plan.signature, player.name, session.names_token, preview == true,
        arm_after_apply == true, tostring(session.operator_revision),
        session.operator_armed and '1' or '0',
        session.terminal_reapply and '1' or '0')
    chat(207, ('%s %s v%s across available clients...')
        :format(preview and 'Previewing' or 'Loading', id, profile.version))
end

local function announce_abort(session, reason)
    send_ipc{
        PREFIX, 'abort', session.nonce, _addon.version, session.id,
        session.version, session.signature, session.requester,
        reason or 'validation-aborted',
    }
end

local function announce_commit(session)
    send_ipc{
        PREFIX, 'commit', session.nonce, _addon.version, session.id,
        session.version, session.signature, session.requester,
        session.names_token, tostring(session.apply_epoch or 0),
        session.arm_after_apply and '1' or '0',
        tostring(session.operator_revision or 0),
        session.operator_armed and '1' or '0',
        session.terminal_reapply and '1' or '0',
    }
    session.next_commit_at = os.clock() + COMMIT_RETRY_INTERVAL
end

local function show_profile(id, include_members)
    local profile, plan = profiles[id], plans[id]
    if not profile or not plan then return end
    chat(207, ('%s v%s | %s | %s | leader %s | puller %s')
        :format(id, profile.version, profile.label, profile.combat.movement,
            profile.combat.leader, profile.combat.puller))
    if include_members then
        for _, name in ipairs(util.sorted_keys(plan.members)) do
            chat(207, '  '..name..': '..plan.members[name].summary)
        end
    end
    for _, advisory in ipairs(profile.advisories or {}) do
        chat(123, advisory)
    end
end

local function vote_count(session)
    local count = 0
    for _, name in ipairs(session.names or {}) do
        if session.votes[name:lower()] then count = count + 1 end
    end
    return count
end

local function first_rejection(session)
    for _, name in ipairs(session.names or {}) do
        local vote = session.votes[name:lower()]
        if vote and not vote.ready then return name, vote.reason end
    end
    return nil
end

finalize_session = function(session, timed_out)
    if not session or session.decided or not session.initiator then return end
    if vote_count(session) < #session.names then
        if not timed_out then return end
    end

    local ready, unavailable, warnings = 0, {}, {}
    for _, name in ipairs(session.names) do
        local vote = session.votes[name:lower()]
        if vote and vote.ready then
            ready = ready + 1
            if vote.reason and vote.reason ~= '' and vote.reason ~= '-' then
                warnings[#warnings + 1] = name..' ('..vote.reason..')'
            end
        elseif vote then
            unavailable[#unavailable + 1] = name..' ('..vote.reason..')'
        else
            unavailable[#unavailable + 1] = name..' (no response)'
        end
    end

    if session.preview then
        session.decided = 'preview'
        announce_abort(session, 'preview-complete')
        show_profile(session.id, true)
        chat(158, ('Preview complete: %d/%d clients ready; no automation changed.')
            :format(ready, #session.names))
        if #unavailable > 0 then
            chat(123, 'Preview warnings: '..table.concat(unavailable, '; '))
        end
        if #warnings > 0 then
            chat(123, 'Setup observations: '..table.concat(warnings, '; '))
        end
        return
    end

    session.decided = 'commit'
    session.commit_retry_until = os.clock() + COMMIT_RETRY_WINDOW
    announce_commit(session)
    handle_commit(session.nonce, _addon.version, session.id, session.version,
        session.signature, session.requester, session.names_token,
        session.apply_epoch or 0, session.arm_after_apply == true,
        tostring(session.operator_revision or 0),
        session.operator_armed and '1' or '0',
        session.terminal_reapply and '1' or '0')
    chat(158, ('Loading %s on %d/%d ready clients (best-effort).')
        :format(session.id, ready, #session.names))
    if #unavailable > 0 then
        chat(123, 'Clients not loaded: '..table.concat(unavailable, '; ')
            ..'. Use //pt reapply after correcting them if desired.')
    end
    if #warnings > 0 then
        chat(123, 'Setup observations: '..table.concat(warnings, '; '))
    end
end

local function deactivate_runtime(record)
    if not record or record.runtime_deactivated then return end
    record.runtime_deactivated = true
    if not record.runtime
        or type(record.runtime.on_deactivate) ~= 'function'
    then return end
    local ok, runtime_error = pcall(
        record.runtime.on_deactivate, record.runtime, record.context)
    if not ok then chat(123, 'Runtime deactivate warning: '..tostring(runtime_error)) end
end

local function issue_commands(commands)
    for _, command in ipairs(commands or {}) do issue(command) end
end

handle_commit = function(nonce, engine_version, id, version, signature,
    requester, names_token, apply_epoch, arm_after_apply, operator_revision,
    operator_bit, terminal_reapply)
    if not valid_nonce(nonce) or retired_generations[nonce]
        or generation_stopped(id, signature, nonce)
        or engine_version ~= _addon.version
    then return end
    apply_epoch = tonumber(apply_epoch) or 0
    operator_revision = valid_operator_counter(
        tostring(operator_revision or ''), true)
    local profile, plan = profiles[id], plans[id]
    local session = sessions[nonce]
    if not profile or not plan or version ~= profile.version
        or signature ~= plan.signature
        or not util.contains_name(expected_names(profile), requester)
        or names_token ~= expected_names_token(profile)
        or not session or not session.local_ready
        or session.id ~= id or session.signature ~= signature
        or apply_epoch ~= (tonumber(session.apply_epoch) or 0)
        or operator_revision == nil
        or (operator_bit ~= '0' and operator_bit ~= '1')
        or (arm_after_apply == true) ~= (operator_bit == '1')
        or (terminal_reapply ~= '0' and terminal_reapply ~= '1')
        or session.terminal_reapply ~= (terminal_reapply == '1')
    then return end
    local session_revision = tonumber(session.operator_revision) or 0
    if operator_revision == session_revision
        and session.operator_armed ~= (operator_bit == '1')
    then
        return
    elseif operator_revision > session_revision then
        session.operator_revision = operator_revision
        session.operator_armed = operator_bit == '1'
        session.arm_after_apply = operator_bit == '1'
    end
    if active and active.nonce == nonce
        or pending_commit and pending_commit.nonce == nonce
    then
        -- Commit retries are also ordered-state carriers. A peer may have
        -- missed the leader's operator-state broadcast while this generation
        -- was pending; merge the session's monotonic tuple before returning.
        process_operator_state(nonce, engine_version, id, version, signature,
            apply_epoch, profile.combat.leader,
            tostring(session.operator_revision or 0),
            session.operator_armed and '1' or '0')
        return
    end
    if applied_generations[nonce] then return end

    if active then
        if active.id ~= id or session.terminal_reapply then
            local old_profile = profiles[active.id]
            local fence_source = old_profile
                and util.contains_name(expected_names(old_profile), requester)
                and requester
                or old_profile and old_profile.combat.leader or nil
            fence_required_controller_stop(
                old_profile, active.nonce, fence_source)
        end
        deactivate_runtime(active)
        issue_commands(compiler.teardown(
            active.job, active.owns_autows2, false, true))
        retired_generations[active.nonce] = true
    end
    active = nil
    pending_reapply = nil
    reraise_guard = {enabled=false, next_check=0, warned=false}

    -- PartyTactics is the only orchestrator. PartyStart-authored GearSwap
    -- compatibility helpers are ordinary includes, not a reason to load the
    -- retired PartyStart addon process. PartyCombat is an explicit process
    -- dependency loaded before PartyTactics by init and the safe reload
    -- scripts, so a profile commit must not issue a noisy blind load request.
    issue('pc invalidate partytactics')
    pending_commit = {
        nonce=nonce, id=id, version=version, signature=signature,
        requester=requester, names_token=names_token,
        apply_epoch=apply_epoch,
        -- The locally validated session is authoritative. Operator changes
        -- received during prepare update it before commit; later changes
        -- update this pending record directly.
        arm_after_apply=session.arm_after_apply == true,
        operator_armed=session.operator_armed == true,
        operator_revision=tonumber(session.operator_revision) or 0,
        operator_sources=session.operator_sources or {},
        apply_at=os.clock() + TRANSITION_DELAY,
    }
end

local function send_ack(record)
    local player = windower.ffxi.get_player()
    if not record or not player or not util.valid_name(player.name) then return end
    -- As with prepare votes, count the local application synchronously. Peer
    -- acknowledgements still arrive through IPC and duplicate delivery is safe.
    record.acks = record.acks or {}
    local epoch = tonumber(record.apply_epoch) or 0
    -- An application ACK now proves that the stable EOF GearSwap host
    -- actually executed for this generation/epoch. A source file existing on
    -- disk is insufficient if a character job file omitted its include.
    if record.host_ready_revision ~= GEARSWAP_HOST_REVISION
        or tonumber(record.host_ready_epoch) ~= epoch
    then return end
    if LEGACY_HELPER_PREFIX[record.job]
        and (record.legacy_ready_revision ~= LEGACY_GEARSWAP_VERSION
            or record.legacy_ready_job ~= record.job
            or tonumber(record.legacy_ready_epoch) ~= epoch)
    then return end
    record.acks[player.name:lower()] = epoch
    send_ipc{
        PREFIX, 'ack', record.nonce, _addon.version, record.id,
        record.version, record.signature, player.name,
        tostring(epoch),
    }
end

local function request_gearswap_host_probe(record)
    if not record or not valid_nonce(record.nonce) then return false end
    local epoch = tonumber(record.apply_epoch) or 0
    issue(('gs c ptgs probe %s %.0f'):format(record.nonce, epoch))
    return true
end

local function request_legacy_helper_probe(record)
    local prefix = record and LEGACY_HELPER_PREFIX[record.job] or nil
    if not prefix or not valid_nonce(record.nonce) then return false end
    local epoch = tonumber(record.apply_epoch) or 0
    issue(('gs c %s probe %s %.0f %s'):format(
        prefix, record.nonce, epoch, LEGACY_GEARSWAP_VERSION))
    return true
end

local function process_gearswap_host_ready(revision, generation, epoch)
    epoch = tonumber(epoch)
    if not active or revision ~= GEARSWAP_HOST_REVISION
        or generation ~= active.nonce or not epoch
        or epoch < 0 or epoch ~= math.floor(epoch)
        or epoch ~= (tonumber(active.apply_epoch) or 0)
    then return end
    active.host_ready_revision = revision
    active.host_ready_epoch = epoch
    send_ack(active)
end

local function process_legacy_helper_ready(revision, job, generation, epoch)
    epoch = tonumber(epoch)
    if not active or revision ~= LEGACY_GEARSWAP_VERSION
        or generation ~= active.nonce or job ~= active.job
        or not LEGACY_HELPER_PREFIX[job] or not epoch
        or epoch < 0 or epoch ~= math.floor(epoch)
        or epoch ~= (tonumber(active.apply_epoch) or 0)
    then return end
    active.legacy_ready_revision = revision
    active.legacy_ready_job = job
    active.legacy_ready_epoch = epoch
    send_ack(active)
end

local function alert(profile, message, audible)
    message = util.clean_field(message)
    chat(167, '********************************************************')
    chat(167, '*** '..message..' ***')
    chat(167, '********************************************************')
    if audible and local_is_leader(profile) then
        pcall(windower.play_sound, 'C:\\Windows\\Media\\Alarm03.wav')
    end
end

local function create_context(profile)
    local context = {}
    context.actions, context.client = action_api.create(issue, function()
        return active and active.nonce,
            active and tonumber(active.apply_epoch) or nil
    end)
    context.now = os.clock
    context.monster_ability = function(id)
        return res.monster_abilities[tonumber(id)]
    end
    context.job_ability = function(id)
        return res.job_abilities[tonumber(id)]
    end
    context.spell = function(id)
        return res.spells[tonumber(id)]
    end
    context.weapon_skill = function(id)
        return res.weapon_skills[tonumber(id)]
    end
    context.mob_by_id = function(id)
        return windower.ffxi.get_mob_by_id(tonumber(id))
    end
    context.mob_array = function() return windower.ffxi.get_mob_array() or {} end
    context.current_target = function()
        return windower.ffxi.get_mob_by_target('t')
    end
    context.recent_target = function(max_age)
        local record = recent_hostile_target
        local info = windower.ffxi.get_info()
        local zone = info and tonumber(info.zone) or nil
        local limit = tonumber(max_age) or 15
        if not record or os.clock() - record.at > limit
            or zone ~= record.zone
        then return nil end
        local mob = windower.ffxi.get_mob_by_id(record.id)
        if not mob or tonumber(mob.index) ~= record.index
            or mob.name ~= record.name or tonumber(mob.spawn_type) ~= 16
            or mob.valid_target ~= true or (tonumber(mob.hpp) or 0) <= 0
        then return nil end
        return mob
    end
    context.zone_id = function()
        local info = windower.ffxi.get_info()
        return info and tonumber(info.zone) or nil
    end
    context.player_job = function()
        local player = windower.ffxi.get_player()
        return player and player.main_job or nil
    end
    context.player_name = function()
        local player = windower.ffxi.get_player()
        return player and player.name or nil
    end
    context.party_tp = function(name)
        if type(name) ~= 'string' then return nil end
        local wanted = name:lower()
        local party = windower.ffxi.get_party() or {}
        for index = 0, 5 do
            local member = party['p'..tostring(index)]
            if member and type(member.name) == 'string'
                and member.name:lower() == wanted
            then
                local tp = tonumber(member.tp)
                return tp and math.max(0, math.floor(tp)) or nil
            end
        end
        return nil
    end
    context.party_hpp_floor = function()
        local floor, seen = 100, 0
        local party = windower.ffxi.get_party() or {}
        for index = 0, 5 do
            local member = party['p'..tostring(index)]
            if member and type(member.hpp) == 'number' then
                seen = seen + 1
                floor = math.min(floor, member.hpp)
            end
        end
        -- This orchestrator owns a fixed six-character party. Missing vitals
        -- are not evidence that the remaining visible members are healthy.
        return seen == 6 and floor or nil
    end
    context.has_buff = function(name)
        if type(name) ~= 'string' then return false end
        local buff = res.buffs:with('en', name)
        local player = windower.ffxi.get_player()
        if not buff or not player then return false end
        for _, id in ipairs(player.buffs or {}) do
            if id == buff.id then return true end
        end
        return false
    end
    context.has_buff_id = function(wanted)
        wanted = tonumber(wanted)
        local player = windower.ffxi.get_player()
        if not wanted or wanted < 1 or wanted % 1 ~= 0 or not player then
            return false
        end
        for _, id in ipairs(player.buffs or {}) do
            if tonumber(id) == wanted then return true end
        end
        return false
    end
    context.party_claimed = function(mob)
        if type(mob) ~= 'table' then return false end
        local claim_id = tonumber(mob.claim_id)
        if not claim_id or claim_id < 1 or claim_id > 4294967295
            or claim_id ~= math.floor(claim_id)
        then
            return false
        end
        local player = windower.ffxi.get_player()
        if player and tonumber(player.id) == claim_id then return true end
        local party = windower.ffxi.get_party() or {}
        for index = 0, 5 do
            local member = party['p'..tostring(index)]
            local id = member and member.mob and tonumber(member.mob.id)
            if id and id == claim_id then return true end
        end
        return false
    end
    context.combat_ready = function()
        -- Readiness checks are diagnostic only. A loaded runtime may make a
        -- best-effort attempt immediately; missing clients or setup are
        -- reported to the operator but never turn into a combat lock.
        return active ~= nil and not pending_reapply
    end
    context.operator_armed = function()
        return active ~= nil and active.operator_armed == true
            and not pending_reapply
    end
    context.authorize_encounter = function(target_id)
        target_id = tonumber(target_id)
        if not target_id or target_id < 1 or target_id > 4294967295
            or target_id ~= math.floor(target_id)
            or not local_is_leader(profile)
        then
            return false
        end
        if active.encounter_authority_id
            and active.encounter_authority_id ~= target_id
        then
            return false
        end
        active.encounter_authority_id = target_id
        active.adapter_status_seen = {}
        -- Peers accept runtime-controller IPC only after this exact encounter
        -- authority has reached them through the signed generation state.
        announce_state()
        return true
    end
    context.encounter_ready = function(target_id)
        target_id = tonumber(target_id)
        return active and target_id
            and active.encounter_authority_id == target_id
    end
    context.release_encounter = function(target_id, keep_armed)
        target_id = tonumber(target_id)
        if not active or active.encounter_authority_id ~= target_id
            or not local_is_leader(profile)
        then
            return false
        end
        active.encounter_authority_id = nil
        active.adapter_status_seen = nil
        -- Clearing the target retires only target-specific queued work. It
        -- does not schedule another readiness audit or make combat contingent
        -- on a new proof.
        local keep = keep_armed == true and active.operator_armed == true
        if active.operator_armed ~= keep then
            -- Runtime callbacks execute independently on every client. Only
            -- the leader may serialize a changed operator intent; peers learn
            -- the resulting revision from operator-state/periodic state.
            request_operator_state(keep)
        end
        active.preflight_epoch = nil
        active.preflight_checked_at = nil
        active.auto_preflight_at = nil
        announce_state()
        return true
    end
    local function adapter_allows(controller, action)
        local adapter = profile.gearswap_adapter
        if type(adapter) ~= 'table' or adapter.controller ~= controller then
            return false
        end
        for _, allowed in ipairs(adapter.actions or {}) do
            if allowed == action then return true end
        end
        return false
    end
    context.actions.party_adapter = function(
        character, action, target_id, request_token, subject_id)
        local player = windower.ffxi.get_player()
        local adapter = profile.gearswap_adapter
        local controller = adapter and adapter.controller or nil
        local requirement = profile.preflight
            and find_member(profile.preflight.members, character) or nil
        requirement = type(requirement) == 'table'
            and requirement.controller or nil
        target_id = runtime_uint32(target_id)
        local has_subject = subject_id ~= nil
        subject_id = has_subject and runtime_uint32(subject_id) or nil
        if not active or not player or not local_is_leader(profile)
            or not util.valid_name(character)
            or not util.contains_name(active.names, character)
            or type(requirement) ~= 'table'
            or requirement.name ~= controller
            or not adapter_allows(controller, action)
            or not valid_runtime_token(request_token)
            or not target_id
            or (has_subject and not subject_id)
            or active.encounter_authority_id ~= target_id
        then
            return false, 'invalid runtime controller request'
        end
        local fields = {
            PREFIX, 'runtime-controller', active.nonce, _addon.version,
            active.id, active.version, active.signature,
            tostring(active.apply_epoch or 0), player.name, character,
            controller, action, ('%.0f'):format(target_id),
        }
        if has_subject then
            fields[#fields + 1] = request_token or '-'
            fields[#fields + 1] = ('%.0f'):format(subject_id)
        elseif request_token ~= nil then
            fields[#fields + 1] = request_token
        end
        send_ipc(fields)
        process_runtime_controller(active.nonce, _addon.version, active.id,
            active.version, active.signature, active.apply_epoch,
            player.name, character, controller, action, target_id,
            request_token, subject_id)
        return true
    end
    context.alert = function(message, audible)
        alert(profile, message, audible == true)
    end
    return context
end

local function create_runtime(profile)
    local context = create_context(profile)
    if not profile.runtime then return nil, context end
    local ok, runtime = pcall(profile.runtime.create)
    if not ok or type(runtime) ~= 'table' then
        return nil, context, ok and 'runtime create returned no object'
            or tostring(runtime)
    end
    return runtime, context
end

local function member_plan(plan, player_name)
    return find_member(plan.members, player_name)
end

local function controller_requirement(profile, player_name)
    local policy = profile and profile.preflight
        and find_member(profile.preflight.members, player_name) or nil
    return type(policy) == 'table' and policy.controller or nil
end

process_runtime_controller = function(generation, engine_version, id,
    version, signature, epoch, source, recipient, controller, action,
    target_id, request_token, subject_id)
    local profile = active and profiles[active.id] or nil
    local player = windower.ffxi.get_player()
    local requirement = profile
        and controller_requirement(profile, recipient) or nil
    local adapter = profile and profile.gearswap_adapter or nil
    local action_allowed = false
    for _, allowed in ipairs(adapter and adapter.actions or {}) do
        if allowed == action then action_allowed = true; break end
    end
    epoch = tonumber(epoch)
    target_id = runtime_uint32(target_id)
    local has_subject = subject_id ~= nil
    subject_id = has_subject and runtime_uint32(subject_id) or nil
    if request_token == '-' and has_subject then request_token = nil end
    if not active or not profile or not player
        or generation ~= active.nonce or engine_version ~= _addon.version
        or id ~= active.id or version ~= active.version
        or signature ~= active.signature
        or epoch ~= tonumber(active.apply_epoch)
        or not util.same_name(source, profile.combat.leader)
        or not util.valid_name(recipient)
        or not util.contains_name(active.names, recipient)
        or type(requirement) ~= 'table'
        or requirement.name ~= controller
        or not adapter or adapter.controller ~= controller
        or not action_allowed
        or not valid_runtime_token(request_token)
        or not target_id
        or (has_subject and not subject_id)
        or active.encounter_authority_id ~= target_id
    then
        return false
    end
    if not util.same_name(player.name, recipient) then return true end
    local ok = active.context.actions.profile_adapter(
        controller, action, target_id, request_token, subject_id)
    return ok == true
end

local authorize_required_controller

local function probe_required_controller(profile, player, delay)
    local requirement = player
        and controller_requirement(profile, player.name) or nil
    if not requirement then return true end
    local adapter = profile.gearswap_adapter
    if not adapter or adapter.controller ~= requirement.name
        or tonumber(adapter.protocol) ~= tonumber(requirement.protocol)
    then
        chat(123, 'Controller probe skipped: profile adapter does not match '
            ..'the declared controller. Manual controls remain available.')
        return false
    end
    -- Adapter activation and setup commands are queued in the same frame.
    -- A short deterministic initial delay lets GearSwap install the adapter.
    -- Protocol-2 lifecycle profiles retry the exact idempotent probe below if
    -- that first local command or its callback is lost during startup.
    delay = tonumber(delay)
    if delay == nil then delay = 1 end
    local command = ('gs c ptgs action %s probe %s %.0f %.0f'):format(
        requirement.name, active.nonce,
        tonumber(active.apply_epoch) or 0, requirement.protocol)
    if delay > 0 then
        command = ('wait %g; %s'):format(delay, command)
    end
    issue(command)
    local lifecycle = adapter.lifecycle_authorization == true
        and tonumber(adapter.protocol) >= 2
    if lifecycle and active and not active.controller_ready then
        active.controller_probe_attempts =
            (active.controller_probe_attempts or 0) + 1
        active.next_controller_probe_at = os.clock() + delay
            + ((active.controller_probe_attempts
                    >= CONTROLLER_PROBE_WARN_AFTER)
                and CONTROLLER_PROBE_SLOW_RETRY_INTERVAL
                or CONTROLLER_PROBE_RETRY_INTERVAL)
    end
    return true
end

local function repair_required_controller(now)
    if not active or pending_reapply or active.controller_ready
        or not active.next_controller_probe_at
        or now < active.next_controller_probe_at
    then
        return false
    end
    local profile = profiles[active.id]
    local adapter = profile and profile.gearswap_adapter or nil
    local player = windower.ffxi.get_player()
    if not adapter or adapter.lifecycle_authorization ~= true
        or tonumber(adapter.protocol) < 2
    then
        active.next_controller_probe_at = nil
        return false
    end
    if (active.controller_probe_attempts or 0)
        >= CONTROLLER_PROBE_WARN_AFTER
        and not active.controller_probe_warned
    then
        active.controller_probe_warned = true
        chat(123, ('Controller proof is still missing after %d attempts; '
            ..'automatic lanes remain off. Low-rate retries continue. '
            ..'If this generation was retired, stop the profile and load '
            ..'it afresh.'):format(CONTROLLER_PROBE_WARN_AFTER))
    end
    -- Reassert the exact pinned adapter before refreshing authorization and
    -- probing. Host activation is idempotent for the same id/version, while
    -- this extra edge repairs a first command lost during GearSwap startup.
    issue(('gs c ptgs activate %s %s'):format(adapter.id, adapter.version))
    authorize_required_controller(profile, active)
    return probe_required_controller(profile, player, 0)
end

authorize_required_controller = function(profile, record)
    local adapter = profile and profile.gearswap_adapter or nil
    if type(adapter) ~= 'table'
        or adapter.lifecycle_authorization ~= true
        or not record
    then
        return true
    end
    -- This is emitted only after a distributed commit has passed the exact
    -- profile/version/signature/roster barrier. The adapter activation command
    -- is earlier in the same local compiler plan; the ordinary capability
    -- probe is delayed one second, leaving deterministic room for this pinned
    -- lifecycle authorization and its standalone-companion relay.
    local command = ('gs c ptgs action %s authorize %s %d %d %s %s %s %s %s')
        :format(adapter.controller, record.nonce,
            tonumber(record.apply_epoch) or 0,
            tonumber(adapter.protocol) or 0,
            profile.id, profile.version, record.signature,
            profile.combat.leader, record.names_token)
    if tonumber(adapter.protocol) >= 2 then
        command = command..(' %d %s'):format(
            tonumber(record.operator_revision) or 0,
            record.operator_armed and '1' or '0')
    end
    issue(command)
    return true
end

fence_required_controller_stop = function(profile, generation, source)
    local adapter = profile and profile.gearswap_adapter or nil
    local plan = profile and plans[profile.id] or nil
    if type(adapter) ~= 'table'
        or adapter.lifecycle_authorization ~= true
        or not valid_nonce(generation) or not util.valid_name(source)
        or not util.contains_name(expected_names(profile), source)
        or not plan
    then
        return false
    end
    local player = windower.ffxi.get_player()
    local local_name = player and player.name or nil
    for member, command in pairs(adapter.lifecycle_stop_fences or {}) do
        if member == '*' or util.same_name(member, local_name) then
            issue(('%s %s %s %s %s %s %s'):format(
                command, generation, _addon.version, profile.id,
                profile.version, plan.signature, source))
        end
    end
    -- Also route the fence through a live adapter so its in-memory
    -- authorization is retired before a queued probe. The direct declarative
    -- commands above are the authority path during a GearSwap host gap; this
    -- adapter message is defense in depth and may harmlessly be unavailable.
    issue(('gs c ptgs action %s retire %s %s %s %s %s %s'):format(
        adapter.controller, generation, _addon.version, profile.id,
        profile.version, plan.signature, source))
    return true
end

local function invoke_runtime(method, ...)
    local record = active
    if not record or not record.runtime
        or type(record.runtime[method]) ~= 'function'
        or record.runtime_failed
        or (record.runtime_failed_methods
            and record.runtime_failed_methods[method])
    then return true end
    local perf_wall, perf_cpu
    if party_tactics_perf and party_tactics_perf.enabled then
        perf_wall, perf_cpu = party_tactics_perf:begin_sample()
    end
    local ok, runtime_error = pcall(record.runtime[method], record.runtime,
        record.context, ...)
    if perf_wall then
        party_tactics_perf:finish_sample('runtime_'..method, perf_wall, perf_cpu)
    end
    if not ok then
        -- A fight callback is one best-effort automation lane, not permission
        -- for the party to act. Quarantine only this callback method so, for
        -- example, an on_action error cannot stop on_tick or on_status.
        record.runtime_failed_methods = record.runtime_failed_methods or {}
        record.runtime_failed_methods[method] = true
        chat(167, 'Profile callback paused locally after '..method..': '
            ..tostring(runtime_error)..'. Other profile callbacks, manual controls, '
            ..'and other clients continue; use //pt reapply to retry this callback.')
        return false
    end
    return true
end

local function adapter_action_allowed(profile, controller, action)
    local adapter = profile and profile.gearswap_adapter or nil
    if type(adapter) ~= 'table' or adapter.controller ~= controller
        or type(action) ~= 'string'
    then
        return false
    end
    for _, allowed in ipairs(adapter.actions or {}) do
        if allowed == action then return true end
    end
    return false
end

local function exact_active_party_member(record, entity_id, entity_index)
    entity_id = runtime_uint32(entity_id)
    entity_index = runtime_index(entity_index)
    if not record or not entity_id or entity_index == nil then return nil end
    local mob = windower.ffxi.get_mob_by_id(entity_id)
    if type(mob) ~= 'table' or tonumber(mob.id) ~= entity_id
        or tonumber(mob.index) ~= entity_index
        or not util.valid_name(mob.name)
        or not util.contains_name(record.names, mob.name)
    then
        return nil
    end
    local party = windower.ffxi.get_party() or {}
    for index = 0, 5 do
        local member = party['p'..tostring(index)]
        local member_id = type(member) == 'table' and (
            member.mob and tonumber(member.mob.id)
                or tonumber(member.mob_id) or tonumber(member.id)) or nil
        if member_id == entity_id and util.same_name(member.name, mob.name) then
            return mob
        end
    end
    return nil
end

process_adapter_status = function(generation, engine_version, id, version,
    signature, epoch, source_name, source_id, source_index, controller,
    action, encounter_id, encounter_index, subject_id, subject_index,
    request_token)
    local profile = active and profiles[active.id] or nil
    epoch = tonumber(epoch)
    source_id = runtime_uint32(source_id)
    source_index = runtime_index(source_index)
    encounter_id = runtime_uint32(encounter_id)
    encounter_index = runtime_index(encounter_index)
    subject_id = runtime_uint32(subject_id)
    subject_index = runtime_index(subject_index)
    local requirement = profile
        and controller_requirement(profile, source_name) or nil
    local encounter = encounter_id
        and windower.ffxi.get_mob_by_id(encounter_id) or nil
    if not active or not profile or generation ~= active.nonce
        or engine_version ~= _addon.version or id ~= active.id
        or version ~= active.version or signature ~= active.signature
        or epoch ~= tonumber(active.apply_epoch)
        or type(requirement) ~= 'table'
        or requirement.name ~= controller
        or not adapter_action_allowed(profile, controller, action)
        or not valid_runtime_token(request_token) or request_token == nil
        or not encounter_id or encounter_index == nil
        or not encounter or tonumber(encounter.index) ~= encounter_index
        or active.encounter_authority_id ~= encounter_id
        or not source_id or source_index == nil
        or not subject_id or subject_index == nil
    then
        return false
    end
    local source = exact_active_party_member(active, source_id, source_index)
    local subject = exact_active_party_member(active, subject_id, subject_index)
    if not source or not subject or not util.same_name(source.name, source_name)
    then
        return false
    end
    local local_player = windower.ffxi.get_player()
    if not local_player or not local_is_leader(profile) then return true end

    active.adapter_status_seen = active.adapter_status_seen or {}
    local proof_key = table.concat({
        source.name, action, tostring(encounter_id), tostring(encounter_index),
        tostring(subject_id), tostring(subject_index), request_token,
    }, ':')
    if active.adapter_status_seen[proof_key] then return true end
    active.adapter_status_seen[proof_key] = true
    return invoke_runtime('on_status', {
        source=source.name, source_id=source_id, source_index=source_index,
        controller=controller, semantic=action,
        encounter_id=encounter_id, encounter_index=encounter_index,
        subject=subject.name, subject_id=subject_id,
        subject_index=subject_index, token=request_token,
    })
end

local function process_local_adapter_status(controller, generation, epoch,
    action, encounter_id, encounter_index, subject_id, subject_index,
    request_token)
    local profile = active and profiles[active.id] or nil
    local player = windower.ffxi.get_player()
    local source_id = player and runtime_uint32(player.id) or nil
    local source_mob = source_id
        and windower.ffxi.get_mob_by_id(source_id) or nil
    local source_index = source_mob and runtime_index(source_mob.index) or nil
    local requirement = profile and player
        and controller_requirement(profile, player.name) or nil
    epoch = tonumber(epoch)
    encounter_id = runtime_uint32(encounter_id)
    encounter_index = runtime_index(encounter_index)
    subject_id = runtime_uint32(subject_id)
    subject_index = runtime_index(subject_index)
    if not active or not profile or not player or not source_mob
        or generation ~= active.nonce or epoch ~= tonumber(active.apply_epoch)
        or type(requirement) ~= 'table' or requirement.name ~= controller
        or not adapter_action_allowed(profile, controller, action)
        or not valid_runtime_token(request_token) or request_token == nil
        or active.encounter_authority_id ~= encounter_id
        or not encounter_id or encounter_index == nil
        or not subject_id or subject_index == nil
        or not exact_active_party_member(active, subject_id, subject_index)
    then
        return false
    end
    local encounter = windower.ffxi.get_mob_by_id(encounter_id)
    if not encounter or tonumber(encounter.index) ~= encounter_index then
        return false
    end
    local fields = {
        PREFIX, 'adapter-status', generation, _addon.version,
        active.id, active.version, active.signature, tostring(epoch),
        player.name, ('%.0f'):format(source_id), tostring(source_index),
        controller, action, ('%.0f'):format(encounter_id),
        tostring(encounter_index), ('%.0f'):format(subject_id),
        tostring(subject_index), request_token,
    }
    send_ipc(fields)
    return process_adapter_status(generation, _addon.version, active.id,
        active.version, active.signature, epoch, player.name, source_id,
        source_index, controller, action, encounter_id, encounter_index,
        subject_id, subject_index, request_token)
end

local function apply_pending_commit()
    local pending = pending_commit
    if not pending or os.clock() < pending.apply_at then return end
    if retired_generations[pending.nonce]
        or generation_stopped(
            pending.id, pending.signature, pending.nonce)
    then
        pending_commit = nil
        return
    end
    local profile, plan = profiles[pending.id], plans[pending.id]
    if not profile or not plan then
        chat(167, 'Selected profile disappeared before local apply. '
            ..'Other clients continue.')
        pending_commit = nil
        return
    end
    local ready, reason, player = local_readiness(profile, pending.names_token)
    if not player then
        chat(167, 'Profile could not load locally: no active player. Other clients continue.')
        pending_commit = nil
        return
    end
    local local_plan = member_plan(plan, player.name)
    if not local_plan then
        chat(167, 'Profile could not load locally: no assignment for '
            ..tostring(player.name)..'. Other clients continue.')
        pending_commit = nil
        return
    end
    local runtime, context, runtime_error = create_runtime(profile)
    if runtime_error then
        chat(167, 'Profile runtime could not start locally: '..runtime_error
            ..'. Manual controls and other clients continue.')
        pending_commit = nil
        return
    end

    if not ready and reason ~= '' then
        chat(123, 'Profile setup warning: '..reason..'. Loading best-effort.')
    end

    local session = sessions[pending.nonce]
    local arm_after_apply = pending.operator_armed == true
    issue_commands(local_plan.commands)
    authorize_required_controller(profile, pending)
    active = {
        nonce=pending.nonce, id=pending.id, version=pending.version,
        signature=pending.signature, requester=pending.requester,
        names_token=pending.names_token,
        names=expected_names(profile), job=player.main_job,
        apply_epoch=pending.apply_epoch or 0,
        owns_autows2=local_plan.owns_autows2, runtime=runtime,
        context=context, runtime_deactivated=false,
        runtime_failed=false, runtime_failed_methods={},
        acks=(sessions[pending.nonce]
            and sessions[pending.nonce].acks or {}),
        ack_deadline=os.clock() + APPLY_ACK_TIMEOUT,
        host_ready_revision=nil, host_ready_epoch=nil,
        legacy_ready_revision=nil, legacy_ready_job=nil,
        legacy_ready_epoch=nil,
        next_controller_probe_at=nil,
        controller_probe_attempts=0,
        controller_probe_warned=false,
        preflight_epoch=nil,
        encounter_authority_id=nil,
        -- New automatic runtimes may require explicit post-positioning
        -- consent. Older runtimes do not consult this latch, preserving their
        -- established behavior.
        operator_armed=arm_after_apply == true,
        operator_revision=tonumber(pending.operator_revision) or 0,
        operator_sources=pending.operator_sources or {},
        -- Checks are explicitly requested diagnostics. Never create a
        -- background retry loop that can flood chat during a live fight.
        auto_preflight_at=nil,
    }
    pending_commit = nil
    applied_generations[active.nonce] = true
    selected_id = active.id
    next_state_sync = 0
    next_maintenance = 0
    reraise_guard = {
        enabled=profile.safety and profile.safety.reraise == true or false,
        next_check=os.clock() + 6, warned=false,
    }
    if runtime and type(runtime.on_activate) == 'function' then
        invoke_runtime('on_activate')
    end
    request_gearswap_host_probe(active)
    request_legacy_helper_probe(active)
    probe_required_controller(profile, player)
    send_ack(active)
    if active.operator_armed then
        local adapter = profile.gearswap_adapter
        -- A lifecycle-authorized adapter may still be one second behind the
        -- compiler plan during a full GearSwap recovery. Preserve the desired
        -- operator bit in distributed state, but do not make combat effective
        -- until this local client proves that exact controller generation.
        if not adapter or adapter.lifecycle_authorization ~= true then
            apply_legacy_combat_state_locally(profile, true)
        end
        announce_state()
    end
    chat(158, ('%s v%s ready as %s/%s; PartyCombat is %s.')
        :format(active.id, active.version, player.main_job,
            tostring(player.sub_job),
            active.operator_armed and 'armed' or 'unarmed'))
    if local_is_leader(profile) then
        for _, advisory in ipairs(profile.advisories or {}) do chat(123, advisory) end
    end
end

local function apply_terminal_reassert(now)
    local terminal = terminal_reassert
    if not terminal or now < terminal.due then return end
    -- Any applied replacement owns its own complete compiler plan. Never let
    -- an older terminal retry cross that lifecycle boundary. A pending commit
    -- is allowed a short bounded window to resolve; if it applies, the active
    -- check cancels this retry, and if it disappears the old OFF baseline is
    -- made durable on the next frame.
    if active then
        terminal_reassert = nil
        return
    end
    if pending_commit then
        if now < terminal.expires then
            terminal.due = now + 0.25
        else
            terminal_reassert = nil
            issue_commands(compiler.teardown(
                terminal.job, terminal.owns_autows2, true))
        end
        return
    end
    terminal_reassert = nil
    issue_commands(compiler.teardown(
        terminal.job, terminal.owns_autows2, true))
end

stop_local = function(reason, nonce, local_only, lifecycle_fenced)
    local active_match = active
        and (nonce == nil or active.nonce == nonce) and active or nil
    local pending_match = pending_commit
        and (nonce == nil or pending_commit.nonce == nonce)
        and pending_commit or nil
    if not active_match and not pending_match then return false end
    if lifecycle_fenced ~= true then
        local fenced = {}
        for _, record in ipairs{active_match, pending_match} do
            if record and not fenced[record.nonce] then
                local profile = profiles[record.id]
                local player = windower.ffxi.get_player()
                local source = player and player.name or nil
                if not profile
                    or not util.contains_name(expected_names(profile), source)
                then
                    source = profile and profile.combat.leader or nil
                end
                fence_required_controller_stop(profile, record.nonce, source)
                fenced[record.nonce] = true
            end
        end
    end
    if active_match then deactivate_runtime(active_match) end
    local player = windower.ffxi.get_player()
    local job = active_match and active_match.job
        or player and player.main_job or nil
    local owns_autows2 = active_match and active_match.owns_autows2 or true
    if active_match then
        retired_generations[active_match.nonce] = true
        active = nil
        pending_reapply = nil
    end
    if pending_match then
        retired_generations[pending_match.nonce] = true
        pending_commit = nil
    end
    -- Cancelling only a future commit must not tear down an unrelated active
    -- generation. With no surviving active state, apply the complete inert
    -- baseline just as the previous single-record stop path did.
    if active_match or not active then
        reraise_guard = {enabled=false, next_check=0, warned=false}
        issue_commands(compiler.teardown(job, owns_autows2, local_only == true))
    end
    if active_match then
        -- Compiler offense commands contain a one-second weapon-mode wait. If
        -- the operator stops during that window, its delayed AutoWS2 ON can
        -- otherwise overtake the immediate teardown. This retry is core-owned
        -- and exact-lifecycle scoped; any newer active/pending application
        -- cancels or defers it, so it cannot turn off another profile.
        terminal_reassert = {
            generation=active_match.nonce,
            job=job,
            owns_autows2=owns_autows2,
            due=os.clock() + 2,
            expires=os.clock() + 6,
        }
    end
    if reason then chat(207, 'Stopped: '..util.clean_field(reason)) end
    return true
end

local function parse_stop_targets(value, fallback)
    if value == nil or value == '' then
        return valid_nonce(fallback) and {fallback} or nil
    end
    if type(value) ~= 'string' or #value > 2048 then return nil end
    local result, seen = {}, {}
    for _, nonce in ipairs(util.split(value, ',')) do
        if not valid_nonce(nonce) or seen[nonce] or #result >= 32 then
            return nil
        end
        seen[nonce] = true
        result[#result + 1] = nonce
    end
    return #result > 0 and result or nil
end

local function process_stop(request_nonce, engine_version, id, version,
    signature, source, reason, targets_token)
    if not valid_nonce(request_nonce) or stop_seen[request_nonce]
        or engine_version ~= _addon.version
    then
        return false
    end
    local profile, plan = profiles[id], plans[id]
    if not profile or not plan or version ~= profile.version
        or signature ~= plan.signature or not util.valid_name(source)
        or not util.contains_name(expected_names(profile), source)
    then
        return false
    end
    local targets = parse_stop_targets(targets_token, request_nonce)
    if not targets then return false end

    stop_seen[request_nonce] = true
    local target_set = {}
    for _, nonce in ipairs(targets) do
        target_set[nonce] = true
        fence_required_controller_stop(profile, nonce, source)
        tombstone_generation(id, signature, nonce)
        local session = sessions[nonce]
        if session and session.id == id and session.signature == signature then
            session.decided = 'stopped'
            retired_generations[nonce] = true
        end
    end

    local pending_match = pending_commit and pending_commit.id == id
        and pending_commit.version == version
        and pending_commit.signature == signature
        and target_set[pending_commit.nonce] and pending_commit or nil
    local active_match = active and active.id == id
        and active.version == version and active.signature == signature
        and target_set[active.nonce] and active or nil
    if pending_match then
        stop_local(active_match and nil or reason or 'leader requested stop',
            pending_match.nonce, nil, true)
    end
    if active_match then
        stop_local(reason or 'leader requested stop', active_match.nonce,
            nil, true)
    end
    return true
end

local function request_stop(reason)
    local player = windower.ffxi.get_player()
    local targets_by_profile = {}
    local function remember(record)
        if not record or retired_generations[record.nonce]
            or generation_stopped(record.id, record.signature, record.nonce)
        then
            return
        end
        local bucket = targets_by_profile[record.id] or {
            version=record.version, signature=record.signature, nonces={}, seen={},
        }
        if bucket.version ~= record.version
            or bucket.signature ~= record.signature
        then
            return
        end
        if not bucket.seen[record.nonce] then
            bucket.seen[record.nonce] = true
            bucket.nonces[#bucket.nonces + 1] = record.nonce
        end
        targets_by_profile[record.id] = bucket
    end
    remember(active)
    remember(pending_commit)
    for _, session in pairs(sessions) do
        if session.decided == nil or session.decided == 'commit' then
            remember(session)
        end
    end
    local ids = util.sorted_keys(targets_by_profile)
    if #ids == 0 then
        chat(207, 'PartyTactics is already off.')
        return
    end
    if not player or not util.valid_name(player.name) then
        chat(123, 'Only a configured profile participant can stop this profile.')
        return
    end
    for _, id in ipairs(ids) do
        local profile = profiles[id]
        if not profile
            or not util.contains_name(expected_names(profile), player.name)
        then
            chat(123, 'Only a configured profile participant can stop this profile.')
            return
        end
    end
    -- Retire both the old active generation and every undecided replacement
    -- or reapply generation. Each exact target gets its own bounded IPC field;
    -- batching several nonces into one clean_field would risk truncating the
    -- terminal fence. Peers retain each tombstone even if stop is delivered
    -- before that generation's prepare or commit.
    for _, id in ipairs(ids) do
        local bucket = targets_by_profile[id]
        table.sort(bucket.nonces)
        for _, target_nonce in ipairs(bucket.nonces) do
            local request_nonce = new_nonce(player)
            send_ipc{
                PREFIX, 'stop', request_nonce, _addon.version, id,
                bucket.version, bucket.signature, player.name,
                reason or 'leader requested stop', target_nonce,
            }
            process_stop(request_nonce, _addon.version, id, bucket.version,
                bucket.signature, player.name,
                reason or 'leader requested stop', target_nonce)
        end
    end
end

-- GearSwap's stable host retires an adapter immediately after delivering its
-- raw logout callback, so an adapter-owned prerender timer cannot survive to
-- defeat older queued compiler commands. This private callback is instead
-- scoped to the exact still-active PartyTactics lifecycle. A profile switch or
-- reapply changes the generation/epoch/controller tuple and makes the delayed
-- callback a no-op; it can never tear down the replacement profile.
local function process_controller_terminal(controller, generation, epoch,
    protocol)
    local profile = active and profiles[active.id] or nil
    local adapter = profile and profile.gearswap_adapter or nil
    epoch, protocol = tonumber(epoch), tonumber(protocol)
    if not active or not adapter or not valid_nonce(generation)
        or generation ~= active.nonce
        or epoch ~= tonumber(active.apply_epoch)
        or controller ~= adapter.controller
        or protocol ~= tonumber(adapter.protocol)
    then
        return false
    end
    return stop_local('local controller terminal lifecycle ended',
        generation, true)
end

local function process_recover_controller(controller, generation, epoch,
    protocol, id, version, engine_version, signature, leader, names_token,
    recovered_revision, recovered_bit)
    local profile = active and profiles[active.id] or nil
    local adapter = profile and profile.gearswap_adapter or nil
    epoch, protocol = tonumber(epoch), tonumber(protocol)
    local revision = valid_operator_counter(
        tostring(recovered_revision or ''), true)
    if not active or not profile or not adapter
        or adapter.lifecycle_authorization ~= true
        or generation ~= active.nonce
        or epoch ~= tonumber(active.apply_epoch)
        or controller ~= adapter.controller
        or protocol ~= tonumber(adapter.protocol)
        or id ~= active.id or version ~= active.version
        or engine_version ~= _addon.version
        or signature ~= active.signature
        or leader ~= profile.combat.leader
        or names_token ~= active.names_token
        or (protocol >= 2 and (revision == nil
            or (recovered_bit ~= '0' and recovered_bit ~= '1')
            or revision > (tonumber(active.operator_revision) or 0)
            or revision == (tonumber(active.operator_revision) or 0)
                and (recovered_bit == '1') ~= active.operator_armed))
        or pending_commit or pending_reapply
    then
        return false
    end
    -- A delayed keeper request may not overtake a newer explicit load/reapply
    -- intent that this client has already observed, even before commit.
    for nonce, session in pairs(sessions) do
        if nonce ~= active.nonce and not applied_generations[nonce]
            and not retired_generations[nonce]
            and (session.decided == nil or session.decided == 'commit')
        then
            return false
        end
    end
    begin(active.id, false, true, active.operator_armed == true,
        tonumber(active.operator_revision) or 0)
    return true
end

local function find_operator_record(generation)
    if active and active.nonce == generation then return active end
    if pending_commit and pending_commit.nonce == generation then
        return pending_commit
    end
    local session = sessions[generation]
    if session and not retired_generations[generation]
        and not generation_stopped(session.id, session.signature, generation)
        and (session.decided == nil or session.decided == 'commit')
    then
        return session
    end
    return nil
end

set_operator_snapshot = function(record, revision, desired)
    record.operator_revision = revision
    record.operator_armed = desired == true
    -- Keep this legacy field mirrored until all generic compiler/session code
    -- has migrated. It is data only; protocol-2 ordering uses the revision.
    record.arm_after_apply = desired == true
end

local function carry_operator_snapshot(record, revision, desired)
    set_operator_snapshot(record, revision, desired)
    if record == pending_commit then
        local pending_session = sessions[record.nonce]
        if pending_session then
            set_operator_snapshot(pending_session, revision, desired)
        end
    end
    if record ~= active then return end

    -- Same-generation reapply and recovery sessions must carry the newest
    -- leader-authored tuple, rather than the bit captured by their first
    -- prepare packet.
    local active_session = sessions[active.nonce]
    if active_session then
        set_operator_snapshot(active_session, revision, desired)
    end
    for nonce, session in pairs(sessions) do
        if nonce ~= active.nonce and session.id == active.id
            and session.signature == active.signature
            and not retired_generations[nonce]
            and (session.decided == nil or session.decided == 'commit')
        then
            set_operator_snapshot(session, revision, desired)
        end
    end
    if pending_commit and pending_commit.id == active.id
        and pending_commit.signature == active.signature
    then
        set_operator_snapshot(pending_commit, revision, desired)
        local pending_session = sessions[pending_commit.nonce]
        if pending_session then
            set_operator_snapshot(pending_session, revision, desired)
        end
    end
end

local function route_operator_to_adapter(record, profile)
    local adapter = profile and profile.gearswap_adapter or nil
    local ready = record == active and active.controller_ready or nil
    if not adapter or adapter.lifecycle_authorization ~= true
        or tonumber(adapter.protocol) < 2 or not ready
        or ready.generation ~= record.nonce
        or ready.epoch ~= tonumber(record.apply_epoch)
        or ready.protocol ~= tonumber(adapter.protocol)
    then
        return false
    end
    issue(('gs c ptgs action %s operator %s %d %d %d %s'):format(
        adapter.controller, record.nonce, tonumber(record.apply_epoch) or 0,
        tonumber(adapter.protocol), tonumber(record.operator_revision) or 0,
        record.operator_armed and '1' or '0'))
    return true
end

-- Protocol-2 profiles continuously reconcile an ordered operator tuple. Their
-- heartbeat and lifecycle repairs use PartyCombat's silent local surface;
-- only an operator's explicit Alt-P/disarm edge uses the visible distributed
-- stop. Legacy profiles retain their established command behavior.
local function issue_profile_combat_off(profile, visible)
    local adapter = profile and profile.gearswap_adapter or nil
    local silent = not visible and adapter
        and adapter.lifecycle_authorization == true
        and tonumber(adapter.protocol) >= 2
    issue(silent and 'pc reconcile off' or 'pc off')
end

apply_operator_locally = function(record, profile)
    if record ~= active or not local_is_profile_member(profile) then return end
    if pending_reapply then
        -- A reapply invalidates effective combat immediately but preserves the
        -- ordered desired bit as data. OFF remains fail-safe; ON is replayed
        -- only after the replacement controller proves this exact epoch.
        if not record.operator_armed then
            issue_profile_combat_off(profile, false)
        end
        return
    end
    local adapter = profile.gearswap_adapter
    if adapter and adapter.lifecycle_authorization == true
        and tonumber(adapter.protocol) >= 2
    then
        -- OFF is a core-owned emergency action and is never delayed by an
        -- adapter/companion outage. ON is only routed after this client proves
        -- the current controller; the adapter may continue to hold it while a
        -- Signet transaction is suspended.
        if not record.operator_armed then
            issue_profile_combat_off(profile, false)
        end
        route_operator_to_adapter(record, profile)
    else
        apply_legacy_combat_state_locally(
            profile, record.operator_armed == true)
    end
end

-- Accept one leader-authored total order. Lower revisions are stale; an equal
-- revision with the same bit is an idempotent retry, while an equal revision
-- with a different bit is invalid. This makes periodic state, commit retries,
-- and delayed IPC converge without letting an old ON defeat a newer OFF.
process_operator_state = function(generation, engine_version, id, version,
    signature, apply_epoch, leader, revision_value, bit)
    local record = find_operator_record(generation)
    local profile = record and profiles[record.id] or nil
    local revision = valid_operator_counter(tostring(revision_value or ''), true)
    apply_epoch = valid_epoch_token(tostring(apply_epoch or ''))
    if not record or not profile or not revision or apply_epoch == nil
        or engine_version ~= _addon.version or id ~= record.id
        or version ~= record.version or signature ~= record.signature
        or apply_epoch ~= (tonumber(record.apply_epoch) or 0)
        or not util.same_name(leader, profile.combat.leader)
        or (bit ~= '0' and bit ~= '1')
    then
        return false
    end
    local desired = bit == '1'
    local current_revision = tonumber(record.operator_revision) or 0
    if revision < current_revision then return false end
    if revision == current_revision then
        if record.operator_armed ~= desired then return false end
        -- Periodic state is also a repair channel. Reconcile the local side
        -- effect without allocating a new transition when an earlier command
        -- was dropped or a companion restarted.
        if record == active then apply_operator_locally(record, profile) end
        return true
    end

    carry_operator_snapshot(record, revision, desired)
    if record == active then
        apply_operator_locally(active, profile)
    end
    return true
end

local function announce_operator_state(record)
    local profile = record and profiles[record.id] or nil
    if not profile or not local_is_leader(profile) then return false end
    local fields = {
        PREFIX, 'operator-state', record.nonce, _addon.version, record.id,
        record.version, record.signature,
        tostring(record.apply_epoch or 0), profile.combat.leader,
        tostring(record.operator_revision or 0),
        record.operator_armed and '1' or '0',
    }
    send_ipc(fields)
    -- Windower does not promise IPC loopback. The leader applies its own
    -- serialized decision synchronously.
    local accepted = process_operator_state(record.nonce, _addon.version, record.id,
        record.version, record.signature, record.apply_epoch or 0,
        profile.combat.leader, tostring(record.operator_revision or 0),
        record.operator_armed and '1' or '0')
    return accepted
end

process_operator_request = function(generation, engine_version, id, version,
    signature, apply_epoch, source, source_sequence_value, bit)
    local record = find_operator_record(generation)
    local profile = record and profiles[record.id] or nil
    local names = record and (record.names or expected_names(profile)) or nil
    local source_sequence = valid_operator_counter(
        tostring(source_sequence_value or ''), false)
    apply_epoch = valid_epoch_token(tostring(apply_epoch or ''))
    if not record or not profile or not source_sequence or apply_epoch == nil
        or engine_version ~= _addon.version or id ~= record.id
        or version ~= record.version or signature ~= record.signature
        or apply_epoch ~= (tonumber(record.apply_epoch) or 0)
        or not util.valid_name(source) or not util.contains_name(names, source)
        or (bit ~= '0' and bit ~= '1')
    then
        return false
    end
    -- Only the exact profile leader serializes requests. Other clients accept
    -- the transport as addressed to the leader but never invent revisions.
    if not local_is_leader(profile) then return true end
    record.operator_sources = record.operator_sources or {}
    local source_key = source:lower()
    local prior = record.operator_sources[source_key]
    if prior and source_sequence < prior.sequence then return false end
    if prior and source_sequence == prior.sequence then
        if prior.bit ~= bit then return false end
        return announce_operator_state(record)
    end
    local revision = tonumber(record.operator_revision) or 0
    if revision >= 2147483647 then return false end
    record.operator_sources[source_key] = {
        sequence=source_sequence, bit=bit,
    }
    carry_operator_snapshot(record, revision + 1, bit == '1')
    return announce_operator_state(record)
end

request_operator_state = function(enabled)
    local record = active or pending_commit
    if not record then
        chat(123, 'No active profile.')
        return false
    end
    local player = windower.ffxi.get_player()
    local profile = profiles[record.id]
    local names = record.names or expected_names(profile)
    if not player or not util.valid_name(player.name)
        or not util.contains_name(names, player.name)
    then
        chat(123, 'Only a named member of the active profile can change combat.')
        return false
    end
    if operator_source_sequence >= 2147483647 then
        chat(123, 'Operator command sequence exhausted; reload PartyTactics.')
        return false
    end
    operator_source_sequence = operator_source_sequence + 1
    local bit = enabled and '1' or '0'
    -- Alt-P is fail-safe locally even before the leader broadcast returns.
    -- This is the one visible distributed OFF edge; revision replay on every
    -- named client is silent and local through apply_operator_locally.
    local adapter = profile and profile.gearswap_adapter or nil
    local protocol_two = adapter
        and adapter.lifecycle_authorization == true
        and tonumber(adapter.protocol) >= 2
    if not enabled and (not local_is_leader(profile) or protocol_two) then
        issue_profile_combat_off(profile, true)
    end
    local fields = {
        PREFIX, 'operator-request', record.nonce, _addon.version, record.id,
        record.version, record.signature, tostring(record.apply_epoch or 0),
        player.name, tostring(operator_source_sequence), bit,
    }
    send_ipc(fields)
    process_operator_request(record.nonce, _addon.version, record.id,
        record.version, record.signature, record.apply_epoch or 0,
        player.name, tostring(operator_source_sequence), bit)
    chat(158, enabled
        and 'Profile ON requested by '..player.name..'.'
        or 'PartyCombat disarmed by '..player.name
        ..' immediately; ordered OFF submitted while support remains active.')
    return true
end

local function process_manual(nonce, id, version, signature, action, source)
    if not valid_nonce(nonce) or manual_seen[nonce] or not active
        or active.id ~= id or active.version ~= version
        or active.signature ~= signature
    then return end
    local profile = profiles[id]
    local policy = manual_action_policy(profile, action)
    if not profile or not policy
        or not util.contains_name(expected_names(profile), source)
    then return end
    manual_seen[nonce] = true
    local player = windower.ffxi.get_player()
    if not player or not util.same_name(player.name, policy.character) then return end
    local adapter = manual_adapters[policy.adapter]
    local accepted, adapter_error = false, 'adapter unavailable'
    if not adapter then
        chat(167, 'Manual adapter unavailable: '..policy.adapter)
    else
        local ok, result, result_error = pcall(
            adapter.execute, active.context, policy)
        accepted = ok and result ~= false
        adapter_error = accepted and '-' or tostring(ok and result_error or result)
        if not accepted then
            chat(167, ('Manual action %s failed: %s')
                :format(action, adapter_error))
        end
    end
    send_ipc{
        PREFIX, 'manual-result', nonce, _addon.version, id, version,
        signature, action, player.name,
        accepted and 'accepted' or 'rejected', adapter_error,
    }
end

local function process_manual_result(nonce, id, version, signature, action,
    source, outcome, detail)
    if not valid_nonce(nonce) or manual_result_seen[nonce] or not active
        or active.id ~= id or active.version ~= version
        or active.signature ~= signature
    then return end
    local profile = profiles[id]
    local policy = manual_action_policy(profile, action)
    if not profile or not policy or not local_is_profile_member(profile)
        or not util.same_name(source, policy.character)
    then return end
    manual_result_seen[nonce] = true
    if outcome == 'accepted' then
        chat(158, ('%s accepted by %s through %s.')
            :format(action, source, policy.adapter))
    else
        chat(167, ('%s rejected by %s: %s')
            :format(action, source, util.clean_field(detail or 'unspecified')))
    end
end

local function request_manual(action)
    if not active then chat(123, 'No active profile.'); return end
    local profile = profiles[active.id]
    local policy = manual_action_policy(profile, action)
    if not policy then
        chat(123, active.id..' has no manual action '..tostring(action)..'.')
        return
    end
    if action == 'sleep' and (policy.character ~= 'Barneystinson'
        or policy.adapter ~= 'brd-pack-sleep'
        or not manual_adapters['brd-pack-sleep'])
    then
        chat(123, 'Emergency sleep blocked: Barney BRD controller adapter '
            ..'is unavailable.')
        return
    end
    if not local_is_profile_member(profile) then
        chat(123, 'Only a configured profile participant can request actions.')
        return
    end
    local player = windower.ffxi.get_player()
    local nonce = new_nonce(player)
    chat(158, ('Requested %s from %s through %s.')
        :format(action, policy.character, policy.adapter))
    send_ipc{
        PREFIX, 'manual', nonce, _addon.version, active.id,
        active.version, active.signature, action, player.name,
    }
    process_manual(nonce, active.id, active.version, active.signature,
        action, player.name)
end

local function preflight_bucket(values)
    if type(values) ~= 'table' or #values == 0 then return '-' end
    return util.clean_field(table.concat(values, '; '))
end

local function process_controller_ready(controller, generation, epoch,
    protocol)
    local profile = active and profiles[active.id] or nil
    local player = windower.ffxi.get_player()
    local requirement = profile and player
        and controller_requirement(profile, player.name) or nil
    epoch, protocol = tonumber(epoch), tonumber(protocol)
    if not active or not profile or not player or not requirement
        or pending_reapply
        or generation ~= active.nonce
        or epoch ~= tonumber(active.apply_epoch)
        or controller ~= requirement.name
        or protocol ~= tonumber(requirement.protocol)
        or player.main_job ~= active.job
    then return false end
    local first_ready = active.controller_ready == nil
    active.controller_ready = {
        name=controller, generation=generation, epoch=epoch,
        protocol=protocol, job=player.main_job, at=os.clock(),
    }
    active.next_controller_probe_at = nil
    active.controller_probe_attempts = 0
    active.controller_probe_warned = false
    local adapter = profile.gearswap_adapter
    if adapter and adapter.lifecycle_authorization == true
        and local_is_profile_member(profile)
    then
        if tonumber(adapter.protocol) >= 2 then
            -- Re-deliver the latest authoritative revision after every fresh
            -- controller proof. The adapter high-water makes retries harmless
            -- and keeps an ON intent inert if Signet is still suspended.
            route_operator_to_adapter(active, profile)
        elseif first_ready and active.operator_armed then
            apply_legacy_combat_state_locally(profile, true)
        end
        if first_ready and local_is_leader(profile) then announce_state() end
    end
    return true
end

local function process_controller_lost(controller, generation, epoch,
    protocol)
    local profile = active and profiles[active.id] or nil
    local player = windower.ffxi.get_player()
    local requirement = profile and player
        and controller_requirement(profile, player.name) or nil
    local capability = active and active.controller_ready or nil
    epoch, protocol = tonumber(epoch), tonumber(protocol)
    if not active or not requirement or not capability
        or generation ~= active.nonce or generation ~= capability.generation
        or epoch ~= tonumber(active.apply_epoch) or epoch ~= capability.epoch
        or controller ~= requirement.name or controller ~= capability.name
        or protocol ~= tonumber(requirement.protocol)
        or protocol ~= capability.protocol
    then return false end
    active.controller_ready = nil
    active.next_controller_probe_at = os.clock()
    active.controller_probe_attempts = 0
    active.controller_probe_warned = false
    active.preflight_epoch = nil
    active.preflight_checked_at = nil
    local adapter = profile and profile.gearswap_adapter or nil
    if adapter and tonumber(adapter.protocol) >= 2 then
        -- Desired ON remains data, but an unavailable protocol-2 controller
        -- may never leave PartyCombat effective.
        issue_profile_combat_off(profile, false)
    end
    chat(123, controller..' GearSwap adapter stopped responding; '
        ..'profile support and all manual controls remain available.')
    return true
end

local function preflight_result_count(check)
    local count = 0
    for _, name in ipairs(check and check.names or {}) do
        if check.results[name:lower()] then count = count + 1 end
    end
    return count
end

local function finalize_preflight(check, timed_out)
    if not check or check.done or not active
        or active.nonce ~= check.generation
        or tonumber(active.apply_epoch) ~= check.epoch
    then return end
    local received = preflight_result_count(check)
    if received < #check.names and not timed_out then return end
    check.done = true
    active.preflight_epoch = nil
    active.preflight_checked_at = nil

    if received < #check.names then
        local missing = {}
        for _, name in ipairs(check.names) do
            if not check.results[name:lower()] then missing[#missing + 1] = name end
        end
        chat(123, ('CHECK INCOMPLETE %d/%d: no result from %s. Continuing best-effort.')
            :format(received, #check.names, table.concat(missing, ', ')))
        announce_state()
        return
    end

    local passed = 0
    for _, name in ipairs(check.names) do
        local result = check.results[name:lower()]
        if result and result.passed then passed = passed + 1 end
    end
    if passed == #check.names then
        active.preflight_epoch = check.epoch
        active.preflight_checked_at = os.clock()
        chat(158, ('CHECK PASS %d/%d for epoch %d.')
            :format(passed, #check.names, check.epoch))
    else
        chat(123, ('CHECK WARN %d/%d for epoch %d. Continuing best-effort.')
            :format(passed, #check.names, check.epoch))
    end
    for _, name in ipairs(check.names) do
        local result = check.results[name:lower()]
        if not result.passed then
            chat(167, name..': '..result.errors)
        elseif result.warnings ~= '-' then
            chat(123, name..' WARN: '..result.warnings)
        else
            chat(207, name..': '..result.details)
        end
    end
    -- Republish diagnostic state so status is consistent on every client.
    announce_state()
end

local function process_preflight_result(request_nonce, engine_version,
    generation, id, version, signature, epoch, name, outcome, errors,
    warnings, details)
    local check = preflight_checks[request_nonce]
    local profile = active and profiles[active.id] or nil
    epoch = tonumber(epoch)
    if not check or check.done or not active or not profile
        or engine_version ~= _addon.version
        or generation ~= active.nonce or generation ~= check.generation
        or id ~= active.id or id ~= check.id
        or version ~= active.version or version ~= check.version
        or signature ~= active.signature or signature ~= check.signature
        or epoch ~= tonumber(active.apply_epoch) or epoch ~= check.epoch
        or not local_is_leader(profile) or not util.valid_name(name)
        or not util.contains_name(check.names, name)
        or outcome ~= 'pass' and outcome ~= 'fail'
    then return end
    check.results[name:lower()] = {
        passed=outcome == 'pass',
        errors=errors or '-', warnings=warnings or '-', details=details or '-',
    }
    finalize_preflight(check, false)
end

local function process_preflight_request(request_nonce, engine_version,
    generation, id, version, signature, epoch, leader)
    local profile = active and profiles[active.id] or nil
    local player = windower.ffxi.get_player()
    epoch = tonumber(epoch)
    if not valid_nonce(request_nonce) or not active or not profile
        or not profile.preflight or engine_version ~= _addon.version
        or generation ~= active.nonce or id ~= active.id
        or version ~= active.version or signature ~= active.signature
        or epoch ~= tonumber(active.apply_epoch)
        or not util.same_name(leader, profile.combat.leader)
        or not player or not util.contains_name(active.names, player.name)
    then return end

    local ok, result = pcall(preflight.evaluate, profile.preflight,
        player.name, windower.ffxi, res)
    if not ok or type(result) ~= 'table' then
        result = {
            passed=false,
            errors={'preflight evaluator failed: '..tostring(result)},
            warnings={}, details={},
        }
    end
    local requirement = controller_requirement(profile, player.name)
    if requirement then
        local capability = active.controller_ready
        local valid = capability
            and capability.name == requirement.name
            and capability.generation == active.nonce
            and capability.epoch == tonumber(active.apply_epoch)
            and capability.protocol == tonumber(requirement.protocol)
            and capability.job == player.main_job
        if not valid then
            result.passed = false
            result.errors = result.errors or {}
            result.errors[#result.errors + 1] = ('controller %s protocol %s '
                ..'did not answer the current-generation GearSwap probe')
                :format(tostring(requirement.name),
                    tostring(requirement.protocol))
        else
            result.details = result.details or {}
            result.details[#result.details + 1] = ('controller %s protocol %s '
                ..'loaded for epoch %d'):format(requirement.name,
                    tostring(requirement.protocol), capability.epoch)
        end
    end
    local outcome = result.passed and 'pass' or 'fail'
    local errors = preflight_bucket(result.errors)
    local warnings = preflight_bucket(result.warnings)
    local details = preflight_bucket(result.details)
    send_ipc{
        PREFIX, 'preflight-result', request_nonce, _addon.version,
        generation, id, version, signature, tostring(epoch), player.name,
        outcome, errors, warnings, details,
    }
    process_preflight_result(request_nonce, _addon.version, generation, id,
        version, signature, epoch, player.name, outcome, errors, warnings,
        details)
end

local function announce_preflight(check)
    send_ipc{
        PREFIX, 'preflight-request', check.nonce, _addon.version,
        check.generation, check.id, check.version, check.signature,
        tostring(check.epoch), check.leader,
    }
    check.next_request_at = os.clock() + PREFLIGHT_RETRY_INTERVAL
end

begin_preflight = function(automatic)
    if not active then
        if not automatic then chat(123, 'Preflight blocked: no active profile.') end
        return false
    end
    local profile = profiles[active.id]
    if not profile or not profile.preflight then
        if not automatic then
            chat(207, active.id..' has no profile-owned preflight requirements.')
        end
        return false
    end
    if not local_is_leader(profile) then
        if not automatic then
            chat(123, 'Run preflight from '..profile.combat.leader..'.')
        end
        return false
    end
    if active.encounter_authority_id then
        if not automatic then
            chat(123, 'Preflight waits until the active encounter ends.')
        end
        return false
    end
    for _, check in pairs(preflight_checks) do
        if not check.done and check.generation == active.nonce
            and check.epoch == tonumber(active.apply_epoch)
        then
            if not automatic then chat(207, 'Preflight is already running.') end
            return false
        end
    end
    local player = windower.ffxi.get_player()
    local request_nonce = new_nonce(player)
    local check = {
        nonce=request_nonce, generation=active.nonce, id=active.id,
        version=active.version, signature=active.signature,
        epoch=tonumber(active.apply_epoch) or 0,
        leader=profile.combat.leader, names=active.names,
        results={}, deadline=os.clock() + PREFLIGHT_TIMEOUT,
        next_request_at=0, done=false,
    }
    active.preflight_epoch = nil
    active.preflight_checked_at = nil
    -- A fresh check replaces the previously displayed diagnostic result. It
    -- has no effect on armed state, runtime callbacks, or manual controls.
    announce_state()
    preflight_checks[request_nonce] = check
    announce_preflight(check)
    process_preflight_request(request_nonce, _addon.version, active.nonce,
        active.id, active.version, active.signature, check.epoch,
        profile.combat.leader)
    chat(207, ('Running read-only preflight across all %d clients%s...')
        :format(#check.names, automatic and ' automatically' or ''))
    return true
end

announce_state = function()
    if not active then return end
    local profile = profiles[active.id]
    if not profile or not local_is_leader(profile) then return end
    local preflight_age = '-'
    if active.preflight_epoch and active.preflight_checked_at then
        preflight_age = ('%.3f'):format(math.max(
            0, os.clock() - active.preflight_checked_at))
    end
    send_ipc{
        PREFIX, 'state', active.nonce, _addon.version, active.id,
        active.version, active.signature, profile.combat.leader,
        active.names_token, tostring(active.apply_epoch or 0),
        active.preflight_epoch and tostring(active.preflight_epoch) or '-',
        preflight_age,
        active.encounter_authority_id
            and ('%.0f'):format(active.encounter_authority_id) or '-',
        tostring(active.operator_revision or 0),
        active.operator_armed and '1' or '0',
    }
    -- Windower does not guarantee IPC loopback. Protocol-2 state repair is
    -- silent, so converge the leader locally as well as every remote member;
    -- legacy profiles retain their prior edge-only leader behavior.
    local adapter = profile.gearswap_adapter
    if adapter and adapter.lifecycle_authorization == true
        and tonumber(adapter.protocol) >= 2
    then
        process_operator_state(active.nonce, _addon.version, active.id,
            active.version, active.signature, active.apply_epoch or 0,
            profile.combat.leader, tostring(active.operator_revision or 0),
            active.operator_armed and '1' or '0')
    end
end

local function process_state(nonce, engine_version, id, version, signature,
    leader, names_token, apply_epoch, preflight_epoch, preflight_age,
    encounter_authority, operator_revision, operator_armed)
    if not valid_nonce(nonce) or retired_generations[nonce]
        or generation_stopped(id, signature, nonce)
        or engine_version ~= _addon.version
    then return end
    apply_epoch = valid_epoch_token(apply_epoch)
    if apply_epoch == nil then return end
    local state_operator_revision = valid_operator_counter(
        tostring(operator_revision or ''), true)
    if state_operator_revision == nil
        or (operator_armed ~= '0' and operator_armed ~= '1')
    then return end
    local profile, plan = profiles[id], plans[id]
    if not profile or not plan or version ~= profile.version
        or signature ~= plan.signature
        or not util.same_name(leader, profile.combat.leader)
        or names_token ~= expected_names_token(profile)
    then return end
    if active and active.nonce == nonce then
        local local_epoch = tonumber(active.apply_epoch) or 0
        if apply_epoch > local_epoch then
            -- The epoch transition and operator order are independent. Merge
            -- the leader's monotonic tuple before invalidating this epoch so
            -- the replacement authorization cannot resurrect a stale ON.
            local local_revision = tonumber(active.operator_revision) or 0
            local desired = operator_armed == '1'
            if state_operator_revision < local_revision
                or state_operator_revision == local_revision
                    and active.operator_armed ~= desired
            then
                return
            end
            if state_operator_revision > local_revision then
                carry_operator_snapshot(
                    active, state_operator_revision, desired)
            end
            schedule_reapply(0, apply_epoch)
            return
        elseif apply_epoch < local_epoch then
            return
        end
        if pending_reapply then
            -- A same-epoch periodic packet may repair a dropped OFF or update
            -- desired intent while the runtime is unavailable. The local
            -- application helper guarantees ON remains inert until ready.
            process_operator_state(nonce, engine_version, id, version,
                signature, apply_epoch, leader, operator_revision,
                operator_armed)
            return
        end
        local synced_preflight = tonumber(preflight_epoch)
        local synced_age = tonumber(preflight_age)
        local max_age = profile.preflight
            and tonumber(profile.preflight.max_age_seconds) or nil
        local fresh = synced_preflight == local_epoch
            and synced_age and synced_age >= 0
            and (not max_age or synced_age < max_age)
        active.preflight_epoch = fresh and synced_preflight or nil
        active.preflight_checked_at = fresh
            and (os.clock() - synced_age) or nil
        local synced_encounter = tonumber(encounter_authority)
        active.encounter_authority_id = synced_encounter
            and synced_encounter >= 1
            and synced_encounter <= 4294967295
            and synced_encounter == math.floor(synced_encounter)
            and synced_encounter or nil
        process_operator_state(nonce, engine_version, id, version, signature,
            apply_epoch, leader, operator_revision, operator_armed)
        send_ack(active)
        return
    end
    local matches, reason, player = local_readiness(profile, names_token)
    if not player or not token_contains_name(names_token, player.name) then return end
    local session = sessions[nonce]
    local desired = operator_armed == '1'
    if session then
        if session.id ~= id or session.version ~= version
            or session.signature ~= signature
            or session.names_token ~= names_token
        then
            return
        end
        local session_epoch = tonumber(session.apply_epoch) or 0
        local session_revision = tonumber(session.operator_revision) or 0
        local session_bit = session.operator_armed == true
        if pending_commit and pending_commit.nonce == nonce then
            local pending_epoch_value = tonumber(pending_commit.apply_epoch) or 0
            local pending_revision = tonumber(
                pending_commit.operator_revision) or 0
            if pending_epoch_value > session_epoch then
                session_epoch = pending_epoch_value
            end
            if pending_revision > session_revision then
                session_revision = pending_revision
                session_bit = pending_commit.operator_armed == true
            elseif pending_revision == session_revision
                and pending_commit.operator_armed ~= session_bit
            then
                return
            end
        end
        if apply_epoch < session_epoch
            or state_operator_revision < session_revision
            or state_operator_revision == session_revision
                and desired ~= session_bit
        then
            return
        end
        if apply_epoch > (tonumber(session.apply_epoch) or 0) then
            session.apply_epoch = apply_epoch
            session.acks = {}
        end
        if state_operator_revision > (tonumber(session.operator_revision) or 0)
        then
            set_operator_snapshot(session, state_operator_revision, desired)
        end
        if pending_commit and pending_commit.nonce == nonce then
            pending_commit.apply_epoch = apply_epoch
            carry_operator_snapshot(
                pending_commit, state_operator_revision, desired)
        end
    else
        session = {
            nonce=nonce, id=id, version=version, signature=signature,
            requester=leader, names_token=names_token,
            names=expected_names(profile), preview=false, votes={}, acks={},
            created_at=os.clock(), apply_epoch=apply_epoch,
            operator_revision=state_operator_revision,
            operator_armed=desired,
            arm_after_apply=desired, operator_sources={},
        }
        sessions[nonce] = session
    end
    -- A late or rejoining named client follows the same best-effort contract
    -- as the initial prepare path. Job, party, and controller observations
    -- are reported, but cannot veto installing the profile on that client.
    session.local_ready = true
    session.local_reason = matches and '' or ('setup warning: '..reason)
    send_vote(session, true, session.local_reason, player, 'join')
end

schedule_reapply = function(delay, required_epoch)
    if not active then return end
    delay = math.max(0, tonumber(delay) or 0)
    local current_epoch = tonumber(active.apply_epoch) or 0
    local requested_epoch = tonumber(required_epoch)
    if requested_epoch and (requested_epoch < 0
        or requested_epoch > 2147483647
        or requested_epoch ~= math.floor(requested_epoch))
    then
        return
    end
    if pending_reapply then
        -- A peer may already be rebuilding epoch N when a later authoritative
        -- leader state announces epoch N+1. Advance the pending replacement
        -- exactly; the older delayed callback is fenced by its epoch argument.
        if not requested_epoch
            or requested_epoch <= (tonumber(pending_reapply.epoch) or 0)
        then
            return
        end
        active.apply_epoch = requested_epoch
        reapply_epoch = math.max(reapply_epoch, requested_epoch)
        active.controller_ready = nil
        local session = sessions[active.nonce]
        if session then
            session.apply_epoch = requested_epoch
            session.operator_revision = active.operator_revision or 0
            session.operator_armed = active.operator_armed == true
            session.arm_after_apply = active.operator_armed == true
        end
        pending_reapply.epoch = requested_epoch
        pending_reapply.at = os.clock() + delay
        pending_reapply.deadline = pending_reapply.at + 25
        issue_profile_combat_off(profiles[active.id], false)
        issue(('wait %d; lua i PartyTactics __reapply %d')
            :format(delay, requested_epoch))
        return
    end
    -- Revoke the old runtime while its exact generation, epoch, and encounter
    -- authority are still valid. Otherwise exact-ID queue cancellation would
    -- be rejected and stale work could survive into the replacement epoch.
    deactivate_runtime(active)
    active.runtime = nil
    local target_epoch = requested_epoch and requested_epoch > current_epoch
        and requested_epoch or current_epoch + 1
    reapply_epoch = math.max(reapply_epoch, target_epoch)
    active.apply_epoch = target_epoch
    active.acks = {}
    active.preflight_epoch = nil
    active.preflight_checked_at = nil
    -- Preserve the authoritative desired tuple. Effective combat is stopped
    -- below and cannot resume until the replacement controller proves ready.
    active.arm_after_apply = active.operator_armed == true
    active.controller_ready = nil
    active.next_controller_probe_at = nil
    active.controller_probe_attempts = 0
    active.controller_probe_warned = false
    active.host_ready_revision = nil
    active.host_ready_epoch = nil
    active.legacy_ready_revision = nil
    active.legacy_ready_job = nil
    active.legacy_ready_epoch = nil
    active.encounter_authority_id = nil
    active.auto_preflight_at = nil
    active.ack_deadline = os.clock() + delay + APPLY_ACK_TIMEOUT
    local session = sessions[active.nonce]
    if session then
        session.apply_epoch = target_epoch
        session.acks = active.acks
        session.operator_revision = active.operator_revision or 0
        session.operator_armed = active.operator_armed == true
        session.arm_after_apply = active.operator_armed == true
    end
    issue_profile_combat_off(profiles[active.id], false)
    issue('pc invalidate partytactics')
    pending_reapply = {
        nonce=active.nonce, epoch=target_epoch,
        at=os.clock() + delay, deadline=os.clock() + delay + 25,
    }
    issue(('wait %d; lua i PartyTactics __reapply %d')
        :format(delay, target_epoch))
end

local function attempt_reapply(epoch)
    local pending = pending_reapply
    if not pending or not active or pending.nonce ~= active.nonce
        or epoch and epoch ~= pending.epoch or os.clock() < pending.at
    then return end
    local profile, plan = profiles[active.id], plans[active.id]
    local ready, reason, player = local_readiness(profile, active.names_token)
    if not player then
        if os.clock() < pending.deadline then
            pending.at = os.clock() + 1
            return
        end
        pending_reapply = nil
        chat(167, 'Profile could not reapply locally: no active player. '
            ..'Other clients and manual controls continue.')
        return
    end
    local local_plan = member_plan(plan, player.name)
    local runtime, context, runtime_error = create_runtime(profile)
    if not local_plan or runtime_error then
        pending_reapply = nil
        active.runtime_failed = true
        chat(167, 'Profile could not reapply locally: '
            ..tostring(runtime_error or 'local plan is unavailable')
            ..'. Other clients and manual controls continue.')
        return
    end
    if not ready and reason ~= '' then
        chat(123, 'Profile setup warning after zone change: '..reason
            ..'. Reapplying best-effort.')
    end
    issue_commands(local_plan.commands)
    authorize_required_controller(profile, active)
    active.runtime, active.context = runtime, context
    active.runtime_deactivated = false
    active.runtime_failed = false
    active.runtime_failed_methods = {}
    pending_reapply = nil
    active.ack_deadline = os.clock() + APPLY_ACK_TIMEOUT
    active.preflight_epoch = nil
    active.preflight_checked_at = nil
    active.auto_preflight_at = nil
    reraise_guard = {
        enabled=profile.safety and profile.safety.reraise == true or false,
        next_check=os.clock() + 6, warned=false,
    }
    if runtime and type(runtime.on_activate) == 'function' then
        invoke_runtime('on_activate')
    end
    request_gearswap_host_probe(active)
    request_legacy_helper_probe(active)
    probe_required_controller(profile, player)
    send_ack(active)
    if active.operator_armed then
        local adapter = profile.gearswap_adapter
        if not adapter or adapter.lifecycle_authorization ~= true then
            apply_legacy_combat_state_locally(profile, true)
        end
    end
    chat(158, active.id..' reapplied after zone/sync; PartyCombat is '
        ..(active.operator_armed and 'armed.' or 'unarmed.'))
end


local function check_reraise(now)
    if not active or not reraise_guard.enabled
        or now < reraise_guard.next_check
    then return end
    reraise_guard.next_check = now + RERAISE_CHECK_INTERVAL
    local player = windower.ffxi.get_player()
    local reraise = res.buffs:with('en', 'Reraise')
    if not player or not reraise then return end
    for _, buff_id in ipairs(player.buffs or {}) do
        if buff_id == reraise.id then
            reraise_guard.warned = false
            return
        end
    end
    if not reraise_guard.warned then
        chat(167, ('*** NO RERAISE: %s %s/%s. Restore it before the pull. ***')
            :format(player.name, tostring(player.main_job),
                tostring(player.sub_job)))
        reraise_guard.warned = true
    end
end

local function maintenance_tick(now)
    if not active or pending_reapply or now < next_maintenance then return end
    next_maintenance = now + MAINTENANCE_INTERVAL
    local player = windower.ffxi.get_player()
    local fallback = player
        and MAINTENANCE_FALLBACK_COMMANDS[player.main_job] or nil
    if fallback and gearswap_maintenance_fast_lane then
        -- This private fast lane refreshes GearSwap globals and invokes only
        -- the already-reviewed PartyStart maintenance callback.  It avoids
        -- running a no-equipment `gs c` command through the complete
        -- self-command/equipment pipeline every 0.75 seconds.
        issue('lua i GearSwap party_tactics_maintenance_tick')
    elseif fallback then
        -- Preserve role maintenance if an official GearSwap update replaces
        -- the local core patch. The catalog warning makes that slower fallback
        -- visible without sacrificing combat behavior.
        issue(fallback)
    end
end

local function party_actor(actor_id)
    actor_id = tonumber(actor_id)
    if not actor_id then return false end
    local player = windower.ffxi.get_player()
    if player and tonumber(player.id) == actor_id then return true end
    local party = windower.ffxi.get_party() or {}
    for index = 0, 5 do
        local member = party['p'..tostring(index)]
        local id = type(member) == 'table' and tonumber(
            member.mob and member.mob.id or member.mob_id or member.id) or nil
        if id == actor_id then return true end
    end
    return false
end

local function automatic_target(action)
    if type(action) ~= 'table' or not party_actor(action.actor_id) then
        return nil
    end
    local category = tonumber(action.category)
    if category ~= 1 and category ~= 2 and category ~= 3
        and category ~= 4 and category ~= 6
    then return nil end
    local info = windower.ffxi.get_info()
    local zone = info and tonumber(info.zone) or nil
    local names = zone and auto_profile_targets[zone] or nil
    if type(names) ~= 'table' then return nil end
    for _, target in ipairs(action.targets or {}) do
        local mob = windower.ffxi.get_mob_by_id(tonumber(target.id))
        local id = mob and names[type(mob.name) == 'string'
            and mob.name:lower() or ''] or nil
        if id and mob.spawn_type == 16 and mob.valid_target == true
            and (tonumber(mob.hpp) or 0) > 0
        then
            return id, mob, zone
        end
    end
    return nil
end

-- Returns true while the action belongs to a profile transition, preventing
-- the prior encounter runtime from interpreting the first swing on a new mob.
local function auto_select_profile(action)
    local id, mob, zone = automatic_target(action)
    if not id then return false end
    recent_hostile_target = {
        id=mob.id, index=mob.index, name=mob.name, zone=zone, at=os.clock(),
    }
    local profile = profiles[id]
    if not profile or not local_is_leader(profile) then return false end
    if active then
        -- A matching target may select a profile once, but it may never
        -- override a later Alt-P / //pt disarm decision.  Re-arming the same
        -- active profile here made an operator stop self-cancelling. It also
        -- may never replace a different active profile: profile boundaries
        -- are changed only by an explicit profile/start transaction.
        return false
    end
    if pending_commit then
        -- The transaction already in flight owns the next generation. A
        -- target packet cannot supersede or alter its arm state.
        return true
    end
    local now = os.clock()
    if last_auto_profile_id == id and now - last_auto_profile_at < 1.5 then
        return true
    end
    last_auto_profile_id, last_auto_profile_at = id, now
    chat(158, ('AUTO %s: %s engaged; loading and arming across the party.')
        :format(id, mob.name))
    begin(id, false, false, true)
    return true
end

windower.register_event('ipc message', function(message)
    if type(message) ~= 'string'
        or message:sub(1, #PREFIX + 1) ~= PREFIX..'|'
    then return end
    local fields = util.split(message, '|')
    local kind = fields[2]
    if kind == 'prepare' and #fields == 14 then
        process_prepare(fields[3], fields[4], fields[5], fields[6], fields[7],
            fields[8], fields[9], fields[10] == '1', fields[11] == '1',
            fields[12], fields[13], fields[14])
    elseif kind == 'vote' then
        local session = sessions[fields[3]]
        local name = fields[8]
        if session and session.initiator and not session.decided
            and fields[4] == _addon.version and fields[5] == session.id
            and fields[6] == session.version
            and fields[7] == session.signature and util.valid_name(name)
            and util.contains_name(session.names, name)
        then
            session.votes[name:lower()] = {
                ready=fields[9] == 'ready', main_job=fields[10],
                sub_job=fields[11], reason=fields[12] or 'unspecified rejection',
            }
            finalize_session(session, false)
        end
    elseif kind == 'commit' and #fields == 14 then
        handle_commit(fields[3], fields[4], fields[5], fields[6], fields[7],
            fields[8], fields[9], fields[10], fields[11] == '1',
            fields[12], fields[13], fields[14])
    elseif kind == 'abort' then
        local session = sessions[fields[3]]
        if session and session.id == fields[5]
            and session.signature == fields[7]
        then session.decided = session.decided or 'abort' end
    elseif kind == 'ack' then
        local record = active and active.nonce == fields[3] and active
            or sessions[fields[3]]
        local name = fields[8]
        if record and fields[4] == _addon.version and fields[5] == record.id
            and fields[6] == record.version and fields[7] == record.signature
            and util.valid_name(name) and util.contains_name(record.names, name)
            and tonumber(fields[9]) == (tonumber(record.apply_epoch) or 0)
        then
            record.acks = record.acks or {}
            record.acks[name:lower()] = tonumber(fields[9])
        end
    elseif kind == 'stop' and #fields == 10 then
        process_stop(fields[3], fields[4], fields[5], fields[6], fields[7],
            fields[8], fields[9], fields[10])
    elseif kind == 'fault' then
        local record = active or pending_commit
        local profile = record and profiles[record.id] or nil
        if record and fields[3] == record.nonce and fields[4] == _addon.version
            and fields[5] == record.id and fields[6] == record.version
            and fields[7] == record.signature and profile
            and util.contains_name(expected_names(profile), fields[8])
        then
            chat(123, tostring(fields[8])..' reported a local automation warning: '
                ..util.clean_field(fields[9] or 'unspecified')
                ..'. This client continues.')
        end
    elseif kind == 'operator-request' and #fields == 11
        and fields[4] == _addon.version
    then
        process_operator_request(fields[3], fields[4], fields[5], fields[6],
            fields[7], fields[8], fields[9], fields[10], fields[11])
    elseif kind == 'operator-state' and #fields == 11
        and fields[4] == _addon.version
    then
        process_operator_state(fields[3], fields[4], fields[5], fields[6],
            fields[7], fields[8], fields[9], fields[10], fields[11])
    elseif kind == 'manual' and fields[4] == _addon.version then
        process_manual(fields[3], fields[5], fields[6], fields[7],
            fields[8], fields[9])
    elseif kind == 'manual-result' and fields[4] == _addon.version then
        process_manual_result(fields[3], fields[5], fields[6], fields[7],
            fields[8], fields[9], fields[10], fields[11])
    elseif kind == 'runtime-controller' and fields[4] == _addon.version then
        process_runtime_controller(fields[3], fields[4], fields[5], fields[6],
            fields[7], fields[8], fields[9], fields[10], fields[11],
            fields[12], fields[13], fields[14], fields[15])
    elseif kind == 'adapter-status' and fields[4] == _addon.version then
        process_adapter_status(fields[3], fields[4], fields[5], fields[6],
            fields[7], fields[8], fields[9], fields[10], fields[11],
            fields[12], fields[13], fields[14], fields[15], fields[16],
            fields[17], fields[18])
    elseif kind == 'preflight-request' and fields[4] == _addon.version then
        process_preflight_request(fields[3], fields[4], fields[5], fields[6],
            fields[7], fields[8], fields[9], fields[10])
    elseif kind == 'preflight-result' and fields[4] == _addon.version then
        process_preflight_result(fields[3], fields[4], fields[5], fields[6],
            fields[7], fields[8], fields[9], fields[10], fields[11],
            fields[12], fields[13], fields[14])
    elseif kind == 'state' and #fields == 15 then
        process_state(fields[3], fields[4], fields[5], fields[6], fields[7],
            fields[8], fields[9], fields[10], fields[11], fields[12],
            fields[13], fields[14], fields[15])
    elseif kind == 'join' then
        local profile = active and profiles[active.id] or nil
        local name = fields[8]
        if active and profile and local_is_leader(profile)
            and fields[3] == active.nonce and fields[4] == _addon.version
            and fields[5] == active.id and fields[6] == active.version
            and fields[7] == active.signature and util.valid_name(name)
            and util.contains_name(active.names, name)
        then
            if fields[9] == 'ready' then
                local session = sessions[active.nonce] or active
                session.apply_epoch = active.apply_epoch or 0
                announce_commit(session)
            else
                chat(123, name..' could not rejoin: '
                    ..tostring(fields[12] or 'unknown reason')
                    ..'. Other clients continue.')
            end
        end
    end
end)

windower.register_event('prerender', function()
    local perf_wall, perf_cpu
    if party_tactics_perf and party_tactics_perf.enabled then
        perf_wall, perf_cpu = party_tactics_perf:begin_sample()
    end
    local now = os.clock()
    for nonce, session in pairs(sessions) do
        if session.initiator and not session.decided then
            if now >= session.deadline then
                finalize_session(session, true)
            elseif now >= (session.next_prepare_at or 0) then
                announce_prepare(session)
            end
        elseif session.initiator and session.decided == 'commit'
            and now <= (session.commit_retry_until or 0)
            and now >= (session.next_commit_at or math.huge)
        then
            announce_commit(session)
        elseif session.created_at and now - session.created_at > 45
            and (not active or active.nonce ~= nonce)
            and (not pending_commit or pending_commit.nonce ~= nonce)
        then
            sessions[nonce] = nil
        end
    end

    for nonce, check in pairs(preflight_checks) do
        if not check.done then
            if not active or active.nonce ~= check.generation
                or tonumber(active.apply_epoch) ~= check.epoch
            then
                check.done = true
            elseif now >= check.deadline then
                finalize_preflight(check, true)
            elseif now >= (check.next_request_at or 0) then
                announce_preflight(check)
            end
        elseif now - check.deadline > 30 then
            preflight_checks[nonce] = nil
        end
    end

    apply_pending_commit()
    attempt_reapply()
    repair_required_controller(now)
    apply_terminal_reassert(now)
    if active and not pending_reapply
        and not active.encounter_authority_id
    then
        local profile = profiles[active.id]
        local policy = profile and profile.preflight or nil
        local max_age = policy and tonumber(policy.max_age_seconds) or nil
        local epoch = tonumber(active.apply_epoch) or 0
        if local_is_leader(profile) and max_age
            and tonumber(active.preflight_epoch) == epoch
            and active.preflight_checked_at
            and now - active.preflight_checked_at >= max_age
        then
            -- Expiration changes only the displayed age of diagnostic data.
            active.preflight_epoch = nil
            active.preflight_checked_at = nil
            announce_state()
        end
    end
    -- No automatic check or retry loop. `//pt check` is operator-requested
    -- diagnostics and can never stall combat.
    if active and not pending_reapply and local_is_leader(profiles[active.id])
        and now >= next_state_sync
    then
        next_state_sync = now + STATE_SYNC_INTERVAL
        announce_state()
    end
    maintenance_tick(now)
    check_reraise(now)
    invoke_runtime('on_tick', now)
    if perf_wall then
        party_tactics_perf:finish_sample('prerender', perf_wall, perf_cpu)
    end
end)

windower.register_event('action', function(action)
    local perf_wall, perf_cpu
    if party_tactics_perf and party_tactics_perf.enabled then
        perf_wall, perf_cpu = party_tactics_perf:begin_sample()
    end
    if not auto_select_profile(action) then
        invoke_runtime('on_action', action)
    end
    if perf_wall then
        party_tactics_perf:finish_sample('action', perf_wall, perf_cpu)
    end
end)

windower.register_event('zone change', function()
    if active then schedule_reapply(8) end
end)

windower.register_event('gain buff', function(buff_id)
    if active and buff_id == 269 then schedule_reapply(3) end
end)

windower.register_event('job change', function()
    if active then
        deactivate_runtime(active)
        active.runtime = nil
        active.runtime_failed = true
        issue('pc localstop')
        chat(123, 'Local job changed; local fight callbacks paused. '
            ..'Other clients and manual controls continue; use //pt reapply when ready.')
    elseif pending_commit then
        pending_commit = nil
        chat(123, 'Local job changed while loading; this client skipped the profile.')
    end
end)

local function acknowledgement_count(record)
    local count = 0
    local epoch = tonumber(record and record.apply_epoch) or 0
    for _, name in ipairs(record and record.names or {}) do
        if record.acks and tonumber(record.acks[name:lower()]) == epoch then
            count = count + 1
        end
    end
    return count
end

local function status()
    if active then
        local player = windower.ffxi.get_player()
        local profile = profiles[active.id]
        local has_check = profile and profile.preflight ~= nil
        local preflight_passed = tonumber(active.preflight_epoch)
            == (tonumber(active.apply_epoch) or 0)
        local max_age = profile and profile.preflight
            and tonumber(profile.preflight.max_age_seconds) or nil
        if preflight_passed and max_age then
            preflight_passed = active.preflight_checked_at ~= nil
                and os.clock() - active.preflight_checked_at < max_age
        end
        local preflight_state = not has_check and 'none'
            or preflight_passed and 'PASS'
            or 'not run'
        chat(207, ('Active %s v%s | generation %s | local %s/%s | acks %d/6 | preflight %s | combat %s r%d%s')
            :format(active.id, active.version, active.nonce,
                player and player.main_job or 'NON',
                player and player.sub_job or 'NON',
                acknowledgement_count(active),
                preflight_state,
                active.operator_armed and 'armed' or 'unarmed',
                tonumber(active.operator_revision) or 0,
                pending_reapply and ' | reapply pending' or ''))
    elseif pending_commit then
        chat(207, 'Transitioning to '..pending_commit.id..' v'
            ..pending_commit.version..'.')
    else
        chat(207, 'Inactive | selected '..(selected_id or 'none')
            ..' | valid profiles '..tostring(util.count(profiles))
            ..' | catalog errors '..tostring(#catalog_errors)
            ..' | setup warnings '..tostring(#catalog_warnings))
    end
end

windower.register_event('addon command', function(command, ...)
    local args = {...}
    command = (command or 'status'):lower()
    if command == '__reapply' then
        attempt_reapply(tonumber(args[1]))
        return
    elseif command == '__controller_ready' then
        if #args == 4 then
            process_controller_ready(args[1], args[2], args[3], args[4])
        end
        return
    elseif command == '__controller_lost' then
        if #args == 4 then
            process_controller_lost(args[1], args[2], args[3], args[4])
        end
        return
    elseif command == '__controller_terminal' then
        if #args == 4 then
            process_controller_terminal(args[1], args[2], args[3], args[4])
        end
        return
    elseif command == '__recover_controller' then
        if #args == 10 or #args == 12 then
            process_recover_controller(args[1], args[2], args[3], args[4],
                args[5], args[6], args[7], args[8], args[9], args[10],
                args[11], args[12])
        end
        return
    elseif command == '__adapter_status' then
        process_local_adapter_status(args[1], args[2], args[3], args[4],
            args[5], args[6], args[7], args[8], args[9])
        return
    elseif command == '__gearswap_host_ready' then
        process_gearswap_host_ready(args[1], args[2], args[3])
        return
    elseif command == '__legacy_helper_ready' then
        process_legacy_helper_ready(args[1], args[2], args[3], args[4])
        return
    elseif command == '__gearswap_host_lost' then
        local reason = args[2]
        if args[1] == GEARSWAP_HOST_REVISION
            and (reason == 'file-unload' or reason == 'addon-unload'
                or reason == 'logout' or reason == 'adapter-error')
        then
            if active then
                active.controller_ready = nil
                active.preflight_epoch = nil
                active.preflight_checked_at = nil
            end
            chat(123, 'GearSwap adapter host changed ('..reason
                ..'); manual controls and profile support remain available. '
                ..'Use //pt reapply to restore fight-specific automation.')
        end
        return
    elseif command == 'perf' then
        if party_tactics_perf then
            party_tactics_perf:command(args[1])
        else
            chat(123, 'Hot-path profiler library is unavailable; addon behavior is unaffected.')
        end
        return
    end
    if command == 'use' then
        -- Loading is an operational command: it selects and arms.  The only
        -- inert load spelling is the private `inert` mode used by explicit
        -- integrations; operators use `preview` when they only want to
        -- inspect a profile.  This prevents periodic state repair from
        -- replaying an accidental OFF bit after a successful profile load.
        begin(args[1], false, false,
            tostring(args[2] or ''):lower() ~= 'inert')
    elseif command == 'preview' then
        begin(args[1], true, false)
    elseif command == 'reapply' then
        -- Reapply repairs the current profile; it must preserve the current
        -- operator intent instead of silently converting an armed profile to
        -- OFF.
        local profile = active and profiles[active.id] or nil
        local adapter = profile and profile.gearswap_adapter or nil
        begin(active and active.id or selected_id, false, true,
            active and active.operator_armed == true,
            active and active.operator_revision or nil,
            adapter and adapter.lifecycle_authorization == true
                and tonumber(adapter.protocol) >= 2)
    elseif command == 'on' or command == 'start' then
        if active then request_operator_state(true)
        else begin(selected_id, false, false, true) end
    elseif command == 'off' or command == 'stop' then
        request_stop('leader requested stop')
    elseif command == 'arm' then
        request_operator_state(true)
    elseif command == 'disarm' then
        request_operator_state(false)
    elseif command == 'force' then
        if not active or not local_is_leader(profiles[active.id]) then
            chat(123, 'Force PartyCombat from the active profile leader.')
        else
            request_operator_state(true)
            local profile = profiles[active.id]
            local adapter = profile and profile.gearswap_adapter or nil
            local ordered_lifecycle = adapter
                and adapter.lifecycle_authorization == true
                and tonumber(adapter.protocol) >= 2
            if ordered_lifecycle then
                -- Protocol-2 owns the complete ON transition. A trailing raw
                -- force would require Dolo to have a target even when an
                -- automatic puller owns acquisition, and could bypass an
                -- adapter's temporary maintenance hold when a target exists.
            elseif profile and profile.runtime_owns_pull == true
                and active.runtime then
                chat(158, ('Tank-first pull requested: %s owns initial '
                    ..'engagement; the runtime will release damage after '
                    ..'the puller acts or its two-second safety release fires.')
                    :format(profile.combat.puller))
            else
                issue('pc force')
            end
        end
    elseif command == 'check' or command == 'preflight' then
        begin_preflight(false)
    elseif command == 'action' then
        request_manual((args[1] or ''):lower())
    elseif command == 'sleep' then
        request_manual('sleep')
    elseif resolve_profile(command) then
        -- A frozen profile ID/alias always wins over a fight-local shorthand.
        -- New manual actions remain reachable through `pt action <name>` but
        -- can never shadow an established profile switch such as `pt locus`.
        -- Direct profile commands are the simple operational surface: select
        -- and arm in one transaction.  `preview` remains the inert inspection
        -- command and `use <profile>` retains its explicit arm argument for
        -- route integrations.
        begin(resolve_profile(command), false, false, true)
    elseif active and profiles[active.id].manual_actions
        and profiles[active.id].manual_actions[command]
    then
        request_manual(command)
    elseif command == 'status' then
        status()
    elseif command == 'version' then
        chat(207, 'Version '.._addon.version
            ..' | profile schema 1 | checks advisory | manual controls always available.')
    elseif command == 'list' then
        for _, id in ipairs(util.sorted_keys(profiles)) do
            chat(207, ('%s v%s - %s'):format(
                id, profiles[id].version, profiles[id].label))
        end
        if #catalog_errors > 0 then
            chat(123, #catalog_errors..' catalog issue(s) quarantined; use //pt errors.')
        end
        if #catalog_warnings > 0 then
            chat(123, #catalog_warnings
                ..' setup warning(s); profiles remain selectable. Use //pt errors.')
        end
    elseif command == 'show' then
        local id = resolve_profile(args[1])
        if id then show_profile(id, true)
        else chat(123, 'Unknown profile: '..tostring(args[1])) end
    elseif command == 'errors' then
        if #catalog_errors == 0 and #catalog_warnings == 0 then
            chat(207, 'No catalog errors or setup warnings.')
        end
        for _, message in ipairs(catalog_errors) do chat(167, message) end
        for _, message in ipairs(catalog_warnings) do chat(123, message) end
    else
        chat(207, 'Commands: use <profile> | preview <profile> | reapply | '
            ..'off | check | arm | disarm | force | action <name> | status | list | '
            ..'show <profile> | errors | version. Profile aliases work directly.')
    end
end)

windower.register_event('unload', function()
    if active or pending_commit then
        stop_local('PartyTactics unloaded locally', nil, true)
    end
end)

-- PartyCombat is loaded before PartyTactics by the supported init and safe
-- reload paths. Do not blindly load it here: Windower reports an error when
-- the dependency is already present, and profile application supplies the
-- validated inert policy before any ordered operator ON can become effective.

chat(158, ('Loaded v%s inert with %d isolated profiles; the PartyStart addon '
    ..'is neither loaded nor used, and FastFollow is untouched. Use '
    ..'//pt preview <profile>, then '
    ..'//pt use <profile>.'):format(_addon.version, util.count(profiles)))
if #catalog_errors > 0 then
    chat(123, #catalog_errors..' catalog issue(s) were quarantined; '
        ..'valid profiles remain available. Use //pt errors.')
end
if #catalog_warnings > 0 then
    chat(123, #catalog_warnings..' setup warning(s) detected; '
        ..'profiles remain selectable and unaffected lanes can run. Use //pt errors.')
end
