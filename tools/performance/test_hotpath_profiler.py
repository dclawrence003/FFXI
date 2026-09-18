from pathlib import Path
import os
import unittest


ROOT = Path(__file__).resolve().parents[2]
PERF = ROOT / "tools" / "performance"
LIVE = Path(r"C:\Program Files (x86)\Windower")


def normalized(path: Path) -> bytes:
    return path.read_bytes().replace(b"\r\n", b"\n")


class HotPathProfilerGuards(unittest.TestCase):
    def test_profiler_is_bounded_and_dormant(self):
        source = (PERF / "hotpath_profiler.lua").read_text(encoding="utf-8")
        self.assertIn("local MAX_SECONDS = 900", source)
        self.assertIn("local MAX_SLOW_SAMPLES = 256", source)
        self.assertIn("if not owner.enabled then return callback(...) end", source)
        self.assertIn("socket.gettime", source)
        self.assertIn("return unpack(results, 1, results.n)", source)

    @unittest.skipUnless(os.environ.get('FFXI_TEST_INSTALLED') == '1' and LIVE.is_dir(), "installed-file checks not requested")
    def test_live_profiler_and_scripts_match_reviewed_copies(self):
        pairs = (
            (
                PERF / "hotpath_profiler.lua",
                LIVE / "addons" / "libs" / "hotpath_profiler.lua",
            ),
            (
                PERF / "addon_hotpath_perf_start_all.txt",
                LIVE / "scripts" / "addon_hotpath_perf_start_all.txt",
            ),
            (
                PERF / "addon_hotpath_perf_stop_all.txt",
                LIVE / "scripts" / "addon_hotpath_perf_stop_all.txt",
            ),
            (
                PERF / "reload_addon_hotpath_profilers_safe.txt",
                LIVE / "scripts" / "reload_addon_hotpath_profilers_safe.txt",
            ),
        )
        for reviewed, deployed in pairs:
            self.assertTrue(deployed.is_file(), deployed)
            self.assertEqual(normalized(reviewed), normalized(deployed))

    @unittest.skipUnless(os.environ.get('FFXI_TEST_INSTALLED') == '1' and LIVE.is_dir(), "installed-file checks not requested")
    def test_live_addons_have_opt_in_hooks(self):
        sources = {
            "battlemod": LIVE / "addons" / "battlemod" / "battlemod.lua",
            "healbot": LIVE / "addons" / "HealBot" / "HealBot.lua",
            "healbot_utils": LIVE / "addons" / "HealBot" / "HealBot_utils.lua",
            "healbot_packets": LIVE / "addons" / "HealBot" / "HealBot_packetHandling.lua",
            "react": LIVE / "addons" / "React" / "react.lua",
            "party_tactics": ROOT / "addons" / "PartyTactics" / "PartyTactics.lua",
        }
        text = {name: path.read_text(encoding="utf-8") for name, path in sources.items()}
        self.assertIn("action_packet_parse_and_format", text["battlemod"])
        self.assertIn("action_message_packet", text["battlemod"])
        self.assertIn("decision_tick_20hz", text["healbot"])
        self.assertIn("select_action", text["healbot"])
        self.assertIn("command == 'perf'", text["healbot_utils"])
        self.assertIn("decode_0x028_action", text["healbot_packets"])
        self.assertIn("react_perf:wrap('action'", text["react"])
        self.assertIn("finish_sample('runtime_'..method", text["party_tactics"])
        self.assertIn("finish_sample('action'", text["party_tactics"])
        self.assertIn("finish_sample('prerender'", text["party_tactics"])
        self.assertEqual(
            normalized(sources["party_tactics"]),
            normalized(LIVE / "addons" / "PartyTactics" / "PartyTactics.lua"),
        )

    def test_start_and_stop_cover_all_profilers(self):
        start = (PERF / "addon_hotpath_perf_start_all.txt").read_text(encoding="utf-8")
        stop = (PERF / "addon_hotpath_perf_stop_all.txt").read_text(encoding="utf-8")
        for addon in ("GearSwap", "BattleMod", "HealBot", "PartyTactics", "React"):
            self.assertIn(f"lua c {addon} perf start", start)
            self.assertIn(f"lua c {addon} perf stop", stop)


if __name__ == "__main__":
    unittest.main()
