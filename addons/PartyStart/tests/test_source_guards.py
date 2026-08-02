from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
ADDON = (ROOT / "PartyStart.lua").read_text(encoding="utf-8")
RDM = (ROOT / "gearswap" / "PartyStart_RDM.lua").read_text(encoding="utf-8")


class PartyStartSourceGuards(unittest.TestCase):
    def test_partystart_does_not_police_combat(self):
        self.assertNotIn("PARTYCOMBAT1", ADDON)
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


if __name__ == "__main__":
    unittest.main()
