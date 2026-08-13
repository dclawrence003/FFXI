from pathlib import Path
import unittest


ROOT = Path(__file__).parents[1]


class PartyStartRolePolicy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.addon = (ROOT / "addons/PartyStart/PartyStart.lua").read_text(
            encoding="utf-8"
        )
        cls.rdm = (
            ROOT / "addons/PartyStart/gearswap/PartyStart_RDM.lua"
        ).read_text(encoding="utf-8")

    def test_current_follower_jobs_are_guarded(self):
        for character, job, weapon, weaponskill in (
            ("Tackleberry", "PLD", "Naegling", "Savage Blade"),
            ("Kickpuncher", "DNC", "Tauret", "Evisceration"),
            ("Barneystinson", "BRD", "DualSavage", "Savage Blade"),
            ("Smalls", "RDM", "Maxentius", "Black Halo"),
            ("Achoo", "GEO", "Maxentius", "Black Halo"),
        ):
            start = self.addon.index(character + " = {")
            block = self.addon[start : self.addon.index("    },", start) + 6]
            self.assertIn("jobs = S{'" + job + "'}", block)
            self.assertIn("weapon_mode = '" + weapon + "'", block)
            self.assertIn("ws = '" + weaponskill + "'", block)

    def test_new_job_automation_is_enabled(self):
        self.assertIn("local function apply_pld()", self.addon)
        self.assertIn("gs c set AutoTankMode true", self.addon)
        self.assertIn("gs c set AutoWSMode false", self.addon)
        self.assertIn("local function apply_dnc()", self.addon)
        self.assertIn("gs c set AutoSambaMode Haste", self.addon)
        self.assertIn("gs c set MainStep Box Step", self.addon)

    def test_geo_entrust_prefers_the_pld(self):
        self.assertIn("entrust_jobs={'PLD','RUN','DRK','BLU'}", self.addon)
        self.assertNotIn("entrust_job='WHM'", self.addon)

    def test_rdm_defenses_use_the_full_target_union(self):
        self.assertIn("local defense = pstart_rdm_union_names(", self.rdm)
        self.assertIn("{'Protect V', 'Protect IV'", self.rdm)
        self.assertIn("{'Shell V', 'Shell IV'", self.rdm)


if __name__ == "__main__":
    unittest.main()
