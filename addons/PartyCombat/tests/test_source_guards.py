from pathlib import Path


SOURCE = (Path(__file__).parents[1] / "PartyCombat.lua").read_text(
    encoding="utf-8"
)
SETTINGS = (Path(__file__).parents[1] / "data" / "settings.lua").read_text(
    encoding="utf-8"
)


def test_addon_starts_inert():
    assert "local armed = false" in SOURCE
    assert "local authorized = false" in SOURCE
    assert "loadfile(" in SOURCE
    assert "data/settings.lua" in SOURCE
    assert "require('config')" not in SOURCE
    assert "puller = 'Tackleberry'" in SOURCE
    assert "puller = 'Tackleberry'" in SETTINGS


def test_damage_actions_and_scoped_puller_flash_drive_targets():
    assert "action.category == 1" in SOURCE
    assert "action.category == 2" in SOURCE
    assert "action.category == 3" in SOURCE
    assert "message.color == 'D'" in SOURCE
    assert "local PULL_FLASH_SPELL_ID = 112" in SOURCE
    assert "action.param == PULL_FLASH_SPELL_ID" in SOURCE
    assert "local target = damage_target(action, puller_authority)" in SOURCE
    assert "if physical or puller_flash then return target end" in SOURCE


def test_distance_limits_are_separate():
    assert "auto_distance = 10" in SOURCE
    assert "force_distance = 30" in SOURCE
    assert "force and attacker.force_distance or attacker.auto_distance" in SOURCE


def test_combat_authority_is_explicit():
    for name in (
        "Tackleberry", "Kickpuncher", "Barneystinson", "Smalls", "Achoo"
    ):
        assert f"{name} = {{" in SOURCE
        assert f"{name} = {{" in SETTINGS
    assert "broadcast_authority(true)" in SOURCE
    assert "broadcast_authority(false)" in SOURCE
    assert "local directed_split_mode = mode == 'forcesubset'" in SOURCE
    assert "not is_targeter() and not (directed_split_mode and is_attacker())" in SOURCE


def test_authorized_puller_can_establish_but_not_replace_live_target():
    action = SOURCE.split("windower.register_event('action'", 1)[1]
    action = action.split("windower.register_event('ipc message'", 1)[0]
    assert "local puller_authority = (authorized or armed) and is_puller()" in action
    assert "local leader_authority = armed and is_leader()" in action
    assert "active_target_id ~= target.id" in action
    assert "if valid_enemy(active) then return end" in action
    assert "accept_target(target.id, 'auto')" in action
    assert action.index("accept_target(target.id, 'auto')") < action.index(
        "send_ipc('target', target.id, 'auto')"
    )


def test_runtime_policy_is_validated_and_loaded_inert():
    policy = SOURCE.split("local function apply_runtime_policy", 1)[1]
    policy = policy.split("local function damage_target", 1)[0]
    assert "valid_policy_name(policy_name)" in policy
    assert "valid_name(leader)" in policy
    assert "valid_name(puller)" in policy
    assert "same_attacker_roster(settings, normalized)" in policy
    assert "armed = false" in policy
    assert "settings = {" in policy
    assert "puller = puller" in policy
    assert "Policy %s loaded inert" in policy
    assert "elseif command == 'policy' then" in SOURCE


def test_support_readiness_interlock_blocks_stale_combat():
    assert "local runtime_policy_ready = false" in SOURCE
    arm = SOURCE.split("local function arm()", 1)[1].split(
        "local function force_current_target", 1
    )[0]
    assert "if not runtime_policy_ready then" in arm
    assert "return false" in arm
    policy = SOURCE.split("local function apply_runtime_policy", 1)[1].split(
        "local function damage_target", 1
    )[0]
    assert policy.count("runtime_policy_ready = true") == 2
    assert "local function invalidate_runtime_policy" in SOURCE
    assert "runtime_policy_ready = false" in SOURCE
    assert "elseif command == 'invalidate' then" in SOURCE
    assert "source ~= 'partystart' and source ~= 'partytactics'" in SOURCE
    assert "support-ready %s" in SOURCE
    authority = SOURCE.split("if kind == 'authority' then", 1)[1].split(
        "elseif kind == 'target'", 1
    )[0]
    assert "fields[5] == '1' and runtime_policy_ready" in authority


