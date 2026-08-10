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


def test_only_damage_actions_drive_automatic_targets():
    assert "action.category == 1" in SOURCE
    assert "action.category == 2" in SOURCE
    assert "action.category == 3" in SOURCE
    assert "message.color == 'D'" in SOURCE


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
    assert "if not authorized or not is_attacker() then return end" in SOURCE


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


def test_no_all_character_attack_command():
    assert "send @all" not in SOURCE
    assert "allattack" not in SOURCE
