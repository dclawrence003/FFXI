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
            ("Barneystinson", "BRD", "Naegling", "Savage Blade"),
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
        self.assertIn("..status_removal..'hb disable buff", self.addon)
        self.assertIn(
            "apply_pld(session.profile, profile, session.leader)", self.addon
        )

    def test_rdm_defenses_use_the_full_target_union(self):
        self.assertIn("#pstart_rdm.defense > 0", self.rdm)
        self.assertIn("or pstart_rdm_union_names(", self.rdm)
        self.assertIn("{'Protect V', 'Protect IV'", self.rdm)
        self.assertIn("{'Shell V', 'Shell IV'", self.rdm)

    def test_party_protect_propagates_the_profile_mp_floor(self):
        cast_buff = self.rdm.split(
            "local function pstart_rdm_cast_buff(", 1
        )[1].split("local function pstart_rdm_cast_reactive_repair", 1)[0]
        protect = self.rdm.split(
            "local function pstart_rdm_cast_party_protect(", 1
        )[1].split("local function pstart_rdm_cast_party_buffs", 1)[0]
        party_buffs = self.rdm.split(
            "local function pstart_rdm_cast_party_buffs()", 1
        )[1].split("local function pstart_rdm_cast_self_buffs", 1)[0]

        self.assertIn("name, choices, buff, duration, mp_floor", cast_buff)
        self.assertIn("pstart_rdm_can_spend(spell, mp_floor)", cast_buff)
        self.assertIn("defense, mp_floor", protect)
        self.assertIn("'Protect', 1800, mp_floor", protect)
        self.assertEqual(
            2,
            party_buffs.count(
                "pstart_rdm_cast_party_protect(defense, routine_floor)"
            ),
        )

    def test_locus_result_confirmation_is_isolated_from_legacy_profiles(self):
        legacy = self.rdm.split("    locusbats = {", 1)[1].split(
            "    apexcrabs = {", 1
        )[0]
        isolated = self.rdm.split(
            "    ['locusbats-protect'] = {", 1
        )[1].split("\n    },\n}", 1)[0]

        self.assertNotIn("confirm_result", legacy)
        self.assertEqual(2, isolated.count("confirm_result=true"))
        self.assertRegex(
            isolated,
            r"Distract III.*?duration=150,\s*confirm_result=true",
        )
        self.assertRegex(
            isolated,
            r"Dia III.*?duration=150,\s*confirm_result=true",
        )

    def test_pld_action_lease_gates_both_ticks_and_resets_cleanly(self):
        claim = self.pld.split(
            "local function pstart_pld_claim_action(pending)", 1
        )[1].split("local function pstart_pld_action_lease_active", 1)[0]
        timeout = self.pld.split(
            "local function pstart_pld_action_lease_active()", 1
        )[1].split("local function pstart_pld_use_tank_ability", 1)[0]
        action = self.pld.split("local function pstart_pld_action()", 1)[1].split(
            "local function pstart_pld_status()", 1
        )[0]
        status = self.pld.split("local function pstart_pld_status()", 1)[1].split(
            "local pstart_pld_original_self_command", 1
        )[0]
        command = self.pld.split("function user_job_self_command", 1)[1].split(
            "local pstart_pld_original_user_job_tick", 1
        )[0]
        off = command.split("elseif requested == 'off' then", 1)[1].split(
            "elseif PSTART_PLD_PROFILES[requested]", 1
        )[0]
        activate = command.split("elseif PSTART_PLD_PROFILES[requested]", 1)[1]
        native_tick = self.pld.split(
            "local pstart_pld_original_user_job_tick", 1
        )[1].split("local pstart_pld_original_job_aftercast", 1)[0]

        self.assertIn("PSTART_PLD_ACTION_LEASE_TIMEOUT = 5", self.pld)
        self.assertIn("PSTART_PLD_ACTION_LEASE_BACKOFF = 1.5", self.pld)
        self.assertIn("pending.issued_at = now", claim)
        self.assertIn(
            "pending.expires_at = now + PSTART_PLD_ACTION_LEASE_TIMEOUT", claim
        )
        self.assertNotRegex(self.pld, r"pstart_pld\.pending\s*=\s*\{")
        self.assertGreaterEqual(self.pld.count("pstart_pld_claim_action{"), 5)

        self.assertIn("pstart_pld.pending = nil", timeout)
        self.assertIn(
            "pstart_pld.retry_at = now + PSTART_PLD_ACTION_LEASE_BACKOFF",
            timeout,
        )
        self.assertIn("pstart_pld.dispatch_timeouts", timeout)
        self.assertLess(
            action.index("pstart_pld_action_lease_active()"),
            action.index("if midaction()"),
        )
        self.assertIn("if pstart_pld.active", native_tick)
        self.assertIn("os.clock() < (pstart_pld.retry_at or 0)", native_tick)
        self.assertLess(
            native_tick.index("if pstart_pld.active"),
            native_tick.index("pstart_pld_original_user_job_tick"),
        )

        self.assertIn("lease timeouts %d", status)
        for reset in (off, activate):
            self.assertIn("pstart_pld.pending = nil", reset)
            self.assertIn("pstart_pld.dispatch_timeouts = 0", reset)

    def test_partycombat_policy_includes_explicit_target_exclusions(self):
        policy = self.addon.split(
            "local function apply_combat_policy", 1
        )[1].split("local function apply_profile", 1)[0]
        nine_fields = "pc policy " + " ".join(["%s"] * 9)
        old_eight_fields = "pc policy " + " ".join(["%s"] * 8)
        limbus = self.addon.split("    limbus = {", 1)[1].split(
            "    physical = {", 1
        )[0]

        self.assertIn("local exclusion_csv = profile.target_exclusions", policy)
        self.assertIn("and table.concat(profile.target_exclusions, ',') or '-'", policy)
        self.assertIn("issue(('" + nine_fields + "')", policy)
        self.assertNotIn("issue(('" + old_eight_fields + "')", policy)
        self.assertIn(
            "priority_target, priority_attacker_csv, exclusion_csv", policy
        )
        self.assertIn("target_exclusions = {'elemental'}", limbus)

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
        self.assertIn("\n        stationary = true", addon)
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
        self.assertIn("\n        stationary = true", addon)
        self.assertIn("cor = {'corsair', 'samurai'}", addon)
        self.assertIn("indi='Fury', geo='Frailty', entrust='Refresh'", addon)
        self.assertIn("1264 accuracy target", addon)
        self.assertIn("party_shell = false", rdm)
        self.assertLess(rdm.index("'Distract III'"), rdm.index("'Dia III'"))
        self.assertIn("Barblizzara", brd)
        self.assertIn("Victory March", brd)
        self.assertIn("Mage's Ballad III", brd)
        self.assertIn("Blade Madrigal", brd)
        self.assertNotIn("Barwatera", brd)
        self.assertIn("locusbats=true", self.pld)
        self.assertIn("locus = 'locusbats'", self.addon)
        heal_policy = self.pld.split(
            "local function pstart_pld_heal_policy()", 1
        )[1].split("local function pstart_pld_valid_name", 1)[0]
        self.assertNotIn("locusbats", heal_policy)
        self.assertIn("PSTART_PLD_DEFAULT_HEAL_POLICY", heal_policy)

    def test_explicit_support_stop_revokes_partycombat_readiness(self):
        self.assertIn("issue('pc invalidate partystart')", self.addon)
        self.assertIn("stop_local{invalidate_combat=true}", self.addon)
        self.assertIn("windower.register_event('unload'", self.addon)

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
        self.assertIn("\n        stationary = true", addon)
        self.assertGreaterEqual(
            self.addon.count("\n        stationary = true"), 5
        )
        self.assertIn("pc policy %s %s %s %s %s %s %s %s %s", self.addon)
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
        self.assertIn("self_heal_hpp = 40", self.brd)
        self.assertIn("startup_jas = {'Nightingale', 'Troubadour'}", self.brd)
        self.assertIn("mechanic_duty = true", self.brd)
        self.assertIn("pstart_brd_cast_self_heal", self.brd)
        self.assertIn("warble_reactions = true", self.brd)
        self.assertIn("auto_urchin_sleep = true", self.brd)
        self.assertIn(
            "windower.raw_register_event('action', pstart_brd_handle_warble)",
            self.brd,
        )
        self.assertIn("PSTART_BRD_URCHIN_SLEEP_WINDOW = 15", self.brd)
        self.assertIn("kind = 'urchin_sleep'", self.brd)

    def test_limbus_profile_is_stationary_and_puller_driven(self):
        addon = self.addon.split("    limbus = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        rdm = self.rdm.split("    limbus = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        brd = self.brd.split("    limbus = {", 1)[1].split(
            "    physical = {", 1
        )[0]
        self.assertNotIn("target_source = 'command_leader'", addon)
        self.assertIn("Use the composition puller", addon)
        self.assertIn("physical_offense = true", addon)
        self.assertIn("pld_controller = true", addon)
        self.assertIn("\n        stationary = true", addon)
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
            self.assertIn("\n        stationary = true", profile)


if __name__ == "__main__":
    unittest.main()