def test_fastfollow_is_never_controlled_by_partycombat():
    lowered = SOURCE.lower()
    assert "ffo " not in lowered
    assert "fastfollow_claimed" not in lowered
    assert "follow_anchor" not in lowered
    assert "zone_follow_restore" not in lowered
    assert "restore_fastfollow" not in lowered
    assert "claim_combat_movement" not in lowered
    assert "_addon.version = '0.6.19'" in SOURCE
    assert "FastFollow is untouched" in SOURCE

    stop_local = SOURCE.split("local function stop_local", 1)[1]
    stop_local = stop_local.split("local function inject_combat_target", 1)[0]
    assert "stop_running()" in stop_local
    assert "FastFollow" not in stop_local

    zone = SOURCE.split(
        "windower.register_event('zone change'", 1
    )[1].split("windower.register_event('logout'", 1)[0]
    assert "stop_local(nil, true)" in zone
    assert "follow" not in zone.lower()


def test_priority_attackers_split_without_retargeting_the_tank():
    assert "local shared_target_id = nil" in SOURCE
    assert "local priority_target_id = nil" in SOURCE
    assert "local function find_priority_target()" in SOURCE
    assert "local function update_priority_target(now)" in SOURCE
    assert "priority_target_matches(target)" in SOURCE
    assert "accept_target(target.id, 'priority')" in SOURCE
    assert "accept_target(shared.id, 'resume')" in SOURCE
    assert "priority_attackers = priority_attackers" in SOURCE
    action = SOURCE.split("windower.register_event('action'", 1)[1]
    action = action.split("windower.register_event('ipc message'", 1)[0]
    priority = action.split(
        "if is_priority_attacker() and priority_target_matches(target)", 1
    )[1].split("-- The puller may establish", 1)[0]
    assert "return" in priority
    assert "send_ipc('target'" not in priority


def test_active_attackers_face_their_combat_target():
    assert "local function face_target(self, target)" in SOURCE
    assert "windower.ffxi.turn(-math.atan2(dy, dx))" in SOURCE

    movement = SOURCE.split(
        "windower.register_event('prerender'", 1
    )[1]
    movement = movement.split(
        "windower.register_event('addon command'", 1
    )[0]
    assert "inject_combat_target(target)" in movement
    assert "face_target(self, target)" in movement
    assert movement.index("face_target(self, target)") < movement.index(
        "if settings.stationary and not directed then"
    )
    assert movement.index("face_target(self, target)") < movement.index(
        "if distance > engage_distance"
    )


def test_target_maintenance_yields_to_manual_control():
    assert "local manual_override = false" in SOURCE
    assert "local active_engaged_seen = false" in SOURCE
    inject = SOURCE.split("local function inject_combat_target", 1)[1]
    inject = inject.split("local function inject_observer_target", 1)[0]
    assert "get_mob_by_target('bt')" in inject
    assert "player.target_index == target.index" not in inject

    movement = SOURCE.split(
        "windower.register_event('prerender'", 1
    )[1].split("windower.register_event('addon command'", 1)[0]
    assert "yield_to_manual_control(" in movement
    assert "Manual battle-target change detected" in movement
    assert "player.status ~= 1 and active_engaged_seen" in movement

    action = SOURCE.split("windower.register_event('action'", 1)[1]
    action = action.split("windower.register_event('ipc message'", 1)[0]
    assert "target.id == shared_target_id" in action
    assert "manual_override or target.id == active_target_id" in action


