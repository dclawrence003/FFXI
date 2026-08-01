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


if __name__ == "__main__":
    unittest.main()
