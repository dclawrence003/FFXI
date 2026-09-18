from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "LocusPuller.lua").read_text(encoding="utf-8")


class LocusPullerSourceGuards(unittest.TestCase):
    def test_windower_lua51_dispatcher_release(self):
        self.assertIn("_addon.version = '2.1.9'", SOURCE)
        self.assertIn("local function handle_authority_command", SOURCE)
        self.assertIn("local function handle_control_command", SOURCE)

    def test_no_partystart_dependency(self):
        self.assertNotIn("pstart", SOURCE.lower())
        self.assertIn("ADAPTER_CONTROLLER = 'locus-signet'", SOURCE)
        self.assertIn("command == 'bindpt'", SOURCE)
        self.assertIn("command == 'unbindpt'", SOURCE)

    def test_authority_binds_every_profile_command(self):
        self.assertIn("exact_authority(generation, epoch)", SOURCE)
        self.assertIn("exact_authority(args[2], args[3])", SOURCE)
        self.assertIn("sk __pullerdrained %s %s %s", SOURCE)
        self.assertIn("drain_cycle", SOURCE)
        self.assertIn("last_drained_cycle", SOURCE)
        self.assertIn("last_resumed_cycle", SOURCE)
        self.assertIn("cycle == (tonumber(last_drained_cycle) or 0) + 1", SOURCE)
        self.assertIn("authority_is_retired", SOURCE)
        self.assertIn("same_generation_reapply", SOURCE)
        self.assertIn("command == 'authorize'", SOURCE)
        self.assertIn("successor_is_authorized", SOURCE)
        self.assertIn("reload_handoff.authorized_generation", SOURCE)
        self.assertIn("GS_RELOAD_GRACE", SOURCE)
        self.assertNotIn("compare_generation", SOURCE)
        self.assertIn("cycle < (tonumber(last_resumed_cycle) or 0)", SOURCE)
        self.assertIn("report_resume_complete(cycle)", SOURCE)
        self.assertIn("sk __pullerresumed %s %s %s", SOURCE)
        self.assertIn("command == 'retirept'", SOURCE)
        self.assertIn("if #args ~= 10 then return end", SOURCE)
        self.assertIn("if #args ~= 8 then return end", SOURCE)
        self.assertIn("if #args ~= 6 then return end", SOURCE)
        self.assertIn("if #args ~= 3 then return end", SOURCE)
        self.assertIn("if #args ~= 2 then return end", SOURCE)
        self.assertIn("pending_authority_matches", SOURCE)
        self.assertIn("stop_metadata_matches", SOURCE)

    def test_binding_proof_is_exact_query_only_and_version_agnostic(self):
        self.assertIn("command == '__ackpt'", SOURCE)
        self.assertIn("if #args == 2 then", SOURCE)
        self.assertIn("generation ~= pt_generation", SOURCE)
        self.assertIn("tonumber(epoch) ~= pt_epoch", SOURCE)
        self.assertIn("pt_profile_version,", SOURCE)
        self.assertIn("pt_engine_version, pt_signature", SOURCE)
        self.assertNotIn("ACK_ENGINE_VERSION", SOURCE)
        self.assertEqual(SOURCE.count("acknowledge_adapter_binding("), 2)

    def test_operator_register_is_revisioned_and_monotonic(self):
        self.assertIn("local operator_revision = nil", SOURCE)
        self.assertIn("local function valid_revision", SOURCE)
        self.assertIn("if revision < operator_revision", SOURCE)
        self.assertIn("revision == operator_revision", SOURCE)
        self.assertIn("desired ~= operator_armed", SOURCE)
        self.assertIn("operator_revision = revision", SOURCE)
        self.assertIn("resume_marker, args[6]", SOURCE)
        self.assertIn("operator_revision=operator_revision", SOURCE)

    def test_first_hit_is_bounded_and_failure_aware(self):
        self.assertIn("FLASH_CONFIRM_TIMEOUT = 8", SOURCE)
        self.assertIn("LEGACY_FIRST_MELEE_TIMEOUT = 3", SOURCE)
        self.assertIn("FIRST_MELEE_TIMEOUT = 20", SOURCE)
        self.assertIn("GATE_RETRY_SECONDS = 0.35", SOURCE)
        self.assertIn("GATE_RETRY_LIMIT = 4", SOURCE)
        self.assertIn("FLASH_DISPATCH_RETRY_SECONDS = 0.50", SOURCE)
        self.assertIn("FLASH_DISPATCH_WINDOW = 5", SOURCE)
        self.assertIn("FAST_GATE_PROFILE_VERSIONS", SOURCE)
        self.assertIn("['1.4.0']=true", SOURCE)
        self.assertIn("['1.5.0']=true", SOURCE)
        self.assertIn("['1.6.0']=true", SOURCE)
        self.assertIn("['1.7.0']=true", SOURCE)
        self.assertIn("['1.8.0']=true", SOURCE)
        self.assertIn("['1.8.1']=true", SOURCE)
        self.assertIn("local function fast_gate_profile()", SOURCE)
        self.assertIn("and FIRST_MELEE_TIMEOUT or LEGACY_FIRST_MELEE_TIMEOUT", SOURCE)
        self.assertIn("last_attempt = last_attempt - RETRY_SECONDS", SOURCE)
        self.assertIn("windower.register_event('outgoing chunk'", SOURCE)
        self.assertIn("tonumber(packet['Category']) ~= 3", SOURCE)
        self.assertIn("tonumber(packet['Param']) ~= FLASH_ID", SOURCE)
        self.assertIn("tonumber(packet['Target']) ~= opening_target_id", SOURCE)
        self.assertIn("and not flash_dispatched", SOURCE)
        self.assertIn("FAILURE_MESSAGES[message]", SOURCE)
        self.assertIn("opener-release", SOURCE)
        self.assertIn("mob.valid_target == false", SOURCE)
        self.assertNotIn("windower.send_command('aws2 on')", SOURCE)
        self.assertNotIn("windower.send_command('aws2 off')", SOURCE)

    def test_all_exit_paths_release_opening(self):
        for marker in (
            "command == 'off'",
            "command == 'pause'",
            "command == 'mode'",
            "command == 'unbindpt'",
            "windower.register_event('zone change'",
            "windower.register_event('logout'",
            "windower.register_event('unload'",
        ):
            self.assertIn(marker, SOURCE)
        self.assertIn("tostring(args[3] or ''):lower() == 'keepoff'", SOURCE)
        self.assertIn("clear_opening(keep_autows_off == true)", SOURCE)
        self.assertIn("reset_to_standard(true)", SOURCE)
        self.assertIn("reset_to_standard(false)", SOURCE)
        self.assertIn("sk __pullerlost %s %s", SOURCE)

    def test_reload_and_inflight_drain_are_state_preserving(self):
        self.assertIn("command == 'gsreload'", SOURCE)
        self.assertIn("exact_authority(args[1], args[2])", SOURCE)
        self.assertIn("flash_command_issued", SOURCE)
        self.assertIn("may_settle_issued_flash = flash_command_issued", SOURCE)

    def test_standard_mode_still_has_original_delayed_engage(self):
        self.assertIn("if mode == 'standard' then", SOURCE)
        self.assertIn("coroutine.schedule(function()", SOURCE)
        self.assertIn("end, 1.0)", SOURCE)
        self.assertIn("input /attack on", SOURCE)

    def test_stationary_opener_faces_without_movement(self):
        self.assertIn("local function face_mob(mob)", SOURCE)
        self.assertIn("turn(-atan2(dy, dx))", SOURCE)
        self.assertIn("face_mob(live)", SOURCE)
        self.assertNotIn("windower.ffxi.run", SOURCE)

    def test_bound_controls_and_issued_flash_are_transaction_safe(self):
        self.assertIn(
            "pt_bound and (command == 'on' or command == 'mode'", SOURCE
        )
        self.assertIn("or command == 'resume' or command == 'now'", SOURCE)
        self.assertIn("if not flash_command_issued then", SOURCE)
        self.assertIn("`lp off` remains an immediate local emergency stop", SOURCE)


if __name__ == "__main__":
    unittest.main()
