"""Static and syntax guards for the FastFollow safe-zone candidate."""

from pathlib import Path
import re
import unittest

import os
import subprocess


ROOT = Path(__file__).parents[1]
SOURCE_PATH = ROOT / "candidate" / "FastFollow.lua"
SOURCE = SOURCE_PATH.read_text(encoding="utf-8")


class SafeZoneCandidateTests(unittest.TestCase):
    def test_candidate_is_valid_lua(self):
        node = os.environ.get('FFXI_TEST_NODE_EXE')
        self.assertTrue(node, 'Run through tools/OfflineTests/Invoke-Checks.ps1 -Suite FastFollow')
        parser = ROOT.parents[1] / 'tools' / 'OfflineTests' / 'parse-lua.cjs'
        subprocess.run([node, str(parser), str(ROOT / 'candidate')], check=True)

    def test_candidate_has_distinct_version(self):
        self.assertIn("_addon.version = '1.2.4-safezone'", SOURCE)

    def test_zone_request_branch_never_forges_or_blocks_packet(self):
        branch = SOURCE.split(
            "if id == PACKET_OUT.REQUEST_ZONE then", 1
        )[1].split("elseif id == PACKET_OUT.ACTION", 1)[0]
        self.assertNotIn("packets.new", branch)
        self.assertNotIn("packets.inject", branch)
        self.assertNotIn("packets.parse", branch)
        self.assertNotRegex(branch, r"\breturn\s+true\b")
        self.assertIn("Never block, copy, synthesize, or inject", branch)

    def test_legacy_zone_injection_worker_is_removed(self):
        self.assertNotRegex(SOURCE, r"\nfunction\s+zone\s*\(")
        self.assertNotIn("['Zone Line']", SOURCE)
        self.assertNotIn("zone_suppress", SOURCE)
        self.assertNotIn("zone_min_dist", SOURCE)
        self.assertNotIn("math.random", SOURCE)

    def test_signal_is_contextual_fresh_and_unique(self):
        self.assertIn("zonewalk %s %d %.6f %.6f", SOURCE)
        self.assertIn("seen_zone_signals[leader] == token", SOURCE)
        self.assertIn("age > zone_signal_max_age", SOURCE)
        self.assertIn("age < -zone_signal_future_tolerance", SOURCE)
        self.assertIn("info.zone ~= source_zone", SOURCE)
        self.assertIn("distance_squared >= max_dist", SOURCE)

    def test_injected_zone_packets_are_not_rebroadcast(self):
        self.assertRegex(
            SOURCE,
            r"if not injected and follow_me > 0 and self and info\s+"
            r"and tonumber\(info\.zone\)",
        )

    def test_nudge_is_cancelled_by_authoritative_client_events(self):
        self.assertIn("cancel_zone_nudge('natural-zone-request')", SOURCE)
        self.assertIn("windower.register_event('zone change'", SOURCE)
        self.assertIn("cancel_zone_nudge('zone-change')", SOURCE)
        for reason in (
            "command-stop",
            "command-stopall",
            "command-follow",
            "ipc-stop",
            "ipc-follow",
            "source-zone-left",
            "approach-timeout",
            "cross-timeout",
        ):
            self.assertIn(f"cancel_zone_nudge('{reason}')", SOURCE)

    def test_only_action_and_item_paths_still_inject(self):
        occurrences = [m.start() for m in re.finditer(r"packets\.inject\(", SOURCE)]
        self.assertEqual(len(occurrences), 2)
        action_branch = SOURCE.split(
            "elseif id == PACKET_OUT.ACTION", 1
        )[1].split("windower.register_event('zone change'", 1)[0]
        self.assertEqual(action_branch.count("packets.inject("), 2)

    def test_transition_trace_is_not_written_from_prerender_loop(self):
        prerender = SOURCE.split(
            "windower.register_event('prerender'", 1
        )[1].split("local PACKET_OUT", 1)[0]
        self.assertNotIn("io.open", prerender)
        self.assertIn("zone_trace_<character>.log", (ROOT / "README.md").read_text())


if __name__ == "__main__":
    unittest.main()
