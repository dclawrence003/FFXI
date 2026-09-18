from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SortieMainOwnershipTests(unittest.TestCase):
    def test_runtime_has_no_profile_or_global_stop_surface(self):
        text = (ROOT / "profiles/sortie-main-v1/runtime.lua").read_text(
            encoding="utf-8"
        )
        for forbidden in (
            "request_operator_state",
            "combat_stop()",
            "lua i PartyTactics",
            "'pc off'",
            "begin(",
        ):
            self.assertNotIn(forbidden, text)
        self.assertIn("combat_stop_members", text)
        self.assertIn("combat_force", text)

    def test_adapter_cannot_change_profile_or_partycombat_lifecycle(self):
        for version in ("1.1.0", "1.2.0"):
            text = (
                ROOT / f"gearswap/adapters/sortie-main-v1/{version}.lua"
            ).read_text(encoding="utf-8")
            for forbidden in (
                "lua i PartyTactics",
                "pt use",
                "pt off",
                "pt arm",
                "pt disarm",
                "pc off",
                "pc stop",
                "pc invalidate",
                "pc policy",
            ):
                self.assertNotIn(forbidden, text, version)

    def test_leshonn_adapter_preserves_manual_input(self):
        text = (
            ROOT / "gearswap/adapters/sortie-main-v1/1.2.0.lua"
        ).read_text(encoding="utf-8")
        self.assertIn("function M.filter_pretarget() return false end", text)
        self.assertIn("function M.filter_precast() return false end", text)
        self.assertNotIn("eventArgs.cancel", text)

    def test_legacy_sortie_profiles_are_explicit_recovery_only(self):
        ids = (
            "sortie-objective-c-magic-burst-v1",
            "sortie-objective-b-weapon-skill-v1",
            "sortie-objective-a-magic-kill-v1",
            "sortie-boss-skomora-v1",
            "sortie-boss-leshonn-v1",
            "sortie-boss-ghatjot-v1",
        )
        for profile_id in ids:
            text = (ROOT / "profiles" / profile_id / "profile.lua").read_text(
                encoding="utf-8"
            )
            self.assertNotIn("auto_select=", text.replace(" ", ""), profile_id)
            self.assertIn("Explicit recovery profile only", text, profile_id)


if __name__ == "__main__":
    unittest.main()
