"""Failure controls for the lab's test collection and Lua completion marker."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent

class RunnerControls(unittest.TestCase):
    def test_python_functions_are_executed_and_empty_collection_fails(self):
        with tempfile.TemporaryDirectory(prefix='ffxi-runner-') as folder:
            def run():
                return subprocess.run([sys.executable, '-B', str(HERE / 'run-python-cases.py'), folder],
                                      capture_output=True, text=True)
            self.assertNotEqual(run().returncode, 0)
            path = Path(folder) / 'test_example.py'
            path.write_text('def test_failure():\n    assert False, "COLLECTION_FAULT"\n')
            failed = run()
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn('COLLECTION_FAULT', failed.stderr)
            path.write_text('def test_pass():\n    assert True\n')
            passed = run()
            self.assertEqual(passed.returncode, 0, passed.stderr)
            self.assertIn('Ran 1 test', passed.stderr)

    def test_lua_error_cannot_emit_completion_marker(self):
        node = os.environ['FFXI_TEST_NODE_EXE']
        with tempfile.TemporaryDirectory(prefix='ffxi-lua-runner-') as folder:
            path = Path(folder) / 'case.lua'
            command = [node, str(HERE / 'node_modules/fengari-node-cli/src/lua-cli.js'),
                       str(HERE / 'run-lua-case.lua'), str(path)]
            path.write_text('error("EXPECTED_LUA_FAULT")')
            failed = subprocess.run(command, capture_output=True, text=True)
            self.assertIn('EXPECTED_LUA_FAULT', failed.stdout + failed.stderr)
            self.assertNotIn('OFFLINE_LUA_CASE_COMPLETED', failed.stdout)
            path.write_text('assert(2 + 2 == 4)')
            passed = subprocess.run(command, capture_output=True, text=True)
            self.assertIn('OFFLINE_LUA_CASE_COMPLETED', passed.stdout)
