# Offline addon checks

## Saved source packages

Use Python 3.11 or newer to build from an exact saved Git version:

```powershell
python tools/OfflineTests/release_package.py build . C:/private-output/candidate.zip
python tools/OfflineTests/release_package.py verify C:/private-output/candidate.zip
python tools/OfflineTests/release_package.py rehearse C:/private-output/candidate.zip C:/private-output/previous.zip
```

The output folder must already exist.  Build includes committed addon files
with a per-file SHA-256 manifest.  It excludes unsaved changes and refuses to
overwrite an existing package.  Verification detects missing, extra or changed
files.  Rehearsal restores the previous package in temporary folders only.
These commands do not deploy, reload clients or establish a tested game build.
Packages include source documentation and tests, so they are review artifacts,
not an automatic Windower installation.  PartyOps builds are not yet paired
with the addon manifest.

## Run tests

GitHub runs the same eleven suites on pull requests and changes to main using a
Windows runner, Node 24.18.0, Python 3.11 and the locked Lua packages.  Actions
are pinned to exact commits.  Reports are retained as workflow artifacts for
14 days.  This checks source without a Windower install or private PartyOps
repository; it does not deploy or verify loaded clients.

Run all eleven configured suites with one command:

```powershell
./tools/OfflineTests/Invoke-Checks.ps1 -NodeExe $node
```

Use `-Suite LocusPuller` (or another configured addon name) for a focused run.
Each run writes separate logs and a JSON result under ignored `reports/`.
The suite includes six addon groups plus InventoryCore, CoreManager local
configuration, ReleasePackage, FastFollow candidate guards and IncidentMemory. The
roster-specific installed GearSwap tests remain separate and have documented
failures in tools/PARTYOPS_ANALYSIS.md.
Failures remain failures even if another suite passes.  Machine-specific
Node/Python paths can be saved in ignored `local.settings.json` as
`node_executable` and `python_executable`, so future runs need no path argument.

The PartyTactics runner uses this folder's locked Lua tools.  It no longer
depends on a previous assistant task folder.  Use Node 24.18.0, the same
version pinned by PartyOps, PowerShell 7, and Python 3.11 or newer.

From the repository root, set `$node` to your Node 24.18.0 executable:

```powershell
$node = 'C:\path\to\node.exe'
./tools/OfflineTests/Initialize.ps1 -NodeExe $node
./addons/PartyTactics/tests/run_tests.ps1 -NodeExe $node
```

Setup downloads the exact packages in `package-lock.json`.  Package install
scripts are disabled.  Subsequent checks use the installed files offline.
Supply `-PythonExe` to the runner if Python is not available as `python`.

The ConquestCash, ExpeditionGuide, JubileeKeeper, LocusPuller and SignetKeeper
test runners use these same tools and accept the same `-NodeExe` and
`-PythonExe` parameters.  Their source and simulated-runtime checks do not
require the removed July task folder either.

Installed Windower file comparisons are excluded by default and reported as
skipped.  To include those read-only comparisons on a configured Windows
game machine, add `-IncludeInstalledChecks`.  Comparing installed files does
not establish which version a running client has loaded.

The suite parses PartyTactics Lua and runs the existing profile, adapter,
runtime, scaffold and Python source checks.  It does not launch a game,
reload addons, command clients or change PartyOps.  Existing simulated tests
still have limits: passing this suite does not prove an encounter works in
the game or reproduce the full real companion stack.

Fengari and fengari-node-cli are MIT-licensed projects.  luaparse is
MIT-licensed.  Their packages retain their upstream notices in
`node_modules`; dependencies are installed, not bundled in the addon.
