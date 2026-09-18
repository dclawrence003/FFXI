from pathlib import Path
import os
import unittest


ROOT = Path(__file__).resolve().parents[1]
PARTYTACTICS = ROOT / "addons" / "PartyTactics" / "PartyTactics.lua"
GEARSWAP_PATCH = ROOT / "patches" / "GearSwap" / "cpu-hot-paths.patch"
MULTICTRL_PATCH = (
    ROOT / "patches" / "MultiCtrl" / "action-event-hot-path.patch"
)
LIVE_PARTYTACTICS = Path(
    r"C:\Program Files (x86)\Windower\addons\PartyTactics\PartyTactics.lua"
)
LIVE_GEARSWAP = Path(
    r"C:\Program Files (x86)\Windower\addons\GearSwap\gearswap.lua"
)
LIVE_TRIGGERS = Path(
    r"C:\Program Files (x86)\Windower\addons\GearSwap\triggers.lua"
)
LIVE_MULTICTRL = Path(
    r"C:\Program Files (x86)\Windower\addons\multictrl\multictrl.lua"
)
RELOAD_SCRIPT = ROOT / "tools" / "performance" / "reload_cpu_hotpaths_safe.txt"
LIVE_RELOAD_SCRIPT = Path(
    r"C:\Program Files (x86)\Windower\scripts\reload_cpu_hotpaths_safe.txt"
)


class PerformanceHotPathGuards(unittest.TestCase):
    def test_party_tactics_preserves_cadence_and_reapply_gate(self):
        text = PARTYTACTICS.read_text(encoding="utf-8")
        function = text.split("local function maintenance_tick(now)", 1)[1]
        function = function.split("windower.register_event('ipc message'", 1)[0]
        invocation = "issue('lua i GearSwap party_tactics_maintenance_tick')"
        self.assertIn(invocation, function)
        self.assertLess(
            function.index("not active or pending_reapply"),
            function.index(invocation),
        )
        self.assertIn("next_maintenance = now + MAINTENANCE_INTERVAL", function)
        self.assertNotIn("gs c pstart", function)

    def test_persistent_patches_keep_only_safe_hot_paths(self):
        gearswap = GEARSWAP_PATCH.read_text(encoding="utf-8")
        self.assertIn("diff --git a/gearswap.lua b/gearswap.lua", gearswap)
        self.assertIn("party_tactics_maintenance_tick", gearswap)
        self.assertNotIn("diff --git a/triggers.lua b/triggers.lua", gearswap)
        self.assertNotIn("data:unpack('I', 0x05)", gearswap)

        multictrl = MULTICTRL_PATCH.read_text(encoding="utf-8")
        self.assertIn("diff --git a/multictrl.lua b/multictrl.lua", multictrl)
        self.assertIn("-    if id == 0x028 then", multictrl)
        self.assertIn("+\tif not player or action.actor_id ~= player.id then", multictrl)

    def test_reload_is_staggered_six_client_and_inert(self):
        text = RELOAD_SCRIPT.read_text(encoding="utf-8")
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        self.assertEqual(lines[1], "send Dolomedes pt off")
        members = (
            "Dolomedes", "Tackleberry", "Kickpuncher",
            "Barneystinson", "Smalls", "Achoo",
        )
        for member in members:
            self.assertEqual(
                text.count(f"send {member} lua reload GearSwap"), 1
            )
            self.assertEqual(
                text.count(f"send {member} lua reload PartyTactics"), 1
            )
            self.assertEqual(
                text.count(f"send {member} lua reload multictrl"), 1
            )
        active = "\n".join(
            line for line in lines if not line.lower().startswith("echo ")
        ).lower()
        for forbidden in ("pt use", "pt arm", "pc on", "pc force"):
            self.assertNotIn(forbidden, active)
        if LIVE_RELOAD_SCRIPT.is_file():
            self.assertEqual(
                LIVE_RELOAD_SCRIPT.read_bytes().replace(b"\r\n", b"\n"),
                RELOAD_SCRIPT.read_bytes().replace(b"\r\n", b"\n"),
            )

    @unittest.skipUnless(
        os.environ.get('FFXI_TEST_INSTALLED') == '1'
        and LIVE_PARTYTACTICS.is_file()
        and LIVE_GEARSWAP.is_file()
        and LIVE_TRIGGERS.is_file()
        and LIVE_MULTICTRL.is_file(),
        "installed-file checks not requested or deployment unavailable",
    )
    def test_live_hot_paths_match_the_reviewed_design(self):
        self.assertEqual(
            LIVE_PARTYTACTICS.read_bytes().replace(b"\r\n", b"\n"),
            PARTYTACTICS.read_bytes().replace(b"\r\n", b"\n"),
        )

        gearswap = LIVE_GEARSWAP.read_text(encoding="utf-8")
        fast_lane = gearswap.split(
            "function party_tactics_maintenance_tick()", 1
        )[1].split("windower.register_event('load'", 1)[0]
        self.assertIn("refresh_globals(true)", fast_lane)
        self.assertIn("user_pcall('user_job_self_command'", fast_lane)
        self.assertNotIn("equip_sets", fast_lane)

        triggers = LIVE_TRIGGERS.read_text(encoding="utf-8")
        action = triggers.split("parse.i[0x028] = function (data)", 1)[1]
        action = action.split("local prefix = ''", 1)[0]
        actor_filter = "if act.actor_id ~= player.id and act.actor_id ~= pet_id then"
        self.assertGreater(action.index(actor_filter), action.index("parse_action(data)"))
        self.assertIn("get_mob_by_index(player.index)", action)
        self.assertNotIn("data:unpack('I', 0x05)", action)

        multictrl = LIVE_MULTICTRL.read_text(encoding="utf-8")
        incoming = multictrl.split(
            "windower.register_event('incoming chunk'", 1
        )[1].split("windower.register_event('action'", 1)[0]
        self.assertNotIn("0x028", incoming)
        self.assertNotIn("action_message", incoming)
        action_event = multictrl.split(
            "windower.register_event('action'", 1
        )[1].split("function poke_npc", 1)[0]
        actor_guard = "if not player or action.actor_id ~= player.id then"
        self.assertLess(action_event.index(actor_guard), action_event.index("isCasting"))
        self.assertIn("if not d2_active or not d2_current_target then return end", action_event)


if __name__ == "__main__":
    unittest.main()
