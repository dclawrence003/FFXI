import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ADDON = (ROOT / "addons" / "LimbusTracker" / "LimbusTracker.lua").read_text(
    encoding="utf-8"
)


class LimbusTrackerDetection(unittest.TestCase):
    def test_final_coffer_detection_uses_three_packet_stages(self):
        self.assertIn("_addon.version = '0.4.3'", ADDON)
        self.assertIn("if id == 0x01A then", ADDON)
        self.assertIn("elseif id == 0x05B then", ADDON)
        self.assertIn("if id == 0x032 or id == 0x034 then", ADDON)
        self.assertIn("begin_chest(packet.Target, 'action', packet.Zone)", ADDON)
        self.assertIn("begin_chest(packet.Target, source, packet.Zone)", ADDON)
        self.assertIn("begin_chest(packet.NPC, 'menu', packet.Zone)", ADDON)

    def test_repeated_stages_preserve_the_currency_baseline(self):
        begin = ADDON.split("local function begin_chest", 1)[1].split(
            "local function finish_chest_if_ready", 1
        )[0]
        self.assertIn("pending_timeout = 120", ADDON)
        self.assertIn("pending_chest.last_seen = now", begin)
        self.assertIn("pending_chest.sources[source] = true", begin)
        guarded_update = (
            "if pending_chest.units_before == nil then\n"
            "            pending_chest.units_before = tonumber(previous_units[field])\n"
            "        end"
        )
        self.assertIn(guarded_update, begin)
        self.assertEqual(
            2, begin.count("units_before = tonumber(previous_units[field])")
        )

    def test_only_authoritative_final_targets_are_accepted(self):
        for target_id, sector in (
            (16929362, "North"), (16929363, "West"),
            (16929364, "East"), (16929365, "Central"),
            (16933563, "NW"), (16933564, "SW"),
            (16933565, "NE"), (16933566, "SE"),
        ):
            self.assertIn(f"[{target_id}] = '{sector}'", ADDON)
        self.assertIn("if not chest then return end", ADDON)

    def test_packet_parsing_prefers_untouched_data(self):
        helper = ADDON.split("local function parse_relevant_packet", 1)[1].split(
            "local function record_chest", 1
        )[0]
        self.assertIn("for _, raw in ipairs({original, modified}) do", helper)
        self.assertIn("predicate(packet)", helper)

    def test_observation_state_is_persisted(self):
        self.assertIn("state.runtime.pending_chest = pending_chest", ADDON)
        self.assertIn("state.runtime.units = {", ADDON)
        begin = ADDON.split("local function begin_chest", 1)[1].split(
            "local function finish_chest_if_ready", 1
        )[0]
        self.assertIn("persist_runtime_state()", begin)
        self.assertIn("coroutine.schedule(request_currency_two, 6)", begin)


if __name__ == "__main__":
    unittest.main()
