"""Run existing source-only addon cases with the locked Lua runtime.

Designed and directed by Don Lawrence; developed using OpenAI Codex.
Installed-client tests are deliberately excluded and listed in COVERAGE.md.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
LUA = {
    'EventGuard': ['test_runtime.lua'],
    'AutoWS2': ['smoke_harness.lua'],
    'PartyCombat': ['test_elemental_exclusion.lua'],
    'PartyStart': ['test_brd_reactions.lua', 'test_rdm_pull_silence.lua'],
    'CombatRecorder': ['test_recorder.lua', 'test_addon.lua'],
    'LimbusTracker': ['test_currency_correlation.lua'],
    'THHUD': ['run.lua', 'runtime_harness.lua'],
    'Roller2': ['decision_spec.lua', 'runtime_stop.lua'],
    'SalvageCells': ['test_runtime.lua'],
}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--suite', choices=LUA, required=True)
    parser.add_argument('--node', required=True)
    args = parser.parse_args()
    tests = ROOT / 'addons' / args.suite / 'tests'
    cli = ROOT / 'tools/OfflineTests/node_modules/fengari-node-cli/src/lua-cli.js'
    wrapper = ROOT / 'tools/OfflineTests/run-lua-case.lua'
    for name in LUA[args.suite]:
        cwd = tests.parent if args.suite == 'Roller2' else ROOT
        result = subprocess.run([args.node, str(cli), str(wrapper), str(tests / name)],
                                cwd=cwd, capture_output=True, text=True)
        output = result.stdout + result.stderr
        print(output, end='', flush=True)
        if result.returncode or 'stack traceback:' in output or 'OFFLINE_LUA_CASE_COMPLETED' not in output:
            raise RuntimeError(f'{args.suite}/{name} failed')
    if list(tests.glob('test_*.py')):
        env = dict(os.environ, FFXI_TEST_NODE_EXE=args.node, FFXI_TEST_INSTALLED='0')
        subprocess.run([sys.executable, '-B', str(ROOT / 'tools/OfflineTests/run-python-cases.py'),
                        str(tests)], cwd=ROOT, env=env, check=True)
    print(f'{args.suite}: configured source-only cases completed')

if __name__ == '__main__':
    main()