def test_exact_target_edges_have_bounded_stale_target_delivery_grace():
    assert "local TARGET_TRANSITION_GRACE = 2.0" in SOURCE
    assert "local DIRECTED_TARGET_TRANSITION_GRACE = 15.0" in SOURCE
    assert "local target_transition = nil" in SOURCE
    accept = SOURCE.split("local function accept_target", 1)[1]
    accept = accept.split("local function update_priority_target", 1)[0]
    assert "from_id=battle and valid_enemy(battle) and battle.id or nil" in accept
    assert "directed_split_mode\n                and DIRECTED_TARGET_TRANSITION_GRACE" in accept
    assert "last_engage_at = os.clock() - ENGAGE_RETRY_INTERVAL" in accept
    movement = SOURCE.split(
        "windower.register_event('prerender'", 1)[1]
    movement = movement.split(
        "windower.register_event('addon command'", 1)[0]
    assert "target_transition.from_id == battle.id" in movement
    assert "now <= target_transition.until_at" in movement
    assert movement.index("target_transition = nil") < movement.index(
        "Manual battle-target change detected")


def test_stationary_policy_holds_ordinary_targets_but_directed_force_closes():
    assert "stationary = false" in SOURCE
    assert "stationary = false" in SETTINGS
    assert "[mobile|stationary]" in SOURCE

    policy = SOURCE.split("local function apply_runtime_policy", 1)[1]
    policy = policy.split("local function damage_target", 1)[0]
    assert "movement_mode ~= 'mobile'" in policy
    assert "movement_mode ~= 'stationary'" in policy
    assert "(settings.stationary == true) == stationary" in policy
    assert "stationary = stationary" in policy

    movement = SOURCE.split(
        "windower.register_event('prerender'", 1
    )[1].split("windower.register_event('addon command'", 1)[0]
    assert "local directed = active_mode == 'force' or active_mode == 'forceopaque'" in movement
    guard = movement.split("if settings.stationary and not directed then", 1)[1]
    guard = guard.split("if distance > engage_distance", 1)[0]
    assert "stop_running()" in guard
    assert "return" in guard
    assert "windower.ffxi.run" not in guard
    assert movement.index("if settings.stationary and not directed then") < movement.index(
        "windower.ffxi.run(dx / length, dy / length)"
    )
    stop = SOURCE.split("local function stop_local", 1)[1]
    stop = stop.split("local function inject_combat_target", 1)[0]
    assert "reason, revoke" in stop
    assert "hold_position" not in stop
    target_end = movement.split("if not valid_enemy(target) then", 1)[1]
    target_end = target_end.split("if not is_attacker() then", 1)[0]
    assert "stop_local(is_attacker()" in target_end
    assert "hold_position" not in target_end


def test_target_exclusions_are_explicit_runtime_policy():
    assert "target_exclusions = {}" in SOURCE
    assert "target_exclusions = {}" in SETTINGS
    assert "target_exclusion_configured('elemental')" in SOURCE
    assert "same_target_exclusion_policy(" in SOURCE
    assert "target_exclusion_csv = args[9]" in SOURCE
    assert "[target_exclusions|-]" in SOURCE
    assert "target_exclusions = target_exclusions" in SOURCE
    assert "Target exclusions: " in SOURCE


def test_no_all_character_attack_command():
    assert "send @all" not in SOURCE
    assert "allattack" not in SOURCE


def test_forceid_is_bounded_validated_and_participant_scoped():
    assert "local function unsigned_entity_id(value)" in SOURCE
    validator = SOURCE.split("local function unsigned_entity_id(value)", 1)[1]
    validator = validator.split("local function arm()", 1)[0]
    assert "value:match('^%d+$')" in validator
    assert "id < 1 or id > 4294967295" in validator
    assert "elseif command == 'forceid' then" in SOURCE
    forceid = SOURCE.split("elseif command == 'forceid' then", 1)[1]
    forceid = forceid.split("elseif command == 'off'", 1)[0]
    assert "if not is_controller() then" in forceid
    assert "force_target_id(#args == 1 and args[1] or nil)" in forceid
    controller = SOURCE.split("local function is_controller()", 1)[1]
    controller = controller.split("local function is_attacker()", 1)[0]
    assert "settings.attackers or {}" in controller
    assert "settings.targeters or {}" in controller


