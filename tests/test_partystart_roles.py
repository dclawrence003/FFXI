from pathlib import Path
import re
import unittest


ROOT = Path(__file__).parents[1]


class PartyStartRolePolicy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.addon = (ROOT / "addons/PartyStart/PartyStart.lua").read_text(
            encoding="utf-8"
        )
        cls.compositions = (
            ROOT / "addons/PartyStart/data/compositions.lua"
        ).read_text(encoding="utf-8")
        cls.rdm = (
            ROOT / "addons/PartyStart/gearswap/PartyStart_RDM.lua"
        ).read_text(encoding="utf-8")
        cls.brd = (
            ROOT / "addons/PartyStart/gearswap/PartyStart_BRD.lua"
        ).read_text(encoding="utf-8")
        cls.pld = (
            ROOT / "addons/PartyStart/gearswap/PartyStart_PLD.lua"
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
            self.assertIn(character + " = {", self.compositions)
            self.assertIn(
                job + " = {weapon_mode='" + weapon + "', ws='"
                + weaponskill + "', tp=1000}",
                self.compositions,
            )

    def test_every_composition_authorizes_the_command_leader_to_attack(self):
        blocks = re.findall(
            r"attackers\s*=\s*\{(.*?)\},\s*offense",
            self.compositions,
            flags=re.DOTALL,
        )
        self.assertEqual(3, len(blocks))
        for block in blocks:
            self.assertIn("'Dolomedes'", block)

    def test_new_job_automation_is_enabled(self):
        self.assertIn(
            "local function apply_pld(profile_name, profile, leader)", self.addon
        )
        self.assertIn("gs c set AutoTankMode", self.addon)
        self.assertIn("gs c unset AutoWSMode", self.addon)
        self.assertIn(
            "local function apply_dnc(profile_name, target_source)", self.addon
        )
        self.assertIn("gs c set AutoSambaMode Off", self.addon)
        self.assertIn("gs c pstartdnc %s %s", self.addon)
        self.assertIn("gs c set AutoBuffMode Off; gs c unset AutoPrestoMode", self.addon)
        self.assertIn("gs c set DanceStance None", self.addon)
        self.assertNotIn("gs c set AutoTankMode true", self.addon)
        self.assertNotIn("gs c set AutoWSMode false", self.addon)

    def test_geo_entrust_prefers_the_pld(self):
        self.assertIn("entrust_jobs={'PLD','RUN','RDM','COR'}", self.addon)
        self.assertNotIn("entrust_job='WHM'", self.addon)

    def test_master_profile_is_mp_conservative(self):
        self.assertIn("local last_profile = 'master'", self.addon)
        master = self.addon[
            self.addon.index("    master = {") : self.addon.index(
                "    physical = {"
            )
        ]
        self.assertIn("Mage's Ballad III", master)
        self.assertIn("Carnage Elegy", master)
        self.assertIn("Dia III", master)
        self.assertIn("entrust='Refresh'", master)
        self.assertIn("profile_name == 'master'", self.addon)
        self.assertIn("and job == 'PLD'", self.addon)
        self.assertIn("profile.physical_offense", self.addon)
        self.assertIn("master = {", self.rdm)
        self.assertIn("lean = true", self.rdm)
        self.assertIn("party_shell = false", self.rdm)
        self.assertIn("routine_buff_mp_floor = 35", self.rdm)
        self.assertIn("{'Gain-MND', 'Gain-STR'}", self.rdm)
        self.assertIn("if not profile.lean", self.rdm)
        self.assertIn("local function pstart_rdm_convert()", self.rdm)
        self.assertIn("player.mpp >= 15 or player.hpp < 70", self.rdm)
        self.assertIn("if pstart_rdm_convert() then return true end", self.rdm)
        self.assertIn("local function pstart_rdm_convert_recovery()", self.rdm)
        self.assertIn("if pstart_rdm_convert_recovery() then return true end", self.rdm)
        self.assertIn("player.hpp >= 90", self.rdm)
        self.assertIn("local function pstart_rdm_emergency_heal()", self.rdm)
        self.assertIn("member.hpp > 0 and member.hpp < heal_hpp", self.rdm)
        self.assertIn("if pstart_rdm_emergency_heal() then return true end", self.rdm)
        self.assertIn("hb deactivateindoors off", self.addon)
        self.assertIn("hb disable cure", self.addon)
        self.assertIn("hb enable na; hb disable buff", self.addon)
        self.assertIn(
            "apply_pld(session.profile, profile, session.leader)", self.addon
        )

    def test_rdm_defenses_use_the_full_target_union(self):
        self.assertIn("#pstart_rdm.defense > 0", self.rdm)
        self.assertIn("or pstart_rdm_union_names(", self.rdm)
        self.assertIn("{'Protect V', 'Protect IV'", self.rdm)
        self.assertIn("{'Shell V', 'Shell IV'", self.rdm)

    def test_august_ambuscade_profiles_are_encounter_scoped(self):
        for profile in ("ambuscade-v1", "ambuscade-v2"):
            self.assertIn(f"['{profile}'] = {{", self.addon)
            self.assertIn(f"['{profile}'] = {{", self.rdm)
            self.assertIn(f"['{profile}'] = {{", self.brd)
            self.assertIn(f"['{profile}']=true", self.pld)
        self.assertGreaterEqual(
            self.addon.count(
                "attackers = {'Dolomedes', 'Tackleberry', 'Kickpuncher'}"
            ),
            2,
        )
        self.assertGreaterEqual(self.addon.count("target_all = true"), 2)
        self.assertIn("Stymie", self.rdm)
        self.assertIn("Saboteur", self.rdm)
        self.assertIn("{'Silence'}", self.rdm)
        self.assertIn("Barstonra", self.brd)
        self.assertIn("Barsilencera", self.brd)
        self.assertIn("Barsleepra", self.brd)
        self.assertIn("PSTART_PLD_V1_HUNDRED_FISTS_HPP = 52", self.pld)
        self.assertIn("Sweet Breath resets enmity", self.addon)


if __name__ == "__main__":
    unittest.main()
