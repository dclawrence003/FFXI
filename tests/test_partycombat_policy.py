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


if __name__ == "__main__":
    unittest.main()
