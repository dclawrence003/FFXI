"""Optional Lua/real-filesystem round trip. Requires lupa with Lua 5.1."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    LuaRuntime = None

ROOT = Path(__file__).parents[1]
SPEC = importlib.util.spec_from_file_location("combat_report_io", ROOT / "tools/combat_report.py")
report = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(report)


@unittest.skipIf(LuaRuntime is None, "optional lupa Lua 5.1 runtime is unavailable")
class RealDiskRecorderTests(unittest.TestCase):
    def test_real_lua_io_creates_reportable_incident_and_health(self):
        with tempfile.TemporaryDirectory(prefix="ffxi-recorder-test-") as directory:
            root = Path(directory).resolve()
            character = root / "Smalls"
            character.mkdir()
            lua = LuaRuntime(unpack_returned_tuples=True)
            lua.globals().addon_source = (ROOT / "addons/CombatRecorder").as_posix()
            lua.globals().log_directory = character.as_posix()
            lua.globals().list_files = lambda path: lua.table_from([p.name for p in Path(path).iterdir()])
            lua.globals().file_exists = lambda path: Path(path).exists()
            lua.execute("""
                local json = dofile(addon_source .. '/lib/json_encode.lua')
                local storage = dofile(addon_source .. '/lib/recorder.lua')
                local now = 1800000000
                local r = storage.new({character = 'Smalls', directory = log_directory}, {
                    now = function() return now end, clock = os.clock, encode = json.encode,
                    open = io.open, remove = os.remove, exists = file_exists, list = list_files,
                })
                for i = 1, 310 do
                    r:record('snapshot', {vitals = {hp = 2000, hpp = 90, mp = 1000 - i, mpp = 70},
                        buffs = json.array(), target = {name = 'Apollyon Demon'}})
                    r:tick({recording = true, action_parser_available = true})
                    now = now + 1
                end
                r:mark('party_death', {victim = {id = 100, name = 'Smalls'}})
                r:record('death', {victim = {id = 100, name = 'Smalls'}, source = 'status_change'})
                r:record('diagnostic', {text = 'ASCII and escaped bytes: ' .. string.char(255)})
                r:close({recording = false, reason = 'test'})
                assert(r.last_write == now and r.queued_bytes == 0 and r.dropped == 0 and r.write_errors == 0)
            """)
            health = json.loads((character / "health.json").read_text(encoding="utf-8"))
            self.assertEqual(health["last_data_write"], 1800000310)
            self.assertFalse(health["state"]["recording"])
            anchor = report.latest_anchor(root)
            self.assertEqual(anchor, 1800000310)
            rows, warnings = report.load_window(root, anchor - 300, anchor + 120)
            self.assertFalse(warnings)
            self.assertEqual(sum(r["kind"] == "death" for r in rows), 1)
            self.assertEqual(sum(r["kind"] == "snapshot" for r in rows), 300)
            text = report.render_report(rows, anchor - 300, anchor + 120)
            self.assertIn("MP 690 (70%)", text)
            self.assertIn("Smalls (status_change)", text)
            self.assertIn("NOT VERIFIED HEALTHY", report.status(root, anchor + 1))


if __name__ == "__main__":
    unittest.main()
