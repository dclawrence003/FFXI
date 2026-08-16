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


def test_fastfollow_is_claimed_only_after_a_target_is_accepted():
    authority = SOURCE.split("if kind == 'authority'", 1)[1]
    authority = authority.split("elseif kind == 'target'", 1)[0]
    assert "ffo stop" not in authority
    assert "clear_healbot_combat_automation()" in authority

    accept = SOURCE.split("local function accept_target", 1)[1]
    accept = accept.split("local function current_leader_target", 1)[0]
    assert "claim_combat_movement()" in accept
    assert accept.index("if distance > limit") < accept.index(
        "claim_combat_movement()"
    )

    movement_claim = SOURCE.split(
        "local function claim_combat_movement()", 1
    )[1].split("\nend", 1)[0]
    assert "ffo stop" in movement_claim


def test_fastfollow_is_restored_only_after_partycombat_claimed_it():
    assert "local fastfollow_claimed = false" in SOURCE

    restore = SOURCE.split(
        "local function restore_fastfollow()", 1
    )[1].split("\nend", 1)[0]
    assert "if fastfollow_claimed" in restore
    assert "local anchor = follow_anchor()" in restore
    assert "not is_follow_anchor()" in restore
    assert "ffo follow '..anchor" in restore
    assert "settings.leader" not in restore
    assert "fastfollow_claimed = false" in restore

    stop_local = SOURCE.split("local function stop_local", 1)[1]
    stop_local = stop_local.split("local function inject_combat_target", 1)[0]
    assert "restore_fastfollow()" in stop_local


def test_zone_follow_recovery_is_delayed_and_cancelled_by_new_combat():
    assert "local zone_follow_restore_at = nil" in SOURCE
    zone = SOURCE.split(
        "windower.register_event('zone change'", 1
    )[1].split("windower.register_event('logout'", 1)[0]
    assert "local restore_after_zone = fastfollow_claimed" in zone
    assert "zone_follow_restore_at = now + POST_ZONE_FOLLOW_DELAY" in zone

    accept = SOURCE.split("local function accept_target", 1)[1]
    accept = accept.split("local function current_leader_target", 1)[0]
    assert "zone_follow_restore_at = nil" in accept

    prerender = SOURCE.split(
        "windower.register_event('prerender'", 1
    )[1].split("windower.register_event('addon command'", 1)[0]
    assert "if zone_follow_restore_at and now >= zone_follow_restore_at" in prerender
    assert "not active_target_id" in prerender
    assert "local anchor = follow_anchor()" in prerender
    assert "ffo follow '..anchor" in prerender


def test_fastfollow_recovery_uses_puller_not_command_leader():
    anchor = SOURCE.split("local function follow_anchor()", 1)[1]
    anchor = anchor.split("local function is_follow_anchor()", 1)[0]
    assert "settings.puller" in anchor
    assert anchor.index("settings.puller") < anchor.index("settings.leader")
    assert "ffo follow '..settings.leader" not in SOURCE
    assert "_addon.version = '0.5.0'" in SOURCE


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
    assert "reason, revoke, hold_position" in stop
    assert "if not hold_position then" in stop
    target_end = movement.split("if not valid_enemy(target) then", 1)[1]
    target_end = target_end.split("if not is_attacker() then", 1)[0]
    assert "settings.stationary == true)" in target_end


def test_no_all_character_attack_command():
    assert "send @all" not in SOURCE
    assert "allattack" not in SOURCE
