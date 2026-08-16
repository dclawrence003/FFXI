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
        self.assertIn("sustained = true", master)
        self.assertIn("local sustained = profile.sustained == true", self.addon)
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
                "'Dolomedes', 'Tackleberry', 'Kickpuncher', 'Smalls', 'Achoo',"
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

    def test_apex_bats_profile_keeps_mp_and_status_policy_separate(self):
        addon = self.addon.split("    apexbats = {", 1)[1].split(
            "    locusbats = {", 1
        )[0]
        rdm = self.rdm.split("    apexbats = {", 1)[1].split(
            "    locusbats = {", 1
        )[0]
        brd = self.brd.split("    apexbats = {", 1)[1].split(
            "    locusbats = {", 1
        )[0]
        self.assertIn("Sustained Apex Bats: Dho Gates", addon)
        self.assertIn("sustained = true", addon)
        self.assertIn("stationary = true", addon)
        self.assertIn("Mage's Ballad III", addon)
        self.assertIn("entrust='Refresh'", addon)
        self.assertIn("party_shell = false", rdm)
        self.assertIn("routine_buff_mp_floor = 35", rdm)
        self.assertIn("Barwatera", brd)
        self.assertIn("apexbats=true", self.pld)
        self.assertIn("bats = 'apexbats'", self.addon)

    def test_locus_bats_profile_targets_tomb_accuracy_and_move_set(self):
        addon = self.addon.split("    locusbats = {", 1)[1].split(
            "    apexcrabs = {", 1
        )[0]
        rdm = self.rdm.split("    locusbats = {", 1)[1].split(
            "    apexcrabs = {", 1
        )[0]
        brd = self.brd.split("    locusbats = {", 1)[1].split(
            "    apexcrabs = {", 1
        )[0]
        self.assertIn("Sustained Locus Dire Bats", addon)
        self.assertIn("sustained = true", addon)
        self.assertIn("stationary = true", addon)
        self.assertIn("cor = {'corsair', 'samurai'}", addon)
        self.assertIn("1264 accuracy target", addon)
        self.assertIn("party_shell = false", rdm)
        self.assertLess(rdm.index("'Distract III'"), rdm.index("'Dia III'"))
        self.assertIn("Barblizzara", brd)
        self.assertNotIn("Barwatera", brd)
        self.assertIn("locusbats=true", self.pld)
        self.assertIn("locus = 'locusbats'", self.addon)

    def test_apex_crabs_profile_reacts_to_self_buffs_without_blind_spam(self):
        addon = self.addon.split("    apexcrabs = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        rdm = self.rdm.split("    apexcrabs = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        brd = self.brd.split("    apexcrabs = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        self.assertIn("Sustained Apex Crabs: Dho Gates", addon)
        self.assertIn("stationary = true", addon)
        self.assertEqual(4, self.addon.count("stationary = true"))
        self.assertIn("pc policy %s %s %s %s %s %s %s %s", self.addon)
        self.assertIn("profile.stationary and 'stationary' or 'mobile'", self.addon)
        self.assertIn("targeter_csv, movement_mode", self.addon)
        self.assertIn("party_shell = true", rdm)
        self.assertIn("target_names={'Apex Crab'}", rdm)
        self.assertIn("ttl=30", rdm)
        self.assertIn("max_pending=3", rdm)
        self.assertIn("heal_hpp = 45", rdm)
        self.assertIn("PSTART_PLD_CRAB_HEAL_POLICY", self.pld)
        self.assertIn("TP reservation must not suppress a needed cure", self.pld)
        self.assertIn("pstart_rdm.dispel_targets[actor.id]", self.rdm)
        self.assertIn("pstart_rdm.dispel_targets[target.id]", self.rdm)
        self.assertIn("Barwatera", brd)
        self.assertIn("apexcrabs=true", self.pld)
        self.assertIn("crabs = 'apexcrabs'", self.addon)

    def test_v1_has_urchin_split_and_barney_recovery(self):
        v1 = self.addon.split("['ambuscade-v1'] = {", 1)[1].split(
            "['ambuscade-v2'] = {", 1
        )[0]
        self.assertIn("priority_target = 'Bozzetto Urchin'", v1)
        self.assertIn(
            "priority_attackers = {'Dolomedes', 'Kickpuncher'}", v1
        )
        self.assertIn(
            "free_look_observers = {'Barneystinson'}", v1
        )
        self.assertIn("profile.free_look_observers or {}", self.addon)
        self.assertIn(
            "free-look support; no forced target/AutoWS2", self.addon
        )
        self.assertIn("HOUSEMAKER RETURNED: BARNEY RETURN TO GROUP NOW", self.addon)
        self.assertIn("self_heal_hpp = 85", self.brd)
        self.assertIn("pstart_brd_cast_self_heal", self.brd)
        self.assertIn("warble_reactions = true", self.brd)
        self.assertIn("auto_urchin_sleep = true", self.brd)
        self.assertIn(
            "windower.raw_register_event('action', pstart_brd_handle_warble)",
            self.brd,
        )
        self.assertIn("PSTART_BRD_URCHIN_SLEEP_WINDOW = 15", self.brd)
        self.assertIn("kind = 'urchin_sleep'", self.brd)

    def test_limbus_profile_is_mobile_and_dolo_driven(self):
        addon = self.addon.split("    limbus = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        rdm = self.rdm.split("    limbus = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        brd = self.brd.split("    limbus = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        self.assertIn("target_source = 'command_leader'", addon)
        self.assertIn("physical_offense = true", addon)
        self.assertIn("pld_controller = true", addon)
        self.assertNotIn("stationary = true", addon)
        self.assertIn("profile.target_source == 'command_leader'", self.addon)
        self.assertIn("elseif command == 'sleep' then", self.addon)
        self.assertIn("elseif kind == 'sleep' then", self.addon)
        self.assertIn("Horde Lullaby II", self.brd)
        self.assertIn("PSTART_BRD_SLEEP_WINDOW = 8", self.brd)
        self.assertIn("debuff_min_target_hpp = 45", brd)
        self.assertIn("party_shell = true", rdm)
        self.assertIn("healing = true", rdm)
        self.assertIn("heal_hpp = 50", rdm)
        self.assertIn("limbus=true", self.pld)

    def test_every_unattended_xp_profile_is_stationary(self):
        master = self.addon.split("    master = {", 1)[1].split(
            "    apexbats = {", 1
        )[0]
        bats = self.addon.split("    apexbats = {", 1)[1].split(
            "    locusbats = {", 1
        )[0]
        locus_bats = self.addon.split("    locusbats = {", 1)[1].split(
            "    apexcrabs = {", 1
        )[0]
        crabs = self.addon.split("    apexcrabs = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        for profile in (master, bats, locus_bats, crabs):
            self.assertIn("sustained = true", profile)
            self.assertIn("stationary = true", profile)


if __name__ == "__main__":
    unittest.main()
