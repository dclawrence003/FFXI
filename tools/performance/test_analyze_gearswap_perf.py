from pathlib import Path
import tempfile
import unittest

import analyze_gearswap_perf as analyzer


SAMPLE = """character,"Achoo"
duration_seconds,180.000
kind,event,calls,total_ms,average_ms,max_ms,over_1ms,over_5ms,over_10ms
"pipeline","precast",2,6.000000,3.000000,5.500000,2,1,0
"callbacks","precast",2,4.000000,2.000000,3.000000,2,0,0
"""


class GearSwapAnalyzerTests(unittest.TestCase):
    def test_reads_metadata_and_rows(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "gearswap-perf-Achoo-20260908-120000.csv"
            path.write_text(SAMPLE, encoding="utf-8")
            report = analyzer.read_report(path)
        self.assertEqual(report.character, "Achoo")
        self.assertEqual(report.duration_seconds, 180)
        self.assertEqual(report.rows[0]["calls"], 2)
        self.assertEqual(report.rows[0]["max_ms"], 5.5)

    def test_aggregate_uses_weighted_average_and_global_max(self):
        with tempfile.TemporaryDirectory() as folder:
            first = Path(folder) / "first.csv"
            second = Path(folder) / "second.csv"
            first.write_text(SAMPLE, encoding="utf-8")
            second.write_text(
                SAMPLE.replace('"Achoo"', '"Smalls"')
                .replace("2,6.000000,3.000000,5.500000,2,1,0", "1,9.000000,9.000000,9.000000,1,1,0"),
                encoding="utf-8",
            )
            rows = analyzer.aggregate(
                [analyzer.read_report(first), analyzer.read_report(second)]
            )
        precast = next(
            row for row in rows
            if row["kind"] == "pipeline" and row["event"] == "precast"
        )
        self.assertEqual(precast["calls"], 3)
        self.assertEqual(precast["total_ms"], 15)
        self.assertEqual(precast["average_ms"], 5)
        self.assertEqual(precast["max_ms"], 9)


if __name__ == "__main__":
    unittest.main()

