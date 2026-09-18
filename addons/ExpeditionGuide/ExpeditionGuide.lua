--[[
ExpeditionGuide

Leader-side route guidance plus six-client read-only sensing for FFXI
expeditions.  Sortie is the first content pack; combat remains owned by
PartyTactics and equipment remains owned by GearSwap.

Copyright (c) 2026 Don Lawrence.  See LICENSE.
]]

_addon.name = 'ExpeditionGuide'
_addon.author = 'OpenAI Codex at the direction of Dolomedes'
_addon.version = '1.2.0'
_addon.commands = {'exg', 'expeditionguide'}

local config = require('config')
local texts = require('texts')
local images = require('images')
local packets = require('packets')

local Schema = require('lib.schema')
local ContentLoader = require('lib.content_loader')
local Engine = require('lib.route_engine')
local Navigation = require('lib.navigation')
local Protocol = require('lib.protocol')
local Sensors = require('lib.sensors')
local PartyState = require('lib.party_state')
local StateStore = require('lib.state_store')
local ProfileBridge = require('lib.profile_bridge')
local AutomationBridge = require('lib.automation_bridge')
local Sandbox = require('lib.sandbox')
local Fingerprint = require('lib.fingerprint')
local StateValidation = require('lib.state_validation')
local RunSession = require('lib.run_session')
local RewardSafety = require('lib.reward_safety')
local Arrow = require('lib.arrow')

local ROSTER = {
    'Dolomedes', 'Tackleberry', 'Kickpuncher',
    'Barneystinson', 'Smalls', 'Achoo',
}

local defaults = {
    layout_revision = 0,
    leader = 'Dolomedes',
    visible = true,
    peer_max_age = 8,
    sensor_interval = 1,
    render_interval = 0.10,
    entity_scan_interval = 0.75,
    waypoint_dwell = 0.60,
    automatic_profile_requests = true,
    automatic_route_actions = true,
    display = {
        pos = {x = 18, y = 300},
        wrap_width = 88,
        text = {
            font = 'Consolas', size = 18,
            alpha=255, red=235, green=242, blue=250,
            stroke = {width=3, alpha=235, red=0, green=0, blue=0},
        },
        bg = {visible=true, alpha=218, red=5, green=12, blue=20},
        flags = {bold=true, draggable=true, right=false, bottom=false},
        padding = 12,
    },
    arrow = {
        visible = false,
        auto_center = true,
        pos = {x = 0, y = 48},
        size = 180,
        frame_count = 32,
        prefix = 'arrow_v2_',
        alpha = 245,
    },
}

local function discover_content(declaration, kind)
    local directory = declaration[kind == 'routes'
        and 'route_directory' or 'profile_directory']
    local prefix = declaration[kind == 'routes'
        and 'route_module_prefix' or 'profile_module_prefix']
    if type(directory) ~= 'string' or type(prefix) ~= 'string'
        or type(windower.get_dir) ~= 'function' then return {} end
    local names = windower.get_dir(windower.addon_path .. directory) or {}
    local declarations = {}
    for _, name in pairs(names) do
        name = tostring(name)
        if name:match('^[A-Za-z0-9_-]+%.lua$') then
            local basename = name:sub(1, -5):lower()
            local identity = kind == 'routes'
                and (declaration.id .. '-' .. basename:gsub('_', '-'))
                or (declaration.id .. '_' .. basename)
            declarations[#declarations + 1] = {
                module=prefix .. basename,
                path=directory .. name,
                identity=identity,
            }
        end
    end
    return declarations
end

local function load_discovered_content(declaration)
    local value, reason = Sandbox.load(
        windower.addon_path .. declaration.path, loadfile)
    if not value then error(reason) end
    return value
end

local registry_ok, registry = pcall(require, 'content.registry')
local registry_error = nil
if not registry_ok then
    registry_error = tostring(registry)
    registry = {schema=0, packs={}}
