from pathlib import Path
import unittest


ROOT = Path(__file__).parents[1]


class PartyCombatPolicy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.addon = (ROOT / "addons/PartyCombat/PartyCombat.lua").read_text(
            encoding="utf-8"
        )
        cls.settings = (
            ROOT / "addons/PartyCombat/data/settings.lua"
        ).read_text(encoding="utf-8")

    def test_leader_is_an_attacker(self):
        self.assertIn("Dolomedes = {", self.settings)
        self.assertIn("Dolomedes = {", self.addon)

    def test_leader_or_puller_can_control_combat(self):
        self.assertIn("local function is_controller()", self.addon)
        self.assertIn("return is_leader() or is_puller()", self.addon)
        self.assertIn("if not is_controller() then", self.addon)
        self.assertIn("Only the configured leader or puller", self.addon)

    def test_controller_self_authorizes_without_ipc_loopback(self):
        self.assertIn("if is_targeter() and not authorized then", self.addon)
        self.assertIn("authorized = true", self.addon)
        self.assertGreaterEqual(self.addon.count("accept_target(target.id"), 2)

    def test_puller_is_the_follow_anchor_and_never_follows_itself(self):
        anchor = self.addon.split("local function follow_anchor()", 1)[1]
        anchor = anchor.split("local function is_follow_anchor()", 1)[0]
        self.assertIn("settings.puller", anchor)
        self.assertIn("not is_follow_anchor()", self.addon)
        self.assertNotIn("ffo follow '..settings.leader", self.addon)

    def test_target_only_observers_never_claim_combat_movement(self):
        self.assertIn("local function is_targeter()", self.addon)
        self.assertIn("local function inject_observer_target(target)", self.addon)
        self.assertIn("packets.new('incoming', 0x058", self.addon)
        self.assertIn("active_mode = 'observe'", self.addon)
        observer = self.addon.split("if not is_attacker() then", 1)[1]
        observer = observer.split("local attacker =", 1)[0]
        self.assertNotIn("claim_combat_movement", observer)
        self.assertNotIn("inject_combat_target", observer)

    def test_runtime_policy_separates_attackers_and_targeters(self):
        self.assertIn("same_targeter_roster", self.addon)
        self.assertIn("targeters = targeters", self.addon)
        self.assertIn("[targeters|->]", self.addon)
        self.assertIn("target-only observer", self.addon)
        self.assertIn("local unchanged = active_policy_name == policy_name", self.addon)

    def test_priority_split_preserves_and_resumes_shared_target(self):
        self.assertIn("local shared_target_id = nil", self.addon)
        self.assertIn("local priority_target_id = nil", self.addon)
        self.assertIn("local function find_priority_target()", self.addon)
        self.assertIn("local function update_priority_target(now)", self.addon)
        self.assertIn("accept_target(target.id, 'priority')", self.addon)
        self.assertIn("accept_target(shared.id, 'resume')", self.addon)
        self.assertIn("priority_attackers = priority_attackers", self.addon)
        self.assertIn("[priority_target|->]", self.addon)
        self.assertIn("[priority_attackers|->]", self.addon)

    def test_stationary_policy_disables_approach_but_keeps_engagement(self):
        self.assertIn("stationary = false", self.settings)
        self.assertIn("settings.stationary and 'stationary' or 'mobile'", self.addon)
        self.assertIn("if settings.stationary then", self.addon)
        movement = self.addon.split("windower.register_event('prerender'", 1)[1]
        movement = movement.split("windower.register_event('addon command'", 1)[0]
        self.assertIn("inject_combat_target(target)", movement)
        self.assertIn("face_target(self, target)", movement)
        self.assertLess(
            movement.index("face_target(self, target)"),
            movement.index("if settings.stationary then"),
        )
        self.assertLess(
            movement.index("if settings.stationary then"),
            movement.index("windower.ffxi.run(dx / length, dy / length)"),
        )
        self.assertIn("reason, revoke, hold_position", self.addon)
        self.assertIn("if not hold_position then", self.addon)
        self.assertIn("settings.stationary == true)", movement)

    def test_stationary_puller_flash_can_establish_the_target(self):
        self.assertIn("local PULL_FLASH_SPELL_ID = 112", self.addon)
        self.assertIn("action.param == PULL_FLASH_SPELL_ID", self.addon)
        self.assertIn("settings.stationary == true and puller_authority", self.addon)


if __name__ == "__main__":
    unittest.main()
