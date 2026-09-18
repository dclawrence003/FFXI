from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "SalvageCells.lua").read_text(encoding="utf-8")


EXPECTED_CELLS = {
    5365: "Incus Cell",
    5366: "Castellanus Cell",
    5367: "Cumulus Cell",
    5368: "Radiatus Cell",
    5369: "Stratus Cell",
    5370: "Cirrocumulus Cell",
    5371: "Undulatus Cell",
    5372: "Virga Cell",
    5373: "Duplicatus Cell",
    5374: "Opacus Cell",
    5375: "Praecipitatio Cell",
    5376: "Pannus Cell",
    5377: "Fractus Cell",
    5378: "Congestus Cell",
    5379: "Nimbus Cell",
    5380: "Velum Cell",
    5381: "Pileus Cell",
    5382: "Mediocris Cell",
    5383: "Humilus Cell",
    5384: "Spissatus Cell",
}


def parsed_cells():
    pairs = re.findall(r"\{id=(\d+), name='([^']+)'", SOURCE)
    return {int(item_id): name for item_id, name in pairs}


def test_all_twenty_official_cell_ids_are_present_once():
    assert parsed_cells() == EXPECTED_CELLS


def test_only_the_four_remnants_zone_ids_activate_fresh_run_tracking():
    block = SOURCE.split("local SALVAGE_ZONES = {", 1)[1].split("}", 1)[0]
    assert {int(value) for value in re.findall(r"\[(\d+)\]", block)} == {73, 74, 75, 76}


def test_midrun_load_is_fail_closed():
    assert "set_unknown('Loaded inside a Remnants zone" in SOURCE
    assert "elseif not state.run_known then" in SOURCE
    assert "safer than lotting a cell another player needs" in SOURCE


def test_use_must_be_confirmed_by_inventory_decrement():
    assert "(counts[pending.id] or 0) < pending.count_before" in SOURCE
    assert "mark_unlocked(pending.id)" in SOURCE


def test_failed_cell_use_moves_on_after_configured_limit():
    assert "MaxUseFailures = 3" in SOURCE
    assert "failures >= maximum" in SOURCE
    assert "state.needs[pending.id] = false" in SOURCE
    assert "assuming it was unlocked before reload and moving on" in SOURCE


def test_needed_owned_duplicate_is_passed_not_lotted():
    assert "and state.needs[item_id] and (counts[item_id] or 0) == 0" in SOURCE
    assert "elseif settings.AutoPass and not prior then" in SOURCE


def test_multibox_cells_prioritize_coordinator_then_use_stable_rotation():
    assert "Roster = 'Dolomedes,Tackleberry,Kickpuncher,Barneystinson,Smalls,Achoo'" in SOURCE
    assert "PrioritizeCoordinator = true" in SOURCE
    assert "local function assign_next_owner(item_id)" in SOURCE
    assert "state.assigned_cells[owner_key][item_id] = true" in SOURCE
    assert "state.assigned_cells[coordinator_key][item_id] = true" in SOURCE
    assert "owner and same_name(owner, player_name)" in SOURCE


def test_assignment_excludes_party_members_outside_coordinator_zone():
    assert "local function eligible_roster()" in SOURCE
    assert "for index = 0, 5 do" in SOURCE
    assert "tonumber(member.zone) == zone" in SOURCE
    assert "if eligible[owner_key] and not state.assigned_cells" in SOURCE


def test_only_coordinator_assigns_and_unassigned_clients_wait():
    assert "Coordinator = 'Dolomedes'" in SOURCE
    assert "and is_coordinator() then" in SOURCE
    assert "broadcast_assignment(index, item_id, owner)" in SOURCE
    assert "elseif not assignment then" in SOURCE
    assert "salvagecells:v1:assign:" in SOURCE


def test_coordinator_rebroadcasts_assignments_missed_during_reset():
    assert "AssignmentRebroadcastDelay = 1.0" in SOURCE
    assert "state.assignment_broadcasts[index] = timestamp" in SOURCE
    assert "broadcast_assignment(index, item_id, assignment.owner)" in SOURCE
    assert "if not prior or prior.item_id ~= item_id or prior.owner ~= state.pool_assignments[index].owner" in SOURCE


def test_no_raw_packet_injection():
    assert "packets.inject" not in SOURCE
    assert "windower.packets.inject" not in SOURCE
