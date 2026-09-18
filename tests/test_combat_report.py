import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("combat_report", Path(__file__).parents[1] / "tools/combat_report.py")
report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(report)


class CombatReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.directory = self.root / "Smalls"
        self.directory.mkdir()

    def save(self, name, rows):
        path = self.directory / name
        path.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")
        return path

    def row(self, kind, at, seq, data=None):
        return dict(character="Smalls", session="test", seq=seq, time=at, kind=kind, data=data or {})

    def test_no_history_is_explicit(self):
        self.assertIsNone(report.latest_anchor(self.root))
        self.assertIn("NO READABLE HEARTBEAT", report.status(self.root, 1000))

    def test_status_requires_real_recent_disk_write(self):
        path = self.directory / "health.json"
        value = dict(heartbeat=1000, last_data_write=0, state=dict(recording=True))
        path.write_text(json.dumps(value), encoding="utf-8")
        self.assertIn("Smalls: NOT VERIFIED HEALTHY", report.status(self.root, 1001))
        value["last_data_write"] = 1000
        path.write_text(json.dumps(value), encoding="utf-8")
        self.assertIn("Smalls: RECORDING", report.status(self.root, 1001))
        self.assertIn("Smalls: NOT VERIFIED HEALTHY", report.status(self.root, 1100))

    def test_routine_and_incident_copies_are_deduplicated(self):
        rows = [self.row("snapshot", 1000, 1), self.row("incident", 1002, 2), self.row("death", 1002, 3)]
        self.save("combat-1.jsonl", rows)
        self.save("incident-1.jsonl", rows)
        loaded, warnings = report.load_window(self.root, 999, 1005)
        self.assertEqual(len(loaded), 3)
        self.assertFalse(warnings)
        self.assertEqual(report.latest_anchor(self.root), 1002)

    def test_partial_last_record_is_skipped_with_warning(self):
        path = self.save("incident-1.jsonl", [self.row("incident", 1000, 1)])
        with path.open("a", encoding="utf-8") as handle:
            handle.write('{"time":1001,')
        records, warnings = report.load_window(self.root, 999, 1005)
        self.assertEqual(len(records), 1)
        self.assertEqual(len(warnings), 1)

    def test_report_distinguishes_attempt_from_result_and_preserves_uncertainty(self):
        rows = [self.row("snapshot", 1000, 1, dict(vitals=dict(hp=1200, hpp=55, mp=5, mpp=1),
                    buffs=[dict(id=43, name="Refresh")], target=dict(name="Apollyon Demon"))),
                self.row("action_request", 1001, 2, dict(name="Cure IV", blocked=True)),
                self.row("death", 1002, 3, dict(victim=dict(name="Smalls"), source="hp_change"))]
        text = report.render_report(rows, 900, 1100)
        self.assertIn("MP 5 (1%)", text)
        self.assertIn("1 outgoing requests (1 blocked)", text)
        self.assertIn("Cure/Curaga results none", text)
        self.assertIn("not an automatic cause-of-death verdict", text)

    def test_newest_incident_anchor_uses_start_not_last_death(self):
        self.save("incident-1.jsonl", [self.row("incident", 1000, 1), self.row("incident", 1100, 2)])
        self.assertEqual(report.latest_anchor(self.root), 1000)

    def test_source_has_no_game_control_calls(self):
        addon = (Path(__file__).parents[1] / "addons/CombatRecorder/CombatRecorder.lua").read_text(encoding="utf-8")
        for forbidden in ("send_command(", "send_ipc_message(", "inject_incoming(", "inject_outgoing(",
                          "ffxi.run(", "ffxi.turn(", "ffxi.follow(", "ffxi.set_target(", "ffxi.set_player(",
                          "socket.http", "require('packets')", "windower.create_dir("):
            self.assertNotIn(forbidden, addon)


if __name__ == "__main__":
    unittest.main()
