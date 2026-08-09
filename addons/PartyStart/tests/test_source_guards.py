from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
ADDON = (ROOT / "PartyStart.lua").read_text(encoding="utf-8")
RDM = (ROOT / "gearswap" / "PartyStart_RDM.lua").read_text(encoding="utf-8")
BRD = (ROOT / "gearswap" / "PartyStart_BRD.lua").read_text(encoding="utf-8")


class PartyStartSourceGuards(unittest.TestCase):
    def test_partystart_does_not_police_combat(self):
        self.assertNotIn("PARTYCOMBAT1", ADDON)
        self.assertNotIn("ffo ", ADDON.lower())
        maintenance = ADDON.split(
            "windower.register_event('prerender'", 1
        )[1]
        self.assertNotIn("input /attack off", maintenance)
        self.assertNotIn("combat_authorized", ADDON)

    def test_physical_profile_is_the_lean_rdm_profile(self):
        physical = RDM.split("accuracy =", 1)[0]
        self.assertNotIn("Frazzle", physical)
        self.assertIn("debuff_mp_floor = 45", physical)
        self.assertIn("debuff_min_target_hpp = 50", physical)

    def test_rdm_refreshes_before_offensive_magic(self):
        action = RDM.split("local function pstart_rdm_action()", 1)[1]
        party = action.index("pstart_rdm_cast_party_buffs()")
        debuff = action.index("pstart_rdm_cast_debuff(profile)")
        self.assertLess(party, debuff)

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
            block = ADDON.split(f"{name} = {{", 1)[1].split("},", 1)[0]
            for value in values:
                self.assertIn(value, block)

    def test_partystart_only_stops_autows2_it_owns(self):
        self.assertIn("local autows2_owned = false", ADDON)
        owned_stop = ADDON.split("local function stop_owned_autows2()", 1)[1]
        owned_stop = owned_stop.split("\nend", 1)[0]
        self.assertIn("if autows2_owned then", owned_stop)
        self.assertIn("issue('aws2 off')", owned_stop)
        self.assertIn("player.name == 'Dolomedes'", ADDON)

    def test_brd_has_one_party_song_owner(self):
        self.assertIn("pstart_brd_original_check_song()", BRD)
        self.assertIn("state.SongMode:set", BRD)
        self.assertNotIn("pstart_brd_cast_party_song", BRD)
        self.assertNotIn("pstart_brd_force_instrument", BRD)
        self.assertNotIn("pstart_brd_ensure_physical_weapon", BRD)


if __name__ == "__main__":
    unittest.main()