def test_forceidto_is_one_shot_exact_recipient_and_arena_bounded():
    assert "local DIRECTED_SPLIT_FORCE_DISTANCE = 50" in SOURCE
    assert "local function directed_attacker_names(value)" in SOURCE
    assert "local function force_target_id_to(value, recipient_csv)" in SOURCE
    assert "send_ipc('targetto', target.id, 'forcesubset', recipient)" in SOURCE
    assert "elseif kind == 'targetto' then" in SOURCE
    assert "not same_name(local_name(), recipient)" in SOURCE
    assert "or not is_attacker()" in SOURCE
    assert "directed_split_mode = mode == 'forcesubset'" in SOURCE
    assert "math.max(configured_limit, DIRECTED_SPLIT_FORCE_DISTANCE)" in SOURCE
    action = SOURCE.split("windower.register_event('action'", 1)[1]
    action = action.split("windower.register_event('ipc message'", 1)[0]
    assert "active_mode == 'forcesubset'" in action
    assert "active_target_id == target.id" in action
    assert "elseif command == 'forceidto' then" in SOURCE
    directed = SOURCE.split("elseif command == 'forceidto' then", 1)[1]
    directed = directed.split("elseif command == 'engageonceid'", 1)[0]
    assert "if not is_controller() then" in directed
    assert "force_target_id_to(" in directed


def test_directed_only_attackers_and_exact_member_stop_are_explicit():
    policy = SOURCE.split("local function apply_runtime_policy", 1)[1]
    policy = policy.split("local function damage_target", 1)[0]
    assert "An attacker omitted here is directed-only" in policy
    assert "local function stop_target_to(recipient_csv)" in SOURCE
    assert "send_ipc('stopto', recipient)" in SOURCE
    assert "elseif kind == 'stopto' then" in SOURCE
    assert "elseif command == 'stopto' then" in SOURCE
    targetto = SOURCE.split("elseif kind == 'targetto' then", 1)[1]
    targetto = targetto.split("elseif kind == 'stopto' then", 1)[0]
    assert "runtime_policy_ready and is_attacker()" in targetto


def test_opaque_force_is_explicit_exact_and_party_claimed():
    assert "local opaque_target = nil" in SOURCE
    assert "local function party_claimed(target)" in SOURCE
    assert "local function opaque_enemy(target)" in SOURCE
    assert "local function bind_opaque_target(target, expected_name)" in SOURCE
    assert "local function force_opaque_target_id(value, name_token)" in SOURCE
    assert "target.hpp == nil" in SOURCE
    assert "party_claimed(target)" in SOURCE
    assert "elseif command == 'forceopaqueid' then" in SOURCE
    assert "mode == 'forceopaque'" in SOURCE
    target_ipc = SOURCE.split("elseif kind == 'target' then", 1)[1]
    target_ipc = target_ipc.split("elseif kind == 'stop'", 1)[0]
    assert target_ipc.index("bind_opaque_target(target, expected_name)") \
        < target_ipc.index("authorized = true")


def test_logout_and_unload_fail_closed():
    lifecycle = SOURCE.split(
        "windower.register_event('logout', 'unload'", 1
    )[1].split("chat(158", 1)[0]
    assert "armed = false" in lifecycle
    assert "authorized = false" in lifecycle
    assert "runtime_policy_ready = false" in lifecycle
    assert "stop_local(nil, true)" in lifecycle


