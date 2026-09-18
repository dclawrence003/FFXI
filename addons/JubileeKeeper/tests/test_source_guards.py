from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "JubileeKeeper.lua").read_text(encoding="utf-8")


class JubileeKeeperSourceGuards(unittest.TestCase):
    def test_version_and_lock_repair_are_idempotent(self):
        self.assertIn("_addon.version = '2.1.3'", SOURCE)
        self.assertIn("lock_needs_reassert = false", SOURCE)
        self.assertIn("state.lock_needs_reassert = true", SOURCE)
        self.assertNotIn("LOCK_REFRESH_INTERVAL", SOURCE)

    def test_scope_is_exact_and_inert(self):
        self.assertIn("local ITEM_ID = 27593", SOURCE)
        self.assertIn("local OWNER_NAME = 'Dolomedes'", SOURCE)
        self.assertIn("local EQUIPMENT_KEY = 'right_ring'", SOURCE)
        self.assertIn("local EQUIP_SLOT = 'ring2'", SOURCE)
        self.assertIn("armed = false", SOURCE)
        self.assertNotIn("ring1", SOURCE)

    def test_native_equip_is_raw_verified_and_locked(self):
        self.assertIn("raw_equipped_item_id() ~= ITEM_ID", SOURCE)
        self.assertIn("get_items() or {}).equipment", SOURCE)
        self.assertNotIn("get_items('equipment')", SOURCE)
        self.assertIn("input /equip '..EQUIP_SLOT", SOURCE)
        self.assertIn("gs disable '..EQUIP_SLOT", SOURCE)
        self.assertNotIn("gs enable '..EQUIP_SLOT..'; input /equip", SOURCE)
        self.assertNotIn("..'\"; gs disable '..EQUIP_SLOT", SOURCE)

    def test_binding_proof_is_exact_query_only_and_version_agnostic(self):
        self.assertIn("command == '__ackpt'", SOURCE)
        self.assertIn("if #args == 2 then", SOURCE)
        self.assertIn("generation ~= state.generation", SOURCE)
        self.assertIn("tonumber(epoch) ~= state.apply_epoch", SOURCE)
        self.assertIn("state.profile_version, state.pt_engine_version", SOURCE)
        self.assertNotIn("ACK_ENGINE_VERSION", SOURCE)
        self.assertEqual(SOURCE.count("acknowledge_adapter_binding("), 2)

    def test_partytactics_authority_and_every_exit_release(self):
        self.assertIn("command == 'armpt'", SOURCE)
        self.assertIn("command == 'detach'", SOURCE)
        self.assertIn("fields[1] ~= PT_PREFIX", SOURCE)
        self.assertIn("PT_STATE_STALE_AFTER", SOURCE)
        self.assertIn("#fields ~= 15", SOURCE)
        self.assertIn("windower.register_event('zone change'", SOURCE)
        self.assertIn("windower.register_event('logout'", SOURCE)
        self.assertIn("windower.register_event('unload'", SOURCE)
        self.assertIn("gs enable '..EQUIP_SLOT..'; gs c update", SOURCE)
        self.assertNotIn("partystart", SOURCE.lower())

    def test_helper_does_not_control_combat_or_signet(self):
        self.assertNotIn("PartyCombat", SOURCE)
        self.assertNotIn("LocusPuller", SOURCE)
        self.assertNotIn("SignetKeeper", SOURCE)
        self.assertNotIn("pc on", SOURCE.lower())
        self.assertNotIn("lp on", SOURCE.lower())

    def test_reload_and_authority_order_are_bounded(self):
        self.assertIn("command == 'gsreload'", SOURCE)
        self.assertIn("command == 'authorize'", SOURCE)
        self.assertIn("GS_RELOAD_GRACE", SOURCE)
        self.assertIn("authority_is_retired", SOURCE)
        self.assertIn("same_generation_reapply", SOURCE)
        self.assertIn("successor_is_authorized", SOURCE)
        self.assertIn("reload_handoff.authorized_generation", SOURCE)
        self.assertIn("pending_authority_matches", SOURCE)
        self.assertIn("state.reload_pending = false", SOURCE)
        self.assertNotIn("compare_generation", SOURCE)

    def test_stop_uses_exact_0132_target_field(self):
        self.assertIn("fields[2] == 'stop'", SOURCE)
        self.assertIn("#fields == 10", SOURCE)
        self.assertIn("accept_stop(fields[10], fields[4]", SOURCE)
        self.assertIn("stopped_generations", SOURCE)
        self.assertIn("command == 'stoppt'", SOURCE)
        self.assertIn("if #args == 8 then", SOURCE)
        self.assertIn("if #args == 6 then", SOURCE)
        self.assertIn("if #args == 2 then", SOURCE)


if __name__ == "__main__":
    unittest.main()
