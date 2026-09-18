import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ADDON = (ROOT / "addons" / "LimbusTracker" / "LimbusTracker.lua").read_text(
    encoding="utf-8"
)


class LimbusTrackerDetection(unittest.TestCase):
    def test_final_coffer_detection_uses_three_packet_stages(self):
        self.assertIn("_addon.version = '0.5.1'", ADDON)
        self.assertIn("if id == 0x01A then", ADDON)
        self.assertIn("elseif id == 0x05B then", ADDON)
        self.assertIn("if id == 0x032 or id == 0x034 then", ADDON)
        self.assertIn("begin_chest(packet.Target, 'action', packet.Zone)", ADDON)
        self.assertIn("begin_chest(packet.Target, source, packet.Zone)", ADDON)
        self.assertIn("begin_chest(packet.NPC, 'menu', packet.Zone)", ADDON)

    def test_repeated_stages_preserve_the_currency_baseline(self):
        begin = ADDON.split("local function begin_chest", 1)[1].split(
            "local function parse_unit_acquisition", 1
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
            "local function parse_unit_acquisition", 1
        )[0]
        self.assertIn("persist_runtime_state()", begin)
        self.assertIn("coroutine.schedule(request_currency_two, 1)", begin)

    def test_currency_snapshots_cannot_create_chest_history(self):
        incoming = ADDON.split("windower.register_event('incoming chunk'", 1)[1].split(
            "windower.register_event('prerender'", 1
        )[0]
        self.assertNotIn("finish_chest_if_ready", ADDON)
        self.assertNotIn("record_chest(", incoming)
        self.assertNotIn("observe_acquisition(", incoming)
        self.assertIn("previous_units[field] = after", incoming)

    def test_direct_original_receipt_requires_a_pending_coffer(self):
        handler = ADDON.split("windower.register_event('incoming text'", 1)[1].split(
            "windower.register_event('outgoing chunk'", 1
        )[0]
        self.assertIn("parse_unit_acquisition(original)", handler)
        self.assertNotIn("modified", handler)
        observe = ADDON.split("local function observe_acquisition", 1)[1].split(
            "local function normalize_area", 1
        )[0]
        self.assertIn("expire_pending_chest()", observe)
        self.assertIn("observation and observation.area == area", observe)
        self.assertIn("if reason ~= 'confirmed' then return end", observe)
        self.assertNotIn("previous_units", observe)
        self.assertIn("'acquisition-message'", observe)

    def test_receipt_parser_handles_bundled_ffxi_lines_and_retains_raw_evidence(self):
        parser = ADDON.split("local function parse_unit_acquisition", 1)[1].split(
            "local function observe_acquisition", 1
        )[0]
        self.assertIn("for line in plain:gmatch('[^\\7\\r\\n]+') do", parser)
        self.assertIn("local area, amount = line:match(", parser)
        self.assertIn("note_detection('unit-text'", ADDON)
        self.assertIn("raw_hex=raw_hex", ADDON)

    def test_other_npc_interactions_clear_pending_before_the_final_target_allowlist(self):
        begin = ADDON.split("local function begin_chest", 1)[1].split(
            "local function parse_unit_acquisition", 1
        )[0]
        reset = begin.split("if pending_chest and target_id ~= pending_chest.target_id then", 1)[1]
        reset = reset.split("local area, chest = area_for_target", 1)[0]
        self.assertIn("pending_chest = nil", reset)
        self.assertIn("persist_runtime_state()", reset)
        packet_handlers = ADDON.split("windower.register_event('outgoing chunk'", 1)[1]
        packet_handlers = packet_handlers.split("windower.register_event('prerender'", 1)[0]
        self.assertNotIn("area_for_target(candidate.", packet_handlers)
        self.assertIn("if packet and packet.Category == 0 then", packet_handlers)
        self.assertIn("tonumber(candidate.NPC)", packet_handlers)


if __name__ == "__main__":
    unittest.main()