def test_orchestrator_reconcile_is_silent_local_and_fail_closed():
    assert "local function reconcile_local(value)" in SOURCE
    reconcile = SOURCE.split("local function reconcile_local(value)", 1)[1]
    reconcile = reconcile.split("local function force_target", 1)[0]
    assert "not runtime_policy_ready or not is_controller()" in reconcile
    assert "armed = false" in reconcile
    assert "authorized = false" in reconcile
    assert "if was_effective then stop_local(nil, true) end" in reconcile
    assert "armed = true" in reconcile
    assert "if is_targeter() and not authorized then" in reconcile
    for forbidden in ("send_ipc(", "chat("):
        assert forbidden not in reconcile
    assert "elseif command == 'reconcile' then" in SOURCE
    command = SOURCE.split("elseif command == 'reconcile' then", 1)[1]
    command = command.split("elseif command == 'localstop'", 1)[0]
    assert "reconcile_local(#args == 1 and args[1] or nil)" in command


def test_repeated_explicit_arm_repairs_authority_without_chat_spam():
    arm = SOURCE.split("local function arm()", 1)[1].split(
        "local function reconcile_local", 1
    )[0]
    assert "local was_armed = armed" in arm
    assert "broadcast_authority(true)" in arm
    assert "if not was_armed then" in arm
    assert arm.index("broadcast_authority(true)") < arm.index("if not was_armed then")


def test_explicit_force_atomically_authorizes_and_only_opaque_retransmits_once():
    target_ipc = SOURCE.split("elseif kind == 'target' then", 1)[1]
    target_ipc = target_ipc.split("elseif kind == 'stop'", 1)[0]
    assert "mode == 'force' or mode == 'forceopaque'" in target_ipc
    assert "runtime_policy_ready and is_targeter()" in target_ipc
    assert "authorized = true" in target_ipc
    assert "clear_healbot_combat_automation()" in target_ipc

    assert "local FORCE_RETRANSMIT_DELAY = 1" in SOURCE
    force = SOURCE.split("local function force_target(target", 1)[1]
    force = force.split("local function force_current_target()", 1)[0]
    assert "if mode == 'forceopaque' then" in force
    assert force.index("if mode == 'forceopaque' then") < force.index(
        "pending_force_retransmit = {"
    )
    retry = SOURCE.split("local function retransmit_forced_target(now)", 1)[1]
    retry = retry.split("local function stop_all()", 1)[0]
    assert "pending_force_retransmit = nil" in retry
    assert "if pending.mode ~= 'forceopaque' then return end" in retry
    assert retry.count(
        "send_ipc('target', target.id, pending.mode or 'force',"
    ) == 1
    prerender = SOURCE.split("windower.register_event('prerender'", 1)[1]
    prerender = prerender.split("windower.register_event('addon command'", 1)[0]
    assert "retransmit_forced_target(now)" in prerender

    stop_local = SOURCE.split("local function stop_local", 1)[1]
    stop_local = stop_local.split("local function inject_combat_target", 1)[0]
    assert "pending_force_retransmit = nil" in stop_local


def test_observeid_is_local_target_only_and_safety_bounded():
    assert "elseif command == 'observeid' then" in SOURCE
    command = SOURCE.split("elseif command == 'observeid' then", 1)[1]
    command = command.split("elseif command == 'off'", 1)[0]
    assert "observe_target_id(#args == 1 and args[1] or nil)" in command

    observe = SOURCE.split("local function observe_target_id(value)", 1)[1]
    observe = observe.split("local function retransmit_forced_target", 1)[0]
    assert "unsigned_entity_id(value)" in observe
    assert "if not runtime_policy_ready then" in observe
    assert "if not is_targeter() or is_attacker() then" in observe
    assert "if not valid_enemy(target) then" in observe
    assert "local distance = distance_to(target)" in observe
    assert "if distance > limit then" in observe
    assert "authorized = true" in observe
    assert "accept_target(target.id, 'observe')" in observe
    for forbidden in (
        "send_ipc(",
        "inject_combat_target(",
        "windower.ffxi.run(",
        "armed =",
        "pending_force_retransmit =",
    ):
        assert forbidden not in observe
