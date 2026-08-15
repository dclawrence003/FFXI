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
        self.assertIn("if is_attacker() and not authorized then", self.addon)
        self.assertIn("authorized = true", self.addon)
        self.assertGreaterEqual(self.addon.count("accept_target(target.id"), 2)

    def test_leader_never_follows_itself(self):
        self.assertIn("and not is_leader()", self.addon)


if __name__ == "__main__":
    unittest.main()
