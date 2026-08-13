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

    def test_current_offense_jobs_are_guarded(self):
        for character, job, weapon, weaponskill in (
            ("Dolomedes", "COR", "DualSavage", "Savage Blade"),
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
        self.assertIn("local function apply_pld(profile_name)", self.addon)
        self.assertIn("gs c set AutoTankMode", self.addon)
        self.assertIn("gs c unset AutoWSMode", self.addon)
        self.assertIn("local function apply_dnc()", self.addon)
        self.assertIn("gs c set AutoSambaMode Haste", self.addon)
        self.assertIn("gs c set MainStep Box Step", self.addon)
        self.assertIn("gs c set AutoPrestoMode", self.addon)
        self.assertIn("gs c set DanceStance Saber Dance", self.addon)
        self.assertNotIn("gs c set AutoTankMode true", self.addon)
        self.assertNotIn("gs c set AutoWSMode false", self.addon)

    def test_geo_entrust_prefers_the_pld(self):
        self.assertIn("entrust_jobs={'PLD','RUN','DRK','BLU'}", self.addon)
        self.assertNotIn("entrust_job='WHM'", self.addon)

    def test_master_profile_is_mp_conservative(self):
        self.assertIn("local last_profile = 'master'", self.addon)
        master = self.addon[
            self.addon.index("    master = {") : self.addon.index(
                "    physical = {"
            )
        ]
        self.assertIn("brd_debuffs = {}", master)
        self.assertIn("rdm_debuffs = {}", master)
        self.assertIn("entrust='Regen'", master)
        self.assertIn("session.profile == 'master'", self.addon)
        self.assertIn("master = {", self.rdm)
        self.assertIn("local function pstart_rdm_convert()", self.rdm)
        self.assertIn("player.mpp >= 15 or player.hpp < 70", self.rdm)
        self.assertIn("if pstart_rdm_convert() then return true end", self.rdm)
        self.assertIn("local function pstart_rdm_convert_recovery()", self.rdm)
        self.assertIn("if pstart_rdm_convert_recovery() then return true end", self.rdm)
        self.assertIn("player.hpp >= 90", self.rdm)
        self.assertIn("hb disable cure; hb enable na", self.addon)
        self.assertIn(
            "hb enable cure; hb disable na; hb disable buff; hb mincure 2",
            self.addon,
        )
        self.assertIn("apply_pld(session.profile)", self.addon)

    def test_rdm_defenses_use_the_full_target_union(self):
        self.assertIn("local defense = pstart_rdm_union_names(", self.rdm)
        self.assertIn("{'Protect V', 'Protect IV'", self.rdm)
        self.assertIn("{'Shell V', 'Shell IV'", self.rdm)


if __name__ == "__main__":
    unittest.main()
