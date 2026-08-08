"""Static guards for AutoWS2's safety-critical Lua branch."""

from pathlib import Path
import unittest


SOURCE = (Path(__file__).parents[1] / "AutoWS2.lua").read_text(
    encoding="utf-8"
)


class SourceGuardTests(unittest.TestCase):
    def test_exact_3000_guard_precedes_aftermath_check(self):
        reserve = SOURCE.index(
            "current_profile.aftermath_mode == 'active' and reserve_latched"
        )
        exact_tp = SOURCE.index("if tp ~= 3000 then", reserve)
        active_am = SOURCE.index("if aftermath_active then", exact_tp)
        reapply = SOURCE.index(
            "send_ws(current_profile.aftermath_ws", active_am
        )
        self.assertLess(reserve, exact_tp)
        self.assertLess(exact_tp, active_am)
        self.assertLess(active_am, reapply)

    def test_normal_ws_is_outside_hard_reserve_branch(self):
        reserve = SOURCE.index(
            "current_profile.aftermath_mode == 'active' and reserve_latched"
        )
        reserve_return = SOURCE.index("\n        return\n    end", reserve)
        normal = SOURCE.index("send_ws(current_profile.normal_ws", reserve)
        self.assertLess(reserve_return, normal)

    def test_tizona_defaults_to_shadow(self):
        tizona = SOURCE.index("if weapon == 'Tizona' then")
        end = SOURCE.index("\n    end", tizona)
        block = SOURCE[tizona:end]
        self.assertIn("profile.aftermath_enabled = true", block)
        self.assertIn("profile.aftermath_ws = 'Expiacion'", block)
        self.assertNotIn("aftermath_mode = 'active'", block)

    def test_reserve_forecast_uses_remaining_tp(self):
        self.assertIn(
            "local deficit = math.max(0, 3000 - (tonumber(tp) or 0))",
            SOURCE,
        )
        self.assertIn("local predicted = (deficit / rate) + safety", SOURCE)
        self.assertNotIn("local predicted = (3000 / rate)", SOURCE)

    def test_legacy_defaults_are_migrated(self):
        self.assertIn("local RESERVE_MODEL_VERSION = 2", SOURCE)
        self.assertIn(
            "profile.reserve_model_version = RESERVE_MODEL_VERSION", SOURCE
        )

    def test_current_ambuscade_weapon_defaults(self):
        for weapon, ws, tp in (
            ("Naegling", "Savage Blade", 1000),
            ("Tauret", "Evisceration", 1000),
            ("Maxentius", "Black Halo", 1000),
        ):
            block = SOURCE.split(f"elseif weapon == '{weapon}' then", 1)[1]
            block = block.split("\n    end", 1)[0]
            self.assertIn(f"profile.normal_ws = '{ws}'", block)
            self.assertIn(f"profile.normal_tp = {tp}", block)

    def test_unavailable_ws_is_blocked_without_chat_spam(self):
        send_ws = SOURCE.split("local function send_ws(name, reason)", 1)[1]
        send_ws = send_ws.split("\nend", 1)[0]
        self.assertIn("windower.ffxi.get_abilities()", send_ws)
        self.assertIn("last_ws_warning_key ~= warning_key", send_ws)
        self.assertIn("return false", send_ws)

    def test_multibox_settings_are_isolated_per_character(self):
        self.assertIn("data/settings_%s.xml", SOURCE)
        self.assertIn("settings_character", SOURCE)
        self.assertIn("config.load(settings_path, defaults)", SOURCE)


if __name__ == "__main__":
    unittest.main()
