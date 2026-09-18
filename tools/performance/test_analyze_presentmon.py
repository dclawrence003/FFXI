from pathlib import Path
import tempfile
import unittest

import analyze_presentmon as analyzer


class PresentMonAnalyzerTests(unittest.TestCase):
    def test_percentile_interpolates(self):
        self.assertEqual(analyzer.percentile([10, 20, 30], 0.5), 20)
        self.assertEqual(analyzer.percentile([10, 20], 0.5), 15)

    def test_summary_reports_frame_tail_and_degradation(self):
        rows = []
        for second in range(10):
            frame = 20.0 if second < 5 else 40.0
            rows.append(
                {
                    "CPUStartTime": float(second * 1000),
                    "FrameTime": frame,
                    "CPUBusy": frame - 1,
                    "GPUBusy": 5.0,
                    "GPUWait": 2.0,
                    "PresentMode": "Composed: Flip",
                }
            )
        summary = analyzer.summarize(rows)
        self.assertAlmostEqual(summary["fps"], 1000 / 30)
        self.assertEqual(summary["over_33"], 50)
        self.assertGreater(summary["trend"], 90)

    def test_process_map_name_is_derived_from_capture(self):
        capture = Path("ffxi-presentmon-20260907-205517.csv")
        self.assertEqual(
            analyzer.process_map_path(capture).name,
            "ffxi-process-map-20260907-205517.csv",
        )


if __name__ == "__main__":
    unittest.main()
