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


def test_damage_actions_and_scoped_stationary_flash_drive_targets():
    assert "action.category == 1" in SOURCE
    assert "action.category == 2" in SOURCE
    assert "action.category == 3" in SOURCE
    assert "message.color == 'D'" in SOURCE
    assert "local PULL_FLASH_SPELL_ID = 112" in SOURCE
    assert "action.param == PULL_FLASH_SPELL_ID" in SOURCE
    assert "settings.stationary == true and puller_authority" in SOURCE
    assert "if physical or stationary_pull then return target end" in SOURCE


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
    assert "if not authorized or not is_targeter() then return end" in SOURCE


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
    assert "configured command leader or puller issues //pc on or //pc force" in policy
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
    assert "args[1] ~= 'partystart'" in SOURCE
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
    assert "_addon.version = '0.6.1'" in SOURCE
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
        "if settings.stationary then"
    )
    assert movement.index("face_target(self, target)") < movement.index(
        "if distance > engage_distance"
    )


def test_stationary_policy_is_explicit_and_blocks_translation():
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
    guard = movement.split("if settings.stationary then", 1)[1]
    guard = guard.split("if distance > engage_distance", 1)[0]
    assert "stop_running()" in guard
    assert "return" in guard
    assert "windower.ffxi.run" not in guard
    assert movement.index("if settings.stationary then") < movement.index(
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


def test_no_all_character_attack_command():
    assert "send @all" not in SOURCE
    assert "allattack" not in SOURCE
