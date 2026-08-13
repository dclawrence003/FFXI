from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
ADDON = (ROOT / "PartyStart.lua").read_text(encoding="utf-8")
RDM = (ROOT / "gearswap" / "PartyStart_RDM.lua").read_text(encoding="utf-8")
BRD = (ROOT / "gearswap" / "PartyStart_BRD.lua").read_text(encoding="utf-8")
PLD = (ROOT / "gearswap" / "PartyStart_PLD.lua").read_text(encoding="utf-8")
DNC = (ROOT / "gearswap" / "PartyStart_DNC.lua").read_text(encoding="utf-8")
GEO = (ROOT / "gearswap" / "PartyStart_GEO.lua").read_text(encoding="utf-8")


class PartyStartSourceGuards(unittest.TestCase):
    def test_partystart_does_not_police_combat(self):
        self.assertNotIn("PARTYCOMBAT1", ADDON)
        self.assertNotIn("ffo ", ADDON.lower())
        maintenance = ADDON.split(
            "windower.register_event('prerender'", 1
        )[1]
        self.assertNotIn("input /attack off", maintenance)
        self.assertNotIn("combat_authorized", ADDON)
        self.assertIn("schedule_zone_rearm(8)", ADDON)
        self.assertIn("__zonerearm", ADDON)

    def test_physical_profile_is_the_lean_rdm_profile(self):
        physical = RDM.split("accuracy =", 1)[0]
        self.assertNotIn("Frazzle", physical)
        self.assertIn("debuff_mp_floor = 45", physical)
        self.assertIn("debuff_min_target_hpp = 50", physical)

    def test_rdm_refreshes_and_shells_before_offensive_magic(self):
        action = RDM.split("local function pstart_rdm_action()", 1)[1]
        party = action.index("pstart_rdm_cast_party_buffs()")
        debuff = action.index("pstart_rdm_cast_debuff(profile)")
        self.assertLess(party, debuff)
        self.assertIn("party_shell = true", RDM)
        self.assertIn("{'Dia III', 'Dia II', 'Dia'}", RDM)
        self.assertIn("PSTART_RDM_LOSE_EFFECT_MESSAGES", RDM)
        self.assertIn("pstart_rdm_register_remote_buff_loss", RDM)
        self.assertIn("remote_loss_count", RDM)
        self.assertIn("pstart_rdm_cast_reactive_repair", RDM)
        self.assertIn("pstart_rdm_owns_buff", RDM)
        self.assertIn("pending.repair_key and not spell.interrupted", RDM)

    def test_debuffs_respect_mp_and_target_hp_reserves(self):
        self.assertIn(
            "player.mpp < (profile.debuff_mp_floor or 0)", RDM
        )
        self.assertIn(
            "target.hpp < (profile.debuff_min_target_hpp or 0)", RDM
        )

    def test_physical_profile_configures_all_follower_weapon_skills(self):
        expected = {
            "Tackleberry": ("Naegling", "Savage Blade", "1000"),
            "Kickpuncher": ("Tauret", "Evisceration", "1000"),
            "Barneystinson": ("DualSavage", "Savage Blade", "1000"),
            "Smalls": ("Maxentius", "Black Halo", "1000"),
            "Achoo": ("Maxentius", "Black Halo", "1000"),
        }
        for name, values in expected.items():
            start = ADDON.index(f"    {name} = {{")
            block = ADDON[start:].split("\n    },", 1)[0]
            for value in values:
                self.assertIn(value, block)

    def test_partystart_only_stops_autows2_it_owns(self):
        self.assertIn("local autows2_owned = false", ADDON)
        owned_stop = ADDON.split("local function stop_owned_autows2()", 1)[1]
        owned_stop = owned_stop.split("\nend", 1)[0]
        self.assertIn("if autows2_owned then", owned_stop)
        self.assertIn("issue('aws2 off')", owned_stop)
        self.assertIn("Dolomedes = {", ADDON)
        self.assertIn("jobs = S{'COR'}", ADDON)

    def test_brd_has_one_party_song_owner(self):
        self.assertIn("pstart_brd_original_check_song()", BRD)
        self.assertIn("state.SongMode:set", BRD)
        self.assertNotIn("pstart_brd_cast_party_song", BRD)
        self.assertNotIn("pstart_brd_force_instrument", BRD)
        self.assertNotIn("pstart_brd_ensure_physical_weapon", BRD)

    def test_master_has_explicit_single_healing_owners(self):
        master_rdm = ADDON.split(
            "local function apply_rdm", 1
        )[1].split("local function apply_brd", 1)[0]
        master_pld = ADDON.split(
            "local function apply_pld", 1
        )[1].split("local function apply_dnc", 1)[0]
        self.assertIn("hb disable cure", master_rdm)
        self.assertIn("gs c pstartpld master", master_pld)
        self.assertIn("PSTART_PLD_ROUTINE_HPP = 82", PLD)
        self.assertIn("PSTART_PLD_EMERGENCY_HPP = 55", PLD)
        self.assertIn("pstart_pld_action()", PLD)

    def test_pld_healing_precedes_native_tank_tick(self):
        hook = PLD.split(
            "local pstart_pld_original_user_job_tick", 1
        )[1]
        heal = hook.index("pstart_pld_action()")
        native = hook.index("pstart_pld_original_user_job_tick()")
        self.assertLess(heal, native)
        self.assertIn("PSTART_PLD_CHIVALRY_TP = 1000", PLD)
        self.assertIn("reserving 1000 TP for Chivalry", PLD)

    def test_dnc_never_depends_on_unlearned_merit_actions(self):
        apply_dnc = ADDON.split(
            "local function apply_dnc", 1
        )[1].split("local function apply_cor", 1)[0]
        self.assertIn("gs c set DanceStance None", apply_dnc)
        self.assertNotIn("Saber Dance", apply_dnc)
        self.assertIn("pstart_dnc_known(action_id)", DNC)
        self.assertIn("Haste Samba", DNC)
        self.assertIn("Box Step", DNC)
        self.assertIn("PSTART_DNC_EMERGENCY_HPP = 42", DNC)
        self.assertNotIn("pstart_dnc_use(PSTART_DNC_ACTIONS.box_step, tostring(target.id)", DNC)
        self.assertIn("pstart_dnc_use(PSTART_DNC_ACTIONS.box_step, '<t>'", DNC)

    def test_hostile_actions_use_synchronized_local_target(self):
        for source in (RDM, BRD, DNC):
            self.assertIn("get_mob_by_target('t')", source)
        self.assertIn("windower.chat.input('/ma \"'..spell.en..'\" <t>')", RDM)
        self.assertIn("windower.chat.input('/ma \"'..spell.en..'\" <t>')", BRD)

    def test_stop_cannot_reenable_autows2(self):
        dnc_off = DNC.split("elseif requested == 'off' then", 1)[1]
        dnc_off = dnc_off.split("elseif requested", 1)[0]
        self.assertNotIn("aws2 on", dnc_off)
        pld_off = PLD.split("elseif requested == 'off' then", 1)[1]
        pld_off = pld_off.split("elseif requested", 1)[0]
        self.assertNotIn("aws2 on", pld_off)

    def test_master_uses_stackable_physical_debuffs(self):
        master = ADDON.split("master = {", 1)[1].split("physical = {", 1)[0]
        self.assertIn("Carnage Elegy", master)
        self.assertIn("Dia III", master)
        self.assertIn("geo = {indi='Fury', geo='Frailty'", master)

    def test_geo_lean_mode_preserves_colure_automation(self):
        self.assertIn("buff_spell_lists.Auto = {}", GEO)
        self.assertNotIn("AutoBuffMode:set('Off')", GEO)
        self.assertIn("gs c pstartgeo lean", ADDON)

    def test_geo_is_inert_until_partystart_activates_it(self):
        self.assertIn("wait 2; gs c pstartgeo bootidle", GEO)
        boot = GEO.split("requested == 'bootidle'", 1)[1]
        boot = boot.split("elseif requested", 1)[0]
        self.assertIn("if not pstart_geo_active then", boot)
        self.assertIn("pstart_geo_set_autobuff('Off')", GEO)
        stop = ADDON.split("local function stop_local()", 1)[1]
        stop = stop.split("\nend", 1)[0]
        self.assertIn("gs c pstartgeo idle", stop)


if __name__ == "__main__":
    unittest.main()