end
local content, content_errors = ContentLoader.load(registry, Schema, require, {
    discover=discover_content,
    load_data=load_discovered_content,
    fingerprint=Fingerprint.value,
})
if registry_error then
    content_errors[#content_errors + 1] = 'content registry unavailable: '
        .. registry_error
end
local pack_ids = {}
for id in pairs(content.packs) do pack_ids[#pack_ids + 1] = id end
table.sort(pack_ids)

local settings = nil
local settings_character = nil
local party_states = {}
local engine = nil
local active_route_id = nil
local hud = nil
local arrow = nil
local bridges = {}
local automation_bridge = nil
local state_path = nil
local navigation_overrides = {}
local waypoint_tracker = {}
local cached_live_waypoint = nil
local last_local_reports = {}
local run_sessions = {}
local reward_gate = nil
local local_sequence = 0
local last_sensor_at = -100
local last_render_at = -100
local last_entity_scan_at = -100
local last_persist_at = 0
local recovery_required = false
local debug_enabled = false
local last_menu_evidence = nil
local content_failure_reported = false
local automation_source_cache = {at=-100,step_id=nil,ready=false}

local function migrate_layout(value)
    if not value then return false end
    local revision = tonumber(value.layout_revision) or 0
    local changed = false
    if revision < 2 then
        local display = value.display or {}
        display.pos = display.pos or {}
        display.text = display.text or {}
        local screen = type(windower.get_windower_settings) == 'function'
            and windower.get_windower_settings() or {}
        local width = tonumber(screen.ui_x_res or screen.x_res) or 1920
        display.pos.x = math.floor(width * 0.58)
        display.pos.y = 300
        display.text.size = 18
        display.text.stroke = display.text.stroke or {}
        display.text.stroke.width = 3
        display.wrap_width = 88
        value.display = display
        value.arrow = value.arrow or {}
        value.arrow.visible = true
        value.arrow.auto_center = true
        value.arrow.pos = value.arrow.pos or {x=0,y=80}
        value.arrow.pos.y = 80
        value.arrow.size = 180
        value.arrow.frame_count = 32
        changed = true
    end
    if revision < 3 then
        -- Revision 3 promotes route-owned profile handoffs and allowlisted
        -- Sortie Device/Gadget operations. Existing revision-2 `false` values
        -- came from the old default and were never exposed as a user choice.
        value.automatic_profile_requests = true
        value.automatic_route_actions = true
        value.layout_revision = 3
        changed = true
    end
    if revision < 4 then
        value.arrow = value.arrow or {}
        value.arrow.visible = true
        value.arrow.auto_center = true
        value.arrow.pos = value.arrow.pos or {x=0,y=48}
        value.arrow.pos.y = 48
        value.arrow.size = 280
        value.arrow.frame_count = 32
        value.arrow.prefix = 'arrow_v2_'
        value.layout_revision = 4
        changed = true
    end
    if revision < 5 then
        -- Restore the original usable scale and leave this provisional arrow
        -- disabled. A later explicit `//exg arrow on` is persisted at revision
        -- 5 and is therefore never overwritten by another reload.
        value.arrow = value.arrow or {}
        value.arrow.size = 180
        value.arrow.visible = false
        value.layout_revision = 5
        changed = true
    end
    return changed
end

local function chat(color, message)
    if message == nil then message, color = color, 207 end
    windower.add_to_chat(color, '[ExpeditionGuide] ' .. tostring(message))
end

local function dispatch_command(command)
    windower.send_command(command)
end

local function debug(message)
    if debug_enabled then chat(160, 'DEBUG: ' .. tostring(message)) end
end

local function sanitize_filename(value)
    return tostring(value or 'Unknown'):gsub('[^%w_-]', '_')
end

local function player()
    return windower.ffxi.get_player()
end

local function current_zone()
    local info = windower.ffxi.get_info()
    return info and tonumber(info.zone) or nil
end

local function is_leader()
    local current = player()
    return current and settings
        and current.name:lower() == tostring(settings.leader):lower()
end

local function resolve_route(value)
    value = tostring(value or ''):lower()
    local id = content.routes[value] and value or content.aliases[value]
    return id and content.routes[id] or nil
end

local function pack_for_route(route)
    return route and content.packs[route.content] or nil
end

local function current_pack()
    local pack = pack_for_route(engine and engine.route or nil)
    if pack then return pack end
    return pack_for_route(resolve_route('onboarding'))
        or content.packs[pack_ids[1]]
end

local function current_party_state()
    local pack = current_pack()
    return pack and party_states[pack.id] or nil
end

local function current_local_report()
    local pack = current_pack()
    return pack and last_local_reports[pack.id] or nil
end

local function current_bridge()
    local pack = current_pack()
    return pack and bridges[pack.id] or nil
end

local function current_run_session()
    local pack = current_pack()
    return pack and run_sessions[pack.id] or nil
end

local function current_reward_scopes()
    local pack = current_pack()
    return pack and pack.route_reward_scopes
        and pack.route_reward_scopes[active_route_id] or {}
end

local function make_engine(route, saved)
    local pack = assert(pack_for_route(route), 'route pack unavailable')
    active_route_id = route.id
    engine = Engine.new(route, saved, os.time(),
        pack.route_digests and pack.route_digests[route.id] or route.version)
end

local function current_landmarks()
    local pack = current_pack()
    return pack and pack.route_landmarks
        and pack.route_landmarks[active_route_id] or pack and pack.landmarks or {}
end

local function current_navigation_overrides()
    navigation_overrides[active_route_id] =
        navigation_overrides[active_route_id] or {}
    return navigation_overrides[active_route_id]
end

local function route_zone_ready()
    if not engine or not engine.state.active or engine.state.paused
        or engine.state.complete then return false, nil end
    local zone = current_zone()
    local pack = current_pack()
    if not zone or type(engine.route.allowed_zones) ~= 'table'
        or engine.route.allowed_zones[zone] ~= true or not pack
        or pack.instance_zones[zone] ~= true then return false, zone end
    local session = current_run_session()
    if not session or not engine.state.active_run_id
        or session.bound_run_id ~= engine.state.active_run_id then
        return false, zone
    end
    local report = current_local_report()
    if not report or report.ready ~= true
        or tonumber(report.zone) ~= zone then return false, zone end
    return true, zone
end

-- Navigation is useful even when six-client evidence could not bind the run.
-- Keep evidence/reward validation strict, but never take the route or arrow
-- away from an operator who needs to improvise inside the instance.
local function route_navigation_ready()
    if not engine or not engine.state.active or engine.state.paused
        or engine.state.complete then return false end
    local zone = current_zone()
    local pack = current_pack()
    return zone ~= nil and pack ~= nil
        and type(engine.route.allowed_zones) == 'table'
        and engine.route.allowed_zones[zone] == true
        and pack.instance_zones[zone] == true
end

-- Superwarp must see its source object before a request is useful. Resolve the
-- exact route-owned Device/Gadget entity and require Dolo to be within normal
-- interaction range. A missing entity is a wait condition, never a failed or
-- consumed route action.
local function automation_source_ready(step)
    if type(step) ~= 'table' or type(step.automation) ~= 'table' then
        return false
    end
    local now = os.clock()
    if automation_source_cache.step_id == step.id
        and now - automation_source_cache.at < 0.50 then
        return automation_source_cache.ready
    end
    local wanted = step.automation.operation == 'port'
        and 'diaphanous gadget' or 'diaphanous device'
    local landmark_id = step.waypoint
        or (type(step.path) == 'table' and step.path[1])
    local landmark = landmark_id and current_landmarks()[landmark_id] or nil
    local me = windower.ffxi.get_mob_by_target
        and windower.ffxi.get_mob_by_target('me') or nil
    local function in_range(mob)
        if type(mob) ~= 'table'
            or tostring(mob.name or ''):lower():sub(1,#wanted) ~= wanted then
            return false
        end
        local distance, dz
        if tonumber(mob.distance) then
            distance = math.sqrt(math.max(0,tonumber(mob.distance)))
            dz = me and tonumber(me.z) and tonumber(mob.z)
                and (tonumber(mob.z)-tonumber(me.z)) or nil
        else
            distance, dz = Navigation.distance(me,mob)
        end
        return distance ~= nil and distance <= 8
            and (dz == nil or math.abs(dz) <= 12)
    end
    local ready = false
    if type(landmark) == 'table' then
        ready = in_range(Sensors.live_landmark(
            windower,landmark_id,landmark))
    end
    if not ready and windower.ffxi.get_mob_array then
        for _,mob in pairs(windower.ffxi.get_mob_array() or {}) do
            if in_range(mob) then ready=true; break end
        end
    end
    if not ready and windower.ffxi.get_mob_by_target then
        ready = in_range(windower.ffxi.get_mob_by_target('t'))
    end
    automation_source_cache={at=now,step_id=step.id,ready=ready}
    return ready
end

local function reconcile_route_lifecycle()
    if not is_leader() or not engine then return false end
    local step = engine:current()
    local zone = current_zone()
    local pack = current_pack()
    local active = step ~= nil and engine.state.active
        and not engine.state.paused and not engine.state.complete
        and engine.route.guide_only ~= true
    local inside = zone ~= nil and pack ~= nil
        and type(engine.route.allowed_zones) == 'table'
        and engine.route.allowed_zones[zone] == true
        and pack.instance_zones[zone] == true
    local context = {
        is_leader=true,in_allowed_zone=inside,route_active=active,
        source_ready=step and automation_source_ready(step) or false,
        now=os.clock(),
    }
    local changed = false
    local bridge = current_bridge()
    if bridge and engine.route.target_selected_combat ~= true then
        local emitted, operation = bridge:reconcile(
            step and step.profile or nil,
            step and step.profile_arm == true,
            context)
        if emitted then
            changed = true
            chat(158,'Automatic combat handoff: '..tostring(operation)..'.')
        end
    end
    if automation_bridge and step and step.automation then
        local token = table.concat({
            tostring(active_route_id),tostring(engine.state.current_index),
            tostring(step.id),tostring(engine.state.run_started_at or 0),
        },':')
        local emitted, operation, attempt = automation_bridge:reconcile(
            step.automation,token,context)
        if emitted then
            changed = true
            chat(158,('Automatic route action%s: %s.')
                :format((tonumber(attempt) or 1) > 1
                    and (' retry '..tostring(attempt)) or '',
                    tostring(operation)))
        end
    end
    return changed
end

local function clear_step_observations(reason)
    waypoint_tracker = {}
    cached_live_waypoint = nil
    last_menu_evidence = nil
    automation_source_cache = {at=-100,step_id=nil,ready=false}
    if reward_gate then
        reward_gate:reset(reason or 'route or step context changed')
    end
end

local function ensure_data_directory()
    local path = windower.addon_path .. 'data\\'
    if windower.dir_exists and not windower.dir_exists(path)
        and windower.create_dir then
        windower.create_dir(path)
    end
    return path
end

local function state_wrapper()
    return {
        schema=3,
        addon_version=_addon.version,
        character=settings_character,
        active_route_id=active_route_id,
        route_state=engine and engine:snapshot(os.time()) or nil,
        navigation_overrides=navigation_overrides,
        recovery_required=recovery_required,
        saved_at=os.time(),
    }
end

local function persist(force)
    if not is_leader() or not state_path or not engine then return end
    local now = os.time()
    if not force and now - last_persist_at < 20 then return end
    local ok, reason = StateStore.save(state_path, state_wrapper())
    if ok then
        last_persist_at = now
    else
        chat(123, 'Could not save route state: ' .. tostring(reason))
    end
end

local function load_saved_state(path)
    local function validate(candidate)
        if not candidate then return nil, 'state file could not be loaded' end
        return StateValidation.sanitize(candidate, {
            character=settings_character,
            routes=content.routes,
            route_landmarks=content.route_landmarks,
            route_digests=content.route_digests,
        })
    end
    local failures = {}
    for index, candidate in ipairs({
        {path=path, label='saved'},
        {path=path .. '.previous', label='recovery'},
        {path=path .. '.bak', label='backup'},
    }) do
        local saved, load_reason = StateStore.load(candidate.path)
        local clean, validation_reason, notes = validate(saved)
        if clean then
            if index > 1 then
                chat(158, ('Recovered route state from validated %s data.')
                    :format(candidate.label))
            end
            if notes.discarded_overrides > 0 then
                chat(123, ('Discarded %d invalid %s navigation override(s).')
                    :format(notes.discarded_overrides, candidate.label))
            end
            if notes.route_identity_reset then
                chat(123, ('%s route content changed; route progress was reset safely.')
                    :format(candidate.label:gsub('^%l', string.upper)))
            end
            if notes.wrapper_migrated or notes.foray_reset then
                chat(123, ('%s per-foray authorization was discarded safely; a fresh six-client entry binding is required.')
                    :format(candidate.label:gsub('^%l', string.upper)))
            end
            return clean
        end
        failures[#failures + 1] = candidate.label .. '='
            .. tostring(validation_reason or load_reason)
    end
    debug('no valid saved state: ' .. table.concat(failures, '; '))
    return nil
end

local function initialize()
    local current = player()
    if not current or not current.name then return false end
    if #pack_ids == 0 then
        if not content_failure_reported then
            content_failure_reported = true
            chat(123, 'No content pack is available; ExpeditionGuide remains inert.')
            for _, message in ipairs(content_errors or {}) do chat(123, message) end
        end
        return false
    end
    if settings and settings_character == current.name then return true end

    settings_character = current.name
    settings = config.load(('data/settings_%s.xml'):format(
        sanitize_filename(settings_character)), defaults)
    migrate_layout(settings)
    config.save(settings)
    reward_gate = RewardSafety.new()
    party_states, bridges, last_local_reports, run_sessions = {}, {}, {}, {}
    for _, id in ipairs(pack_ids) do
        local pack = content.packs[id]
        party_states[id] = PartyState.new(ROSTER, pack, settings.leader)
        run_sessions[id] = RunSession.new(pack, current.name)
        run_sessions[id]:cold_start(current_zone())
        bridges[id] = ProfileBridge.new(pack.profiles, dispatch_command,
            {enabled=settings.automatic_profile_requests == true})
    end
    automation_bridge = AutomationBridge.new(dispatch_command,
        {enabled=settings.automatic_route_actions == true})
    local data_dir = ensure_data_directory()
    state_path = data_dir .. ('state_%s.lua'):format(
        sanitize_filename(settings_character))

    if is_leader() then
        local HUD = require('lib.hud')
        hud = HUD.new(texts, settings.display, settings)
        arrow = Arrow.new(images, settings.arrow,
            windower.addon_path .. 'assets\\arrow\\', windower)
        if settings.visible == false then
            hud:hide()
            arrow:hide()
        end
        local saved = load_saved_state(state_path)
        local replace_training = saved
            and saved.active_route_id == 'sortie-two-boss-c-a-training'
        local route = replace_training and resolve_route('mainrun')
            or saved and resolve_route(saved.active_route_id)
            or resolve_route('mainrun') or resolve_route('onboarding')
        if not route then
            chat(123, 'No valid onboarding route loaded; guide remains inert.')
            for _, message in ipairs(content_errors or {}) do chat(123, message) end
            return false
        end
        local saved_last_seen = saved and saved.route_state
            and tonumber(saved.route_state.last_seen_at) or nil
        local saved_was_active = saved and saved.route_state
            and saved.route_state.active == true or false
        make_engine(route, not replace_training and saved
            and saved.route_state or nil)
        navigation_overrides = saved
            and type(saved.navigation_overrides) == 'table'
            and saved.navigation_overrides or {}
        recovery_required = saved and saved.recovery_required == true or false
        local pack = current_pack()
        if route.auto_start == true
            and (not engine.state.active or engine.state.complete)
            and not (pack and pack.instance_zones[current_zone()]) then
            engine:start(os.time())
            recovery_required = false
        end
        if pack and pack.instance_zones[current_zone()] then
            engine:unbind_run(os.time(), engine.state.active)
            recovery_required = engine.state.active or recovery_required
        end
        if saved_was_active and saved_last_seen and pack
            and os.time() - saved_last_seen > pack.stale_run_seconds then
            engine.state.paused = true
            recovery_required = true
        end
        for _, message in ipairs(content_errors or {}) do
            chat(123, message)
        end
        chat(158, ('v%s ready on %s; route %s is %s.'):format(
            _addon.version, current.name, route.id,
            route.guide_only and 'GUIDE ONLY' or 'operational'))
    end
    return true
end

local function capture_local(now)
    if not initialize() then return nil end
    local_sequence = local_sequence + 1
    if local_sequence > 2147483646 then local_sequence = 1 end
    local snapshot = Sensors.snapshot(windower, now, ROSTER, settings.leader)
    if not snapshot then return nil end
    for _, id in ipairs(pack_ids) do
        local session = run_sessions[id]
        local report = Sensors.report(snapshot, content.packs[id], local_sequence,
            session and session.entry_nonce or nil)
        local wire = Protocol.state(report)
        local accepted, reason = Protocol.validate(wire, {
            now=now, max_age=tonumber(settings.peer_max_age) or 8,
            catalogs=content.packs,
            allowed_sender=function(name)
                return party_states[id]:allowed_sender(name)
            end,
        })
        if accepted then
            -- Retain unrounded facing locally for navigation; party evidence
            -- receives the same validated shape every remote client decodes.
            last_local_reports[id] = report
            party_states[id]:update(accepted, os.clock())
            windower.send_ipc_message(wire)
        else
            debug(('local %s report rejected: %s'):format(id, tostring(reason)))
        end
    end
    return current_local_report()
end

local function current_waypoint_id(step)
    if not step then return nil end
    if type(step.path) == 'table' then
        return step.path[engine.state.waypoint_index]
    end
    return step.waypoint
end

local function calibrate(landmark_id, value, source)
    local zone_ready = route_zone_ready()
    local x, y = tonumber(value and value.x), tonumber(value and value.y)
    local z = tonumber(value and value.z)
    if not is_leader() or not zone_ready or not landmark_id or not x or not y
        or x ~= x or y ~= y or (z and z ~= z)
        or math.abs(x) > 10000 or math.abs(y) > 10000
        or (z and math.abs(z) > 10000) then return false end
    local landmarks = current_landmarks()
    local landmark = landmarks and landmarks[landmark_id] or nil
    if type(landmark) ~= 'table' then return false end
    local overrides = current_navigation_overrides()
    local previous = overrides[landmark_id]
    local previous_x = type(previous) == 'table' and tonumber(previous.x) or nil
    local previous_y = type(previous) == 'table' and tonumber(previous.y) or nil
    local previous_z = type(previous) == 'table' and tonumber(previous.z) or nil
    local changed = not previous_x or not previous_y
        or math.abs(previous_x - x) > 0.25
        or math.abs(previous_y - y) > 0.25
        or math.abs((previous_z or 0) - (z or 0)) > 0.25
    if not changed then return false end
    overrides[landmark_id] = {
        name=landmark.name,
        x=x, y=y, z=z,
        radius=landmark.radius or 5,
        z_tolerance=landmark.z_tolerance or 12,
        confidence=source or value.confidence or 'live_calibrated',
        captured_at=os.time(),
    }
    debug(('calibrated %s at %.2f %.2f %.2f'):format(
        landmark_id, x, y, z or 0))
    persist(true)
    return true
end

local function scan_current_waypoint()
    cached_live_waypoint = nil
    if not route_zone_ready() then return end
    local step = engine:current()
    local id = current_waypoint_id(step)
    local landmark = id and current_landmarks()[id] or nil
    if not landmark then return end
    local live = Sensors.live_landmark(windower, id, landmark)
    if live then
        cached_live_waypoint = live
        calibrate(id, live, live.confidence)
    end
end

local function party_summary(now)
    local state = current_party_state()
    return state:summary(now, tonumber(settings.peer_max_age) or 8,
        current_zone())
end

local function diagnostic_spec(pack, diagnostic_id)
    local catalog = pack and pack.key_items
    local spec = catalog and type(catalog.diagnostics) == 'table'
        and catalog.diagnostics[diagnostic_id] or nil
    if type(spec) ~= 'table' or type(catalog.by_key) ~= 'table'
        or type(spec.title) ~= 'string'
        or type(spec.primary) ~= 'string' or type(spec.secondary) ~= 'string'
        or spec.primary == spec.secondary
        or not catalog.by_key[spec.primary] or not catalog.by_key[spec.secondary]
        or type(spec.primary_label) ~= 'string'
        or type(spec.secondary_label) ~= 'string'
        or type(spec.missing_label) ~= 'string'
        or type(spec.invalid_label) ~= 'string'
        or type(spec.unknown_label) ~= 'string' then
        return nil
    end
    return spec
end

local function format_key_item_diagnostic(pack, summary, diagnostic_id)
    local spec = diagnostic_spec(pack, diagnostic_id)
    if not spec then return nil end
    local groups = {
        [spec.primary_label]={}, [spec.secondary_label]={},
        [spec.missing_label]={}, [spec.invalid_label]={},
        [spec.unknown_label]={},
    }
    for _, name in ipairs(ROSTER) do
        local presence = type(summary.key_item_presence) == 'table'
            and summary.key_item_presence[name] or nil
        local label
        if type(presence) ~= 'table' then
            label = spec.unknown_label
        else
            local primary = presence[spec.primary] == true
            local secondary = presence[spec.secondary] == true
            if primary and secondary then
                label = spec.invalid_label
            elseif primary then
                label = spec.primary_label
            elseif secondary then
                label = spec.secondary_label
            else
                label = spec.missing_label
            end
        end
        groups[label][#groups[label] + 1] = name
    end
    local parts = {spec.title}
    for _, label in ipairs({spec.primary_label, spec.secondary_label,
        spec.missing_label, spec.invalid_label, spec.unknown_label}) do
        local names = groups[label]
        parts[#parts + 1] = ('%s %d: %s'):format(label, #names,
            #names > 0 and table.concat(names, ',') or 'none')
    end
    return table.concat(parts, ' | '), spec, groups
end

local function diagnostic_for_item(pack, summary, item_key)
    local diagnostics = pack and pack.key_items
        and pack.key_items.diagnostics or nil
    if type(diagnostics) ~= 'table' then return nil end
    local ids = {}
    for id in pairs(diagnostics) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local line, spec, groups = format_key_item_diagnostic(
            pack, summary, id)
        if spec and spec.primary == item_key then
            return line, spec, groups
        end
    end
    return nil
end

local function reconcile_run_binding(now)
    if not is_leader() or not engine then return false end
    local pack = current_pack()
    local session = current_run_session()
    if not pack or not session or not pack.instance_zones[current_zone()] then
        return false
    end
    local summary = party_summary(now)
    local bound, status, run_id = session:reconcile(summary)
    if bound and (status == 'bound' or (status == 'stable'
        and engine.state.active_run_id ~= run_id)) then
        local changed, reason, rewind = engine:bind_run(run_id, summary, now)
        if changed then
            recovery_required = false
            clear_step_observations()
            persist(true)
            if rewind then
                chat(123, ('New expedition run bound; rewound to step %d because a run-scoped goal is still missing.')
                    :format(rewind))
            else
                chat(158, 'Fresh six-client expedition run bound.')
            end
        end
        return changed
    elseif status == 'binding_changed' or status == 'binding_lost'
        or status == 'leader_nonce_mismatch' then
        engine:unbind_run(now, true)
        recovery_required = true
        clear_step_observations()
        persist(true)
        chat(123, 'Expedition run identity changed unexpectedly; route authorization was cleared and paused.')
        return true
    end
    return false
end

-- An all-key-item prerequisite immediately followed by all_in_pack is an
-- entry transaction. Keep rechecking that prerequisite until the actual
-- instance transition so a stale pre-entry success cannot hide a regression.
local function entry_guard_key(step)
    local completion = step and step.completion or nil
    if completion and completion.kind == 'all_key_item' then
        local following = engine and engine.route.steps[
            engine.state.current_index + 1] or nil
        local next_completion = following and following.completion or nil
        return next_completion and next_completion.kind == 'all_in_pack'
            and completion.item or nil
    end
    if not completion or completion.kind ~= 'all_in_pack' or not engine then
        return nil
    end
    local previous = engine.route.steps[engine.state.current_index - 1]
    local prerequisite = previous and previous.completion or nil
    return prerequisite and prerequisite.kind == 'all_key_item'
        and prerequisite.item or nil
end

local function update_evidence(now)
    if not engine or not engine.state.active or engine.state.paused
        or engine.state.complete then return end
    local pack = current_pack()
    if pack and pack.instance_zones[current_zone()]
        and not engine.state.active_run_id then return end
    local summary = party_summary(now)
    if pack and pack.instance_zones[current_zone()]
        and (summary.run_quorum ~= true
            or summary.run_id ~= engine.state.active_run_id) then
        return
    end
    local step = engine:current()
    local menu = last_menu_evidence
    local menu_id = menu and menu.step_id == (step and step.id)
        and menu.landmark_id == current_waypoint_id(step)
        and tonumber(menu.zone) == current_zone()
        and tonumber(menu.at) and now - menu.at >= 0 and now - menu.at <= 3
        and menu.menu_id or nil
    local party_safe = summary.party_quorum and summary.leader_quorum
    if not party_safe then menu_id = nil end
    local evidence = {
        sensor_quorum=summary.sensor_quorum
            and party_safe
            and current_pack().instance_zones[current_zone()] == true,
        all_in_pack=summary.all_in_pack,
        all_key_items=party_safe and summary.all_key_items or {},
        all_items=party_safe and summary.all_items or {},
        menu_id=menu_id,
    }
    local changed, _, advanced = engine:observe(evidence, now)
    if not changed then
        local reconciled = engine:reconcile_forward(evidence, now)
        if reconciled then changed, advanced = true, true end
    end
    last_menu_evidence = nil
    if changed then
        persist(true)
        if advanced then
            clear_step_observations()
            local step = engine:current()
            chat(158, engine.state.complete and 'Route complete.'
                or ('Advanced to: ' .. tostring(step.instruction)))
        end
    end
end

local function update_navigation(clock_now)
    if not route_navigation_ready() then return end
    local step = engine:current()
    local local_report = current_local_report()
    if type(step.path) == 'table' then
        -- If Dolo cut a corner or improvised around a blocked hall, catch up
        -- to a nearby future point instead of pointing backward forever.
        for index = math.min(#step.path, engine.state.waypoint_index + 3),
            engine.state.waypoint_index + 1, -1 do
            local future = Navigation.resolve_landmark(step.path[index],
                current_landmarks(), current_navigation_overrides())
            local distance, dz = Navigation.distance(local_report, future)
            if distance and distance <= (future.radius or 5)
                and (future.z == nil or dz == nil
                    or math.abs(dz) <= (future.z_tolerance or 12)) then
                engine:set_waypoint_index(index)
                waypoint_tracker, cached_live_waypoint = {}, nil
                scan_current_waypoint()
                persist(true)
                break
            end
        end
    end
    local id = current_waypoint_id(step)
    local waypoint = cached_live_waypoint or Navigation.current_waypoint(
        step, engine.state.waypoint_index, current_landmarks(),
        current_navigation_overrides())
    if not waypoint then return end
    local arrived
    arrived, waypoint_tracker = Navigation.observe_waypoint(
        waypoint_tracker, local_report, waypoint, clock_now,
        settings.waypoint_dwell)
    if not arrived then return end
    if type(step.path) == 'table'
        and engine.state.waypoint_index < #step.path then
        engine:set_waypoint_index(engine.state.waypoint_index + 1)
        waypoint_tracker = {}
        cached_live_waypoint = nil
        scan_current_waypoint()
        persist(true)
    else
        local now = os.time()
        if step.completion and step.completion.kind == 'landmark' then
            local changed, _, advanced = engine:observe({landmark=id}, now)
            if changed then persist(true) end
            if advanced then
                clear_step_observations()
                local next_step = engine:current()
                chat(158, engine.state.complete and 'Route complete.'
                    or ('Advanced to: ' .. tostring(next_step.instruction)))
            end
        else
            engine:mark_observed('landmark',
                'arrived at ' .. waypoint.name, now, false)
        end
    end
end

local function format_time(now)
    if not engine or not engine.state.run_started_at then return '--:--' end
    local pack = current_pack()
    local remaining = math.max(0,
        pack.run_seconds - (now - engine.state.run_started_at))
    return ('%02d:%02d'):format(math.floor(remaining / 60), remaining % 60)
end

local function current_timer_spec()
    local step = engine and engine:current() or nil
    return step and step.timer or nil
end

local function route_timer_text(now)
    local spec = current_timer_spec()
    if not spec then return nil end
    local timer = engine:timer(spec.key)
    if not timer then
        return spec.label .. ' --:-- (starts on Dolos in-range interaction)'
    end
    local remaining = math.floor(engine:timer_remaining(spec.key, now) or 0)
    if remaining <= 0 then
        return spec.label .. ' EXPIRED - required result remains unconfirmed'
    end
    return ('%s %02d:%02d remaining'):format(spec.label,
        math.floor(remaining / 60), remaining % 60)
end

local function shortened(value, limit)
    value = tostring(value or '')
    if #value <= limit then return value end
    return value:sub(1, limit - 3) .. '...'
end

local function reward_line(now_wall, now_monotonic, summary, pack, step)
    if not reward_gate then
        return 'CHEST CHECK: sensor proof unavailable; operator decides'
    end
    local zone = current_zone()
    if not pack or not zone or pack.instance_zones[zone] ~= true then
        reward_gate:reset('outside expedition instance')
        return 'REWARD: NOT APPLICABLE - outside expedition instance'
    end
    local session = current_run_session()
    local run_bound = session and session.bound_run_id
        and engine and engine.state.active_run_id == session.bound_run_id
    if not run_bound then
        reward_gate:reset('run unbound')
        return 'CHEST CHECK: run unbound; confirm party position manually'
    end
    if not step or type(step.reward) ~= 'table' then
        reward_gate:reset('no declared reward')
        return 'CHEST CHECK: no declared route reward on this step'
    end
    if not engine.state.active or engine.state.paused or engine.state.complete
        or recovery_required then
        reward_gate:reset('route is not active')
        return ('CHEST CHECK: %s - route is not active')
            :format(tostring(step.reward.label or 'reward'))
    end
    local scopes = current_reward_scopes()
    local scope = scopes and scopes[step.reward.scope] or nil
    local state = current_party_state()
    local status = reward_gate:observe({
        pack_id=pack.id,
        catalog_id=pack.catalog_id,
        route_id=engine.route.id,
        route_digest=pack.route_digests[engine.route.id],
        step_id=step.id,
        scope_id=step.reward.scope,
        scope=scope,
        roster=ROSTER,
        expected_leader=settings.leader,
        zone=zone,
        run_id=summary.run_id,
        run_cohort=summary.run_cohort,
        session_run_id=session.bound_run_id,
        session_cohort=session.bound_cohort,
        engine_run_id=engine.state.active_run_id,
        now_wall=now_wall,
        entry_nonces=summary.entry_nonces,
    }, state and state.reports or nil, now_monotonic)
    local label = tostring(step.reward.label or 'reward')
    local scope_label = type(scope) == 'table'
        and tostring(scope.label or step.reward.scope):upper()
        or tostring(step.reward.scope or 'unknown scope'):upper()
    if status.safe then
        return ('CHEST READY: 6/6 in %s, stable 2/2 - %s')
            :format(scope_label, label)
    end
    local reason_parts = {}
    for _, failure in ipairs(type(status.failures) == 'table'
        and status.failures or {}) do
        local part = tostring(failure.reason or 'not safe'):gsub('_', ' ')
        if type(failure.names) == 'table' and #failure.names > 0 then
            part = part .. ' [' .. table.concat(failure.names, ',') .. ']'
        end
        reason_parts[#reason_parts + 1] = part
    end
    local reason = #reason_parts > 0 and table.concat(reason_parts, '; ')
        or tostring(status.reason or 'not safe'):gsub('_', ' ')
    if #reason_parts == 0 and type(status.missing) == 'table'
        and #status.missing > 0 then
        reason = reason .. ' [' .. table.concat(status.missing, ',') .. ']'
    end
    return ('CHEST RISK: %s - %s (scope %s, %d/2)'):format(
        label, reason, scope_label, tonumber(status.progress) or 0)
end

local function navigation_model(step)
    local id = current_waypoint_id(step)
    if not id then return nil end
    local landmark = current_landmarks()[id]
    local waypoint = cached_live_waypoint or Navigation.resolve_landmark(
        id, current_landmarks(), current_navigation_overrides())
    local model = {
        available=false,
        id=id,
        name=waypoint and waypoint.name or landmark and landmark.name or id,
        cue=waypoint and waypoint.cue ~= '' and waypoint.cue
            or landmark and landmark.cue or '',
        point_index=engine.state.waypoint_index,
        point_count=type(step.path) == 'table' and #step.path or 1,
    }
    local local_report = current_local_report()
    if not local_report or local_report.ready ~= true then
        local mob = windower.ffxi.get_mob_by_target('me')
        if mob and tonumber(mob.x) and tonumber(mob.y) then
            local_report = {
                ready=true,zone=current_zone(),x=mob.x,y=mob.y,z=mob.z,
                facing=mob.facing,
            }
        end
    end
    local ready = route_navigation_ready()
    if not ready or not waypoint or not local_report
        or local_report.ready ~= true then return model end
    local distance, dz = Navigation.distance(local_report, waypoint)
    local relative = Navigation.relative_heading(local_report, waypoint,
        local_report.facing)
    local glyph, word = Navigation.arrow(relative or 0)
    model.available = distance ~= nil and relative ~= nil
    model.distance = distance
    model.dz = dz
    model.relative = relative
    model.glyph = glyph
    model.word = word
    model.frame = Navigation.frame(relative or 0,
        tonumber(settings.arrow and settings.arrow.frame_count) or 32)
    return model
end

local function navigation_text(model)
    if not model then return nil end
    local suffix = tonumber(model.point_count) and model.point_count > 1
        and (' | point %d/%d'):format(
            tonumber(model.point_index) or 1, model.point_count) or ''
    if model.available ~= true then
        return ('DIR -- | %s%s%s'):format(
            tostring(model.name), suffix,
            model.cue ~= '' and (' | ' .. tostring(model.cue)) or '')
    end
    return ('DIR %s %-11s | %5.1fy | dz %+5.1f | %s%s%s'):format(
        model.glyph, model.word, model.distance or 0, model.dz or 0,
        model.name, suffix,
        model.cue ~= '' and (' | ' .. tostring(model.cue)) or '')
end

local function render()
    if not hud or not settings or not engine then return end
    local now = os.time()
    local summary = party_summary(now)
    local pack = current_pack()
    local step = engine:current()
    local state = engine.state.complete and 'COMPLETE'
        or recovery_required and 'RECOVERY REQUIRED'
        or engine.state.paused and 'PAUSED'
        or engine.state.active and 'ACTIVE' or 'NOT STARTED'
    local active_bridge = current_bridge()
    local combat_state, combat_note = active_bridge:describe(
        step and step.profile, step and step.profile_arm == true)
    local warning = step and step.warning or ''
    local timer_spec = current_timer_spec()
    local timer_remaining = timer_spec
        and engine:timer_remaining(timer_spec.key, now) or nil
    local reward = reward_line(now, os.clock(), summary, pack, step)
    if timer_spec and timer_remaining == 0 then
        warning = timer_spec.label
            .. ' WINDOW EXPIRED. The addon will not claim success. ' .. warning
    end
    local guarded_key = entry_guard_key(step)
    local entry_guard_active = guarded_key ~= nil
        and pack.instance_zones[current_zone()] ~= true
    if pack.instance_zones[current_zone()]
        and not engine.state.active_run_id then
        warning = 'SENSORS UNBOUND: automatic party evidence is unavailable. The route, arrow, //exg next, and all manual play remain available. '
            .. warning
    elseif entry_guard_active and not summary.sensor_quorum then
        warning = ('ENTRY CHECK: same-zone ready sensors %d/%d. You may continue manually. %s'):format(
            summary.same_zone, summary.expected, warning)
    elseif entry_guard_active
        and (not summary.party_quorum or not summary.leader_quorum) then
        warning = ('ENTRY CHECK: PARTY %d/%d, DOLO LEADER %d/%d. Verify the party; entry remains your decision. %s')
            :format(summary.party_exact, summary.expected,
                summary.leader_exact, summary.leader_expected, warning)
    elseif pack.instance_zones[current_zone()]
        and (not summary.sensor_quorum or not summary.party_quorum
            or not summary.leader_quorum) then
        local problems = {}
        if #summary.stale_clients > 0 then
            problems[#problems + 1] = 'missing/stale '
                .. table.concat(summary.stale_clients, ',')
        end
        if #summary.unready_clients > 0 then
            problems[#problems + 1] = 'still loading '
                .. table.concat(summary.unready_clients, ',')
        end
        if #summary.other_zone_clients > 0 then
            problems[#problems + 1] = 'other zone '
                .. table.concat(summary.other_zone_clients, ',')
        end
        if #summary.party_mismatch_clients > 0 then
            problems[#problems + 1] = 'party mismatch '
                .. table.concat(summary.party_mismatch_clients, ',')
        end
        if #summary.leader_mismatch_clients > 0 then
            problems[#problems + 1] = 'Dolo not leader '
                .. table.concat(summary.leader_mismatch_clients, ',')
        end
        warning = ('CHEST RISK: sensors %d/%d, party %d/%d, leader %d/%d (%s). Manual actions remain available. %s')
            :format(summary.same_zone, summary.expected,
                summary.party_exact, summary.expected,
                summary.leader_exact, summary.leader_expected,
                table.concat(problems, '; '), warning)
    elseif entry_guard_active
        and summary.fresh == summary.expected then
        local count = summary.key_item_counts[guarded_key] or 0
        local item = pack.key_items.by_key[guarded_key]
        local diagnostic, spec, groups = diagnostic_for_item(
            pack, summary, guarded_key)
        local diagnostic_blocked = spec and groups
            and (#groups[spec.primary_label] ~= summary.expected
                or #groups[spec.secondary_label] > 0
                or #groups[spec.missing_label] > 0
                or #groups[spec.invalid_label] > 0
                or #groups[spec.unknown_label] > 0)
        if count < summary.expected or diagnostic_blocked then
            warning = diagnostic
                and ('ENTRY CHECK: %s. Continue or override manually as needed. %s'):format(diagnostic, warning)
                or ('ENTRY CHECK: %s %d/%d. Continue or override manually as needed. %s'):format(
                    item and item.name:upper() or tostring(guarded_key):upper(),
                    count, summary.expected, warning)
        end
    end
    local navigation = step and navigation_model(step) or nil
    hud:render({
        visible=settings.visible ~= false,
        version=_addon.version,
        mode=engine.route.guide_only and 'GUIDE ONLY' or 'LIVE',
        route=engine.route.title,
        step_index=engine.state.current_index,
        step_count=#engine.route.steps,
        step_id=step and step.id or '--',
        area=step and step.area or '--',
        time=format_time(now),
        fresh=summary.fresh,
        party_exact=summary.party_exact,
        leader_exact=summary.leader_exact,
        leader_expected=summary.leader_expected,
        expected=summary.expected,
        state=state,
        navigation=navigation_text(navigation),
        timer=route_timer_text(now),
        reward=reward,
        instruction=step and step.instruction or 'No route step.',
        detail=step and step.detail or nil,
        warning=warning,
        combat=(combat_state == 'none' and 'OFF / travel'
            or (combat_state:upper() .. ' - ' .. combat_note)),
        observed=engine.state.observed
            and shortened(engine.state.observed.note, 100) or nil,
        next_step=engine:next_step()
            and shortened(engine:next_step().instruction, 92) or nil,
    })
    if arrow then
        navigation = navigation or {}
        navigation.available = settings.visible ~= false
            and navigation.available == true
            and engine.state.active and not engine.state.paused
            and not engine.state.complete
        arrow:render(navigation)
    end
end

local function leader_required()
    if not is_leader() then
        chat(123, 'Route controls are leader-only; this client is a sensor.')
        return false
    end
    return true
end

local function start_route(value)
    if not leader_required() then return end
    local route = resolve_route(value ~= '' and value or 'onboarding')
    if not route then
        chat(123, 'Unknown route. Use //exg list.')
        return
    end
    make_engine(route, nil)
    for _, bridge in pairs(bridges) do bridge:reset() end
    if automation_bridge then automation_bridge:reset() end
    engine:start(os.time())
    local pack = current_pack()
    local session = current_run_session()
    if pack and pack.instance_zones[current_zone()] then
        local bound = session and session.bound_run_id
            and engine:bind_run(session.bound_run_id,
                party_summary(os.time()), os.time())
        recovery_required = not bound
    else
        recovery_required = false
    end
    navigation_overrides = navigation_overrides or {}
    clear_step_observations()
    persist(true)
    render()
    chat(158, ('Started %s v%s (%s).'):format(route.id, route.version,
        route.guide_only and 'GUIDE ONLY; do not enter yet' or 'live'))
end

local function find_step(value)
    if not engine then return nil, nil end
    if value == nil or tostring(value) == '' then
        return engine:current(), engine.state.current_index
    end
    local index = tonumber(value)
    if index then
        index = math.floor(index)
        return engine.route.steps[index], index
    end
    value = tostring(value):lower()
    for candidate_index, step in ipairs(engine.route.steps) do
        if step.id == value then return step, candidate_index end
    end
    return nil, nil
end

local function explain(value)
    local step, index = find_step(value)
    if not step then
        chat(123, 'Unknown step. Use //exg steps.')
        return
    end
    chat(207, ('Step %d/%d %s: %s'):format(index,
        #engine.route.steps, step.id, step.instruction))
    if step.warning then chat(123, 'Warning: ' .. step.warning) end
    for _, line in ipairs(step.detail or {}) do chat(207, '  ' .. line) end
    local completion = step.completion or {}
    chat(207, 'Completion evidence: ' .. tostring(completion.kind))
end

local function list_steps()
    if not engine then return end
    chat(207, engine.route.title .. ' steps:')
    for index, step in ipairs(engine.route.steps) do
        local marker = index == engine.state.current_index and '>' or ' '
        chat(207, ('%s %02d %-8s %s'):format(marker, index, step.area, step.id))
    end
    chat(207, 'Read any step without changing state: //exg explain <number|id>')
end

local function list_routes()
    chat(207, 'Available routes:')
    local ids = {}
    for id in pairs(content.routes) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local route = content.routes[id]
        chat(207, ('  %s v%s - %s%s'):format(id, route.version, route.title,
            route.guide_only and ' [GUIDE ONLY]' or ''))
    end
end

local function parse_remaining(value)
    value = tostring(value or '')
    local minutes, seconds = value:match('^(%d+):(%d%d)$')
    if not minutes then minutes, seconds = value:match('^(%d+)$'), '00' end
    local total = tonumber(minutes) and tonumber(seconds)
        and tonumber(minutes) * 60 + tonumber(seconds) or nil
    local pack = current_pack()
    if not total or not pack or total < 0
        or total > pack.run_seconds then return nil end
    return total
end

local function handle_command(command, ...)
    if not initialize() then chat(123, 'Not logged in yet.'); return end
    command = tostring(command or 'status'):lower()
    local args = {...}
    if command == 'start' or command == 'route' then
        start_route(tostring(args[1] or ''))
    elseif command == 'list' then
        list_routes()
    elseif command == 'next' then
        if not leader_required() then return end
        local confirmed = engine:can_advance()
        local ok, reason
        if confirmed then
            ok, reason = engine:advance(
                'operator next', 'manual', os.time())
        else
            ok, reason = engine:skip(os.time())
        end
        if not ok then chat(123, reason) else
            if not confirmed then
                chat(123, 'Advanced by operator override; missing sensor evidence was not recorded as confirmed.')
            end
            clear_step_observations(); persist(true); render()
        end
    elseif command == 'skip' then
        if not leader_required() then return end
        local ok, reason = engine:skip(os.time())
        if not ok then chat(123, reason) else
            clear_step_observations(); persist(true); render()
        end
    elseif command == 'back' then
        if not leader_required() then return end
        local ok, reason = engine:back(os.time())
        if not ok then chat(123, reason) else
            clear_step_observations(); persist(true); render()
        end
    elseif command == 'wp' or command == 'waypoint' then
        if not leader_required() then return end
        local step = engine:current()
        if type(step.path) ~= 'table' or #step.path <= 1 then
            chat(123, 'The current step has no multi-point arrow path.')
            return
        end
        if engine.state.waypoint_index >= #step.path then
            chat(123, 'Already at the final arrow point; use //exg next to advance the step.')
            return
        end
        engine:set_waypoint_index(engine.state.waypoint_index + 1)
        waypoint_tracker, cached_live_waypoint = {}, nil
        scan_current_waypoint()
        persist(true); render()
        chat(158, ('Arrow advanced to point %d/%d.'):format(
            engine.state.waypoint_index, #step.path))
    elseif command == 'pause' then
        if not leader_required() then return end
        local ok, reason = engine:set_paused(true, os.time())
        if not ok then chat(123, reason) else
            clear_step_observations('route paused')
            persist(true); render()
        end
    elseif command == 'resume' then
        if not leader_required() then return end
        local pack = current_pack()
        if pack and pack.instance_zones[current_zone()] then
            reconcile_run_binding(os.time())
        end
        local session = current_run_session()
        if not engine.state.active then engine:start(os.time()) end
        clear_step_observations()
        engine:set_paused(false, os.time())
        recovery_required = pack and pack.instance_zones[current_zone()]
            and (not session or not session.bound_run_id
                or engine.state.active_run_id ~= session.bound_run_id) or false
        persist(true); render()
        if recovery_required then
            chat(123, 'Guide resumed without sensor binding. Arrow and manual advancement are active; automatic evidence remains advisory/unavailable.')
        end
    elseif command == 'explain' or command == 'why' then
        explain(args[1])
    elseif command == 'steps' or command == 'outline' then
        list_steps()
    elseif command == 'resync' then
        if reward_gate then reward_gate:reset('sensor resync') end
        for _, state in pairs(party_states) do state.reports = {} end
        capture_local(os.time())
        render()
        chat(158, 'Sensor evidence cleared; waiting for fresh periodic reports.')
    elseif command == 'time' then
        if not leader_required() then return end
        local remaining = parse_remaining(args[1])
        local pack = current_pack()
        if not remaining then
            local maximum = pack and math.floor(pack.run_seconds / 60) or 0
            chat(123, ('Usage: //exg time MM:SS (00:00 to %d:00)'):format(maximum))
            return
        end
        local changed, reason = engine:set_run_started_at(
            os.time() - (pack.run_seconds - remaining))
        if not changed then chat(123, reason) else persist(true); render() end
    elseif (command == 'timer' or command == 'dgate')
        and tostring(args[1] or ''):lower() == 'reset' then
        if not leader_required() then return end
        local spec = current_timer_spec()
        if not spec then
            chat(123, 'The current route step has no resettable timer.')
            return
        end
        engine:clear_timer(spec.key)
        persist(true); render()
        chat(158, spec.label
            .. ' attempt timer cleared; the next in-range Dolo interaction starts it.')
    elseif command == 'mark' or command == 'calibrate' then
        if not leader_required() then return end
        if not route_zone_ready() then
            chat(123, 'Calibration requires an active, unpaused route and a ready local sensor inside the active expedition instance.')
            return
        end
        local step = engine:current()
        local id = tostring(args[1] or current_waypoint_id(step) or '')
        local me = windower.ffxi.get_mob_by_target('me')
        local landmarks = current_landmarks()
        if id == '' or not landmarks[id] or not me then
            chat(123, 'No valid current waypoint to calibrate.')
            return
        end
        if calibrate(id, {name=landmarks[id].name,
            x=me.x, y=me.y, z=me.z}, 'operator_position') then
            chat(158, 'Calibrated ' .. id .. ' at your current position.')
        else
            chat(123, 'Calibration was rejected because the position was invalid or unchanged.')
        end
    elseif command == 'profile' or command == 'combat' then
        if not leader_required() then return end
        local step = engine and engine:current() or nil
        if not step or not step.profile then
            chat(123, 'The current step has no PartyTactics profile to load.')
            return
        end
        local bridge = current_bridge()
        local ok, result
        if bridge then
            ok, result = bridge:request_operator(
                step.profile, step.profile_arm == true)
        else
            ok, result = false, 'profile bridge unavailable'
        end
        if not ok then
            chat(123, 'Profile was not loaded: ' .. tostring(result))
            return
        end
        render()
        chat(158, ('Recovery request sent: %s. Alt-P disarms immediately; automatic lifecycle does not repeatedly override it.')
            :format(result:gsub('^lua i PartyTactics ','//pt ')))
    elseif command == 'show' then
        if not leader_required() then return end
        settings.visible = true; config.save(settings); render()
    elseif command == 'hide' then
        if not leader_required() then return end
        settings.visible = false; config.save(settings); render()
    elseif command == 'arrow' then
        if not leader_required() then return end
        local value = tostring(args[1] or ''):lower()
        if value ~= 'on' and value ~= 'off' then
            chat(123, 'Usage: //exg arrow <on|off>')
            return
        end
        settings.arrow.visible = value == 'on'
        config.save(settings); render()
    elseif command == 'arrowpos' then
        if not leader_required() then return end
        local x, y = tonumber(args[1]), tonumber(args[2])
        if not x or not y then
            chat(123, 'Usage: //exg arrowpos <x> <y>')
            return
        end
        if arrow and arrow:pos(x, y) then
            config.save(settings); render()
        end
    elseif command == 'pos' then
        if not leader_required() then return end
        local x, y = tonumber(args[1]), tonumber(args[2])
        if not x or not y then chat(123, 'Usage: //exg pos <x> <y>'); return end
        settings.display.pos.x, settings.display.pos.y = x, y
        hud:pos(x, y); config.save(settings)
    elseif command == 'stop' or command == 'panic' then
        if not leader_required() then return end
        current_bridge():emergency_stop()
        if automation_bridge then automation_bridge:reset() end
        if reward_gate then reward_gate:reset('emergency stop') end
        if engine.state.active then engine:set_paused(true, os.time()) end
        persist(true); render()
        chat(123, 'PartyTactics stopped and route paused. Alt-P remains the universal combat stop.')
    elseif command == 'reset' and tostring(args[1] or ''):lower() == 'confirm' then
        if not leader_required() then return end
        engine:reset(os.time())
        for _, bridge in pairs(bridges) do bridge:reset() end
        if automation_bridge then automation_bridge:reset() end
        local session = current_run_session()
        if session and session.bound_run_id then
            local bound = engine:bind_run(session.bound_run_id,
                party_summary(os.time()), os.time())
            recovery_required = not bound
            if not bound then engine:set_paused(true, os.time()) end
        else
            recovery_required = current_pack().instance_zones[current_zone()] == true
        end
        clear_step_observations()
        persist(true); render(); chat(158, 'Current route state reset.')
    elseif command == 'debug' then
        debug_enabled = tostring(args[1] or ''):lower() == 'on'
            or (args[1] == nil and not debug_enabled)
        chat(207, 'Debug ' .. (debug_enabled and 'on.' or 'off.'))
    elseif command == 'status' then
        local summary = party_summary(os.time())
        chat(207, ('v%s | %s | %s | step %d/%d | sensors %d/%d | party %d/%d | Dolo leader %d/%d | zone %s')
            :format(_addon.version, is_leader() and 'leader' or 'sensor',
                engine and active_route_id or 'no route',
                engine and engine.state.current_index or 0,
                engine and #engine.route.steps or 0,
                summary.fresh, summary.expected,
                summary.party_exact, summary.expected,
                summary.leader_exact, summary.leader_expected,
                tostring(current_zone())))
        if is_leader() then
            local counts = {}
            local pack = current_pack()
            for _, item in ipairs(pack.key_items.ordered) do
                counts[#counts + 1] = ('%s %d/%d'):format(item.name,
                    summary.key_item_counts[item.key] or 0, summary.expected)
            end
            chat(207, table.concat(counts, ' | ') .. ' | profile handoff '
                .. (settings.automatic_profile_requests and 'AUTO' or 'MANUAL')
                .. ' | route actions '
                .. (settings.automatic_route_actions and 'AUTO' or 'MANUAL')
                .. ' | //exg profile is recovery-only')
            local diagnostics = pack.key_items.diagnostics
            if type(diagnostics) == 'table' then
                local ids = {}
                for id in pairs(diagnostics) do ids[#ids + 1] = id end
                table.sort(ids)
                for _, id in ipairs(ids) do
                    local line = format_key_item_diagnostic(pack, summary, id)
                    if line then chat(207, line) end
                end
            end
        end
    else
        chat(207, 'Commands: start <route> | list | steps | next | back | skip | wp | pause | resume | explain [step]')
        chat(207, '          resync | time MM:SS | timer reset | mark [landmark] | profile | show | hide | pos X Y | arrow on|off | arrowpos X Y | status | stop')
        chat(207, 'Reset requires: //exg reset confirm')
    end
end

local function observe_menu(original, modified)
    local zone_ready, zone = route_zone_ready()
    if not is_leader() or not zone_ready then return end
    local step = engine:current()
    local completion = step and step.completion or nil
    local landmark_id = current_waypoint_id(step)
    local landmark = landmark_id and current_landmarks()[landmark_id] or nil
    if not completion or completion.kind ~= 'interaction'
        or type(landmark) ~= 'table' then return end

    local candidates = {modified, original}
    for index = 1, 2 do
        local candidate = candidates[index]
        if type(candidate) == 'string' and #candidate > 0 then
            local ok, parsed = pcall(packets.parse, 'incoming', candidate)
            local menu_id = ok and parsed and tonumber(parsed['Menu ID']) or nil
            local npc_id = ok and parsed and tonumber(parsed.NPC) or nil
            local npc_index = ok and parsed
                and tonumber(parsed['NPC Index']) or nil
            local packet_zone = ok and parsed and tonumber(parsed.Zone) or nil
            if menu_id == tonumber(completion.menu_id) and npc_id and npc_index
                and packet_zone == zone
                and (not landmark.entity_index
                    or tonumber(landmark.entity_index) == npc_index) then
                local mob = windower.ffxi.get_mob_by_id
                    and windower.ffxi.get_mob_by_id(npc_id) or nil
                if not mob and windower.ffxi.get_mob_by_index then
                    mob = windower.ffxi.get_mob_by_index(npc_index)
                end
                if mob and tonumber(mob.id) == npc_id
                    and tonumber(mob.index) == npc_index
                    and Sensors.matches_landmark(mob, landmark) then
                    last_menu_evidence = {
                        menu_id=menu_id,
                        target_id=npc_id,
                        target_index=npc_index,
                        landmark_id=landmark_id,
                        zone=zone,
                        step_id=step.id,
                        at=os.time(),
                    }
                    return
                end
            end
        end
    end
end

local function parse_relevant_outgoing(original, modified)
    local seen = {}
    local candidates = {modified, original}
    for index = 1, 2 do
        local raw = candidates[index]
        if type(raw) == 'string' and #raw > 0 and not seen[raw] then
            seen[raw] = true
            local ok, parsed = pcall(packets.parse, 'outgoing', raw)
            if ok and parsed and tonumber(parsed.Category) == 0
                and tonumber(parsed.Target) then
                return parsed
            end
        end
    end
    return nil
end

local function observe_interaction(original, modified, blocked)
    if not is_leader() or not route_navigation_ready() or blocked then return end
    local packet = parse_relevant_outgoing(original, modified)
    if not packet then return end
    local target_id = tonumber(packet.Target)
    local mob = target_id and windower.ffxi.get_mob_by_id
        and windower.ffxi.get_mob_by_id(target_id) or nil
    local target_index = tonumber(packet['Target Index'])
        or tonumber(mob and mob.index)
    if not target_index then return end
    if not mob and windower.ffxi.get_mob_by_index then
        mob = windower.ffxi.get_mob_by_index(target_index)
    end

    local step = engine:current()
    local completion = step and step.completion or nil
    if completion and completion.kind == 'target_interaction' then
        local landmark_id = completion.landmark
        local landmark = landmark_id and current_landmarks()[landmark_id] or nil
        local identity_matches = landmark
            and (not landmark.entity_index
                or tonumber(landmark.entity_index) == target_index)
            and mob and tonumber(mob.id) == target_id
            and tonumber(mob.index) == target_index
            and Sensors.matches_landmark(mob, landmark)
        local distance = tonumber(mob and mob.distance)
        if distance then distance = math.sqrt(math.max(0, distance)) end
        if identity_matches and (not distance or distance <= 8) then
            local changed, _, advanced = engine:observe({
                interaction_landmark=landmark_id,
            }, os.time())
            if changed then persist(true) end
            if advanced then
                clear_step_observations()
                local next_step = engine:current()
                chat(158, engine.state.complete and 'Route complete.'
                    or ('Advanced after your interaction: '
                        .. tostring(next_step.instruction)))
                render()
            end
            return
        end
    end
    local spec = step and step.timer or nil
    if not spec or spec.kind ~= 'interaction_pair' then return end
    local accepted = false
    for _, entity_index in ipairs(spec.entity_indices) do
        if target_index == entity_index then accepted = true; break end
    end
    if not accepted or not mob or tonumber(mob.id) ~= target_id
        or tonumber(mob.index) ~= target_index then return end
    local expected_landmark = nil
    for _, landmark in pairs(current_landmarks()) do
        if tonumber(landmark.entity_index) == target_index then
            expected_landmark = landmark
            break
        end
    end
    if not expected_landmark
        or not Sensors.matches_landmark(mob, expected_landmark) then return end
    local distance = tonumber(mob.distance)
    if distance then
        distance = math.sqrt(math.max(0, distance))
    else
        local me = windower.ffxi.get_mob_by_target('me')
        distance = Navigation.distance(me, mob)
    end
    if not distance or distance > spec.max_distance then
        debug('ignored out-of-range timed interaction attempt')
        return
    end
    local now = os.time()
    local timer = engine:timer(spec.key)
    if not timer then
        engine:start_timer(spec.key, spec.duration, now)
        timer = engine:timer(spec.key)
        timer.first_index = target_index
        chat(123, ('%s interaction timer started: %d seconds; the required result remains the proof.')
            :format(spec.label, spec.duration))
    elseif timer.first_index ~= target_index and not timer.second_index then
        timer.second_index = target_index
        timer.second_at = now
        if engine:timer_remaining(spec.key, now) > 0 then
            chat(158, 'Second timed interaction observed; waiting for confirmed result evidence.')
        else
            chat(123, 'Second timed interaction was late; required result remains unconfirmed.')
        end
    end
    persist(true)
end

windower.register_event('load', function()
    if initialize() then capture_local(os.time()); render() end
end)

windower.register_event('login', function()
    coroutine.schedule(function()
        if initialize() then capture_local(os.time()); render() end
    end, 1)
end)

windower.register_event('logout', function()
    persist(true)
    if hud then hud:destroy() end
    if arrow then arrow:destroy() end
    hud, arrow, settings, settings_character = nil, nil, nil, nil
    party_states, bridges, run_sessions, engine = {}, {}, {}, nil
    automation_bridge = nil
    active_route_id, state_path = nil, nil
    navigation_overrides = {}
    clear_step_observations()
    reward_gate = nil
    last_local_reports = {}
end)

windower.register_event('unload', function()
    persist(true)
    if reward_gate then reward_gate:reset('addon unload') end
    if hud then hud:destroy() end
    if arrow then arrow:destroy() end
end)

windower.register_event('zone change', function(new_zone, old_zone)
    if not initialize() then return end
    new_zone, old_zone = tonumber(new_zone), tonumber(old_zone)
    clear_step_observations()
    last_local_reports = {}
    local now = os.time()
    local transitions = {}
    for _, id in ipairs(pack_ids) do
        transitions[id] = run_sessions[id]
            and run_sessions[id]:observe_zone(new_zone, old_zone, now) or nil
    end
    local pack = current_pack()
    local transition = pack and transitions[pack.id] or nil
    if is_leader() and engine and engine.route.auto_start == true
        and transition == 'entered'
        and (not engine.state.active or engine.state.complete) then
        local route = engine.route
        make_engine(route, nil)
        engine:start(now)
        for _, bridge in pairs(bridges) do bridge:reset() end
        if automation_bridge then automation_bridge:reset() end
        recovery_required = false
        chat(158, ('New Sortie detected; %s restarted automatically.')
            :format(route.title))
    end
    if is_leader() and engine and engine.state.active
        and (transition == 'entered' or transition == 'exited'
            or transition == 'ambiguous_instance_change'
            or transition == 'invalid_entry_nonce') then
        engine:unbind_run(now, false)
        recovery_required = true
    end
    persist(true)
    coroutine.schedule(function() capture_local(os.time()); render() end, 1)
end)

windower.register_event('incoming chunk', function(id, original, modified)
    if id == 0x032 or id == 0x033 or id == 0x034 then
        observe_menu(original, modified)
    end
end)

windower.register_event('outgoing chunk', function(id, original, modified,
    injected, blocked)
    if id == 0x01A then observe_interaction(original, modified, blocked) end
end)

windower.register_event('ipc message', function(message)
    if not settings or not Protocol.is_ours(message) then return end
    local report, reason = Protocol.validate(message, {
        now=os.time(), max_age=tonumber(settings.peer_max_age) or 8,
        catalogs=content.packs,
        allowed_sender=function(name)
            local state = party_states[pack_ids[1]]
            return state and state:allowed_sender(name) or false
        end,
    })
    if not report then debug('rejected IPC: ' .. tostring(reason)); return end
    local state = party_states[report.pack_id]
    if state then state:update(report, os.clock()) end
end)

windower.register_event('prerender', function()
    local clock_now = os.clock()
    if clock_now - last_sensor_at >= (tonumber(settings and settings.sensor_interval) or 1) then
        last_sensor_at = clock_now
        local before = current_local_report()
        local report = capture_local(os.time())
        if is_leader() and before and before.ready == true
            and report and report.ready == true then
            local distance, dz = Navigation.distance(before, report)
            if distance and (distance >= 45 or math.abs(dz or 0) >= 45) then
                waypoint_tracker, cached_live_waypoint = {}, nil
                if reward_gate then reward_gate:reset('large relocation') end
                debug(('large relocation observed: planar %.1f yalms, dz %.1f')
                    :format(distance, dz or 0))
                local step = engine and engine:current() or nil
                if engine and step and step.completion
                    and step.completion.kind == 'relocation' then
                    local changed, _, advanced = engine:observe({
                        relocation=true,
                    }, os.time())
                    if changed then persist(true) end
                    if advanced then
                        clear_step_observations()
                        local next_step = engine:current()
                        chat(158, engine.state.complete and 'Route complete.'
                            or ('Warp arrival confirmed. Current step: '
                                .. tostring(next_step.instruction)))
                    end
                end
            end
        end
        if is_leader() then
            reconcile_run_binding(os.time())
            update_evidence(os.time())
        end
    end
    if is_leader() and clock_now - last_entity_scan_at
        >= (tonumber(settings.entity_scan_interval) or 0.75) then
        last_entity_scan_at = clock_now
        scan_current_waypoint()
    end
    if is_leader() then update_navigation(clock_now) end
    if is_leader() then reconcile_route_lifecycle() end
    if is_leader() and clock_now - last_render_at
        >= (tonumber(settings.render_interval) or 0.10) then
        last_render_at = clock_now
        render()
        persist(false)
    end
end)

windower.register_event('addon command', handle_command)
