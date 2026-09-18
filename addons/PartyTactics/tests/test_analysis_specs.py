import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROFILE_ROOT = ROOT / "profiles"


class AnalysisSpecTests(unittest.TestCase):
    def test_profile_sidecars_are_passive_and_well_formed(self):
        specs = sorted(PROFILE_ROOT.glob("*/analysis_spec.json"))
        self.assertGreaterEqual(len(specs), 2)

        for path in specs:
            with self.subTest(profile=path.parent.name):
                data = json.loads(path.read_text(encoding="utf-8"))
                self.assertEqual(data.get("schema"), 1)
                required = {
                    "schema",
                    "profile",
                    "encounter",
                    "difficulty",
                    "signals",
                    "metrics",
                    "outcomes",
                    "uncertainties",
                }
                optional = {"strategy", "dimensions", "promotion_gates"}
                self.assertLessEqual(required, set(data))
                self.assertLessEqual(set(data), required | optional)

                if "strategy" in data:
                    self.assertIsInstance(data["strategy"], dict)
                if "dimensions" in data:
                    self.assertIsInstance(data["dimensions"], dict)
                    for values in data["dimensions"].values():
                        self._unique_nonempty_strings(values)
                if "promotion_gates" in data:
                    self._unique_nonempty_strings(data["promotion_gates"])

                profile = data["profile"]
                self.assertEqual(profile.get("id"), path.parent.name)
                self.assertRegex(
                    profile.get("version", ""),
                    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$",
                )
                source = (path.parent / "profile.lua").read_text(
                    encoding="utf-8"
                )
                version = re.search(r"\bversion\s*=\s*'([^']+)'", source)
                self.assertIsNotNone(version)
                self.assertEqual(profile["version"], version.group(1))

                encounter = data["encounter"]
                self.assertIn(encounter.get("volume"), (1, 2))
                self._unique_nonempty_strings(encounter.get("boss_names"))
                self._unique_strings(encounter.get("add_names"))

                difficulty = data["difficulty"]
                self.assertIn(difficulty.get("operator_declared"), (True, False))
                if difficulty["operator_declared"]:
                    self.assertEqual(
                        difficulty.get("allowed"), ["VE", "E", "N", "D", "VD"]
                    )
                else:
                    self.assertEqual(difficulty.get("allowed"), [])

                signals = data["signals"]
                self.assertEqual(
                    set(signals),
                    {
                        "monster_ability_ids",
                        "weapon_skill_ids",
                        "spell_ids",
                        "job_ability_ids",
                    },
                )
                for values in signals.values():
                    self.assertIsInstance(values, list)
                    self.assertEqual(len(values), len(set(values)))
                    for value in values:
                        self.assertIsInstance(value, int)
                        self.assertGreater(value, 0)

                self._unique_nonempty_strings(data.get("metrics"))
                self.assertEqual(
                    data.get("outcomes"),
                    ["clear", "wipe", "timeout", "abort"],
                )
                self._unique_strings(data.get("uncertainties"))

    def test_combat_runtime_does_not_load_analysis_metadata(self):
        production = [ROOT / "PartyTactics.lua", *sorted((ROOT / "lib").glob("*.lua"))]
        for path in production:
            with self.subTest(path=path.name):
                self.assertNotIn(
                    "analysis_spec",
                    path.read_text(encoding="utf-8").lower(),
                )

    def _unique_strings(self, values):
        self.assertIsInstance(values, list)
        self.assertEqual(len(values), len(set(values)))
        for value in values:
            self.assertIsInstance(value, str)
            self.assertTrue(value.strip())

    def _unique_nonempty_strings(self, values):
        self._unique_strings(values)
        self.assertGreater(len(values), 0)


if __name__ == "__main__":
    unittest.main()
