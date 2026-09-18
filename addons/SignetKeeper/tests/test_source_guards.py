from pathlib import Path
import unittest

ROOT = Path(__file__).parents[1]
SOURCE = (ROOT / "SignetKeeper.lua").read_text(encoding="utf-8")


class SignetKeeperSourceGuards(unittest.TestCase):
    def test_version_and_census_release_are_self_healing(self):
        self.assertIn("_addon.version = '2.3.4'", SOURCE)
        self.assertIn("local CENSUS_REPAIR_INTERVAL = 2", SOURCE)
        self.assertIn("state.next_census_at = now + CENSUS_REPAIR_INTERVAL", SOURCE)
        self.assertIn("mark_census_ready(now)", SOURCE)

    def test_exact_partytactics_authority_replaces_partystart(self):
        self.assertIn("_addon.version = '2.3.4'", SOURCE)
        self.assertIn("command == 'armpt'", SOURCE)
        self.assertIn("state.apply_epoch", SOURCE)
        self.assertIn("state.profile_id", SOURCE)
        self.assertIn("state.profile_version", SOURCE)
        self.assertIn("fields[1] == PT_PREFIX", SOURCE)
        self.assertIn("valid_revision(fields[14])", SOURCE)
        self.assertIn("fields[15]", SOURCE)
        self.assertIn("#fields ~= 15", SOURCE)
        self.assertNotIn("pstart", SOURCE.lower())

    def test_terminal_diagnostic_survives_live_state_reset(self):
        self.assertIn("local last_terminal = nil", SOURCE)
        self.assertIn("remember_terminal(reason, terminal_generation or generation,", SOURCE)
        self.assertIn("remember_terminal(reason or 'PartyTactics stopped'", SOURCE)
        self.assertIn("last-terminal=%s | gen/epoch=%s/%s", SOURCE)

    def test_binding_proof_is_exact_query_only_and_version_agnostic(self):
        self.assertIn("command == '__ackpt'", SOURCE)
        self.assertIn("if #args == 2 then", SOURCE)
        self.assertIn("generation ~= state.generation", SOURCE)
        self.assertIn("tonumber(epoch) ~= state.apply_epoch", SOURCE)
        self.assertIn("state.profile_version, state.pt_engine_version", SOURCE)
        self.assertNotIn("ACK_ENGINE_VERSION", SOURCE)
        self.assertEqual(SOURCE.count("acknowledge_adapter_binding("), 2)

    def test_exact_six_fresh_reports_gate_every_transition(self):
        self.assertIn("EXPECTED_ROSTER_SIZE = 6", SOURCE)
        self.assertIn("reports_are_fresh(now)", SOURCE)
        self.assertIn("ANY_MISSING_CONFIRM = 2", SOURCE)
        self.assertIn("return report.signet", SOURCE)
        self.assertIn("state.puller_drained", SOURCE)
        self.assertIn("'lp drain %s %s %s'", SOURCE)
        self.assertIn("local PULLER_DRAIN_RETRY_INTERVAL = 1", SOURCE)
        self.assertIn("request_puller_drain(now)", SOURCE)
        self.assertIn("command == '__pullerdrained'", SOURCE)
        self.assertIn("accept_local_puller_drained", SOURCE)
        self.assertIn("p.name ~= 'Tackleberry'", SOURCE)
        self.assertIn("kind == 'pullerdrained'", SOURCE)
        self.assertIn("report.phase == 'drain'", SOURCE)
        self.assertIn("report.cycle == state.renewal_cycle", SOURCE)
        self.assertIn("suspend_acks_are_fresh(now)", SOURCE)
        self.assertIn("report.phase == 'suspend'", SOURCE)
        self.assertIn("report.phase == 'apply' and report.signet", SOURCE)
        self.assertIn("and report.weapon_restored", SOURCE)

    def test_staff_cycle_is_fail_closed_and_reload_safe(self):
        self.assertIn("STAFF_ID = 17583", SOURCE)
        self.assertIn("SIGNET_BUFF_ID = 253", SOURCE)
        self.assertIn("STAFF_USE_DELAY = 42.5", SOURCE)
        self.assertIn("STAFF_REUSE_DELAY = 12", SOURCE)
        self.assertIn("STAFF_ATTEMPT_CHAT_INTERVAL = 60", SOURCE)
        self.assertIn("charges_remaining", SOURCE)
        self.assertIn("all_known_depleted", SOURCE)
        self.assertIn("LOCK_REFRESH_INTERVAL = 2", SOURCE)
        self.assertIn("party remains paused", SOURCE)
        self.assertIn(
            "EQUIPPABLE_BAG_IDS = {0, 8, 10, 11, 12, 13, 14, 15, 16}",
            SOURCE,
        )
        self.assertIn(
            "gs enable main sub; gs c weapons; gs c update auto", SOURCE
        )
        self.assertIn("local function capture_combat_weapon()", SOURCE)
        self.assertIn("local function combat_weapon_restored()", SOURCE)
        self.assertIn("local sub_id = equipped_slot_id('sub')", SOURCE)
        self.assertIn("or sub_id == nil", SOURCE)
        self.assertIn("state.weapon_restore_pending = true", SOURCE)
        self.assertIn("WEAPON_RESTORE_RETRY_INTERVAL = 2", SOURCE)
        self.assertIn("WEAPON_RESTORE_CONFIRM = 1", SOURCE)
        self.assertIn("fields[12] == '1'", SOURCE)
        self.assertIn("valid_bit(fields[6]) and valid_bit(fields[8])", SOURCE)
        self.assertIn("valid_bit(fields[10]) and valid_bit(fields[12])", SOURCE)
        self.assertNotIn("get_items('equipment')", SOURCE)

    def test_resume_follows_operator_and_never_blindly_arms(self):
        self.assertIn("state.operator_armed = desired", SOURCE)
        self.assertIn("adapter_command('resume', state.operator_revision,", SOURCE)
        self.assertIn("'lp operator %s %s %s %s'", SOURCE)
        self.assertIn("'lp operator %s %s %s %s resume %s'", SOURCE)
        self.assertIn("not state.census_ready", SOURCE)
        self.assertIn("enforce_suspended_combat_hold()", SOURCE)
        self.assertIn("state.phase == 'suspend' or state.phase == 'apply'", SOURCE)
        self.assertIn("windower.send_command('pc reconcile off')", SOURCE)
        self.assertIn(
            "if state.weapon_restore_pending or not combat_weapon_restored()",
            SOURCE,
        )
        self.assertNotIn("windower.send_command('pc off')", SOURCE)
        self.assertNotIn("windower.send_command('pc on')", SOURCE)

    def test_maintenance_delivery_and_resume_are_self_healing(self):
        self.assertIn("local PHASE_REPAIR_INTERVAL = 1", SOURCE)
        self.assertIn("local ADAPTER_RETRY_INTERVAL = 1", SOURCE)
        self.assertIn("local function repair_phase(now)", SOURCE)
        self.assertIn("request_adapter_suspend(now)", SOURCE)
        self.assertIn("request_adapter_resume(now)", SOURCE)
        self.assertIn("status == 'resumed'", SOURCE)
        self.assertIn("kind == 'pullerrelease'", SOURCE)
        self.assertIn("kind == 'pullerresumed'", SOURCE)
        self.assertIn("command == '__pullerresumed'", SOURCE)
        self.assertIn("state.puller_release_authorized", SOURCE)
        self.assertIn("broadcast_puller_release(now)", SOURCE)
        self.assertIn("local CONTROL_LEASE_STALE_AFTER = 30", SOURCE)
        self.assertIn("local ROSTER_STATE_STALE_AFTER = 30", SOURCE)
        self.assertIn("local function roster_state_timed_out(now)", SOURCE)
        self.assertIn("state.control_lease_seen = true", SOURCE)
        self.assertIn("state.last_control_lease_at = os.clock()", SOURCE)
        self.assertIn("PartyTactics control lease became stale', true", SOURCE)
        disarm_receiver = SOURCE.split("if kind == 'disarm' then", 1)[1].split(
            "elseif kind == 'detach' then", 1)[0]
        self.assertNotIn("send{PREFIX, 'disarm'", disarm_receiver)

    def test_exits_release_owned_slots(self):
        self.assertIn("command == 'detach'", SOURCE)
        self.assertIn("windower.register_event('zone change'", SOURCE)
        self.assertIn("windower.register_event('unload'", SOURCE)
        self.assertIn("windower.register_event('logout'", SOURCE)
        self.assertIn("restore_weapon_slots()", SOURCE)
        unload_handler = SOURCE.split(
            "windower.register_event('unload', function()", 1)[1].split(
                "end)", 1)[0]
        self.assertIn(
            "terminal_disarm_local('addon unload', true, false, true)",
            unload_handler)
        self.assertNotIn("disarm_all", unload_handler)
        self.assertNotIn("send_ipc_message", unload_handler)
        self.assertNotIn("send{", unload_handler)
        self.assertIn("local function begin_terminal_restore", SOURCE)
        self.assertIn("local function tick_terminal_restore", SOURCE)
        self.assertIn("local function consume_terminal_restore_on_unload", SOURCE)
        self.assertIn("terminal_restore.expected_main_id", SOURCE)
        self.assertIn("terminal_restore.expected_sub_id", SOURCE)
        self.assertIn("command == '__pullerlost'", SOURCE)

    def test_adapter_binding_carries_a_stable_keeper_instance_nonce(self):
        self.assertIn("local INSTANCE_NONCE =", SOURCE)
        self.assertIn("math.floor(os.clock() * 1000000)", SOURCE)
        self.assertIn("p.main_job, INSTANCE_NONCE", SOURCE)
        self.assertIn("keeper-instance %s", SOURCE)
        self.assertIn(":format(ADAPTER_CONTROLLER, INSTANCE_NONCE)", SOURCE)

    def test_reload_handoff_never_schedules_operator_override(self):
        self.assertIn("merge_reload_operator", SOURCE)
        self.assertIn("operator_revision=revision", SOURCE)
        self.assertIn("pt __recover_controller %s %s %s", SOURCE)
        self.assertNotIn("windower.send_command('pt reapply')", SOURCE)
        self.assertNotIn("wait 1; pt arm", SOURCE)

    def test_full_reload_handoff_is_narrow_and_bounded(self):
        self.assertIn("command == 'gsreload'", SOURCE)
        self.assertIn("command == 'authorize'", SOURCE)
        self.assertIn("successor_is_authorized", SOURCE)
        self.assertIn("reload_handoff.authorized_generation", SOURCE)
        self.assertIn("local exact_successor = reload_handoff_is_live()", SOURCE)
        self.assertIn("local function begin_weapon_recovery", SOURCE)
        self.assertIn("state.emergency_hold_cycle = cycle", SOURCE)
        self.assertIn("kind == 'weapon-recovery'", SOURCE)
        self.assertIn("EMERGENCY_REQUEST_RETRY_INTERVAL = 1", SOURCE)
        self.assertIn("state.emergency_request_pending", SOURCE)
        self.assertIn("request_adapter_suspend(now)", SOURCE)
        self.assertIn("pending_authority_matches", SOURCE)
        self.assertIn("reload_handoff.roster_token == roster_csv", SOURCE)
        self.assertIn("or generation == reload_handoff.generation", SOURCE)
        self.assertIn("authority_is_retired", SOURCE)
        self.assertNotIn("compare_generation", SOURCE)
        self.assertIn("state.reload_request_relays", SOURCE)
        self.assertIn("send{PREFIX, 'reload-request', fields[3]", SOURCE)
        self.assertIn("send{PREFIX, 'reload-start', fields[3]", SOURCE)
        self.assertIn("GearSwap reload recovery expired', true", SOURCE)

    def test_stop_uses_exact_0132_target_field(self):
        self.assertIn("fields[2] == 'stop'", SOURCE)
        self.assertIn("#fields == 10", SOURCE)
        self.assertIn("accept_stop(fields[10], fields[4]", SOURCE)
        self.assertIn("fields[7], fields[8], fields[9])", SOURCE)
        self.assertIn("stopped_generations", SOURCE)
        self.assertIn("command == 'stoppt'", SOURCE)

    def test_automatic_wires_have_exact_cardinality(self):
        for marker in (
            "#fields ~= 15",
            "#fields == 7 and state.armed",
            "#fields == 5 and state.armed",
            "#fields == 12 and tonumber(fields[5])",
            "#fields == 7 then",
            "if #args == 10 then",
            "if #args == 8 then",
            "if #args == 5 then",
            "if #args == 2 then",
        ):
            self.assertIn(marker, SOURCE)

    def test_operator_register_is_monotonic_and_state_heals_effects(self):
        self.assertIn("local function valid_revision", SOURCE)
        self.assertIn("local function accept_operator_tuple", SOURCE)
        self.assertIn("if revision < state.operator_revision", SOURCE)
        self.assertIn("revision == state.operator_revision", SOURCE)
        self.assertIn("desired ~= state.operator_armed", SOURCE)
        self.assertIn("relay_operator_to_puller(true)", SOURCE)
        self.assertIn("fields[2] ~= 'operator-state'", SOURCE)
        self.assertIn("or #fields ~= 11", SOURCE)


if __name__ == "__main__":
    unittest.main()
