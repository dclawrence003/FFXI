# PartyOps analysis tools

These adapters require a separately built private PartyOps source folder.
They reuse that implementation; the public repository does not include it.
Supply absolute paths through PARTYOPS_SOURCE_ROOT and PARTYOPS_STATE_ROOT.
Ambuscade and Sortie analysis also use WINDOWER_ROOT for resource catalogs.
Their existing positional path arguments still override the environment.
Missing paths fail before evidence is read.

The tools are analyze_ambuscade_run.mjs, analyze_sortie_run.mjs,
diagnose_locus_idle.mjs, diagnose_network_failure.mjs,
inspect_locus_partyops.mjs and inspect_partyops_live.mjs.  Their existing
time/character arguments and analysis behavior are unchanged.  Some retain
incident-specific defaults, so inspect those arguments before using them for
a new incident.  Their outputs are private evidence, not source to commit.

The private historical diagnostic command can inspect an explicitly selected
old session without current connectivity.  The older analysis adapters still
have their original current-session assumptions.

## GearSwap regressions

The lockstyle, accessory-slot and Achoo ring PowerShell runners now use the
locked tools/OfflineTests Lua runtime and require NodeExe and GearSwapRoot.
The ring comparison also requires GearFile and its original baseline folder.
They read the supplied files and execute extracted code with simulated game
boundaries.  They do not reload or command game clients.

These are roster-specific legacy tests, not part of the six portable addon
suites.  September 17 checks against installed files found two failures:
the lockstyle harness rejects the newer PartyTactics host include, and the
accessory test expects Andoaa Earring on a different side in Smalls' Enhancing
Magic set.  Neither result was treated as permission to change live gear or
weaken an assertion.  The ring comparison was not run without its historical
baseline.  validate_gearswap_runtime.lua accepts GEARSWAP_TEST_ROOT and retains
its legacy default for callers that have not yet been converted.
