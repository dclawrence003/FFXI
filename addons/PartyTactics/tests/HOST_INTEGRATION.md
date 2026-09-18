# Host and puller integration

`test_locus_host_puller_integration.lua` extends the existing opener fixture
to route activation, commands and events through the actual stable GearSwap
host, versioned Locus adapter and LocusPuller addon.

The normal case verifies readiness, Flash/first-melee reservation timing,
timeout release, explicit stop and rejection of a late acknowledgement after
stop.  A separate process drops the real LocusPuller readiness acknowledgement
at the simulated command transport.  The same readiness assertion must fail
with its specific failure message.  Fengari can report Lua errors with exit
code zero, so the runner checks both output and exit status.

This is one-client component integration with simulated Windower boundaries.
SignetKeeper acknowledgement is still synthetic.  The PartyTactics coordinator,
six-client activation, full job files and retail behavior are not covered.
The injected fault is a test control, not proof of the historical startup cause.
No production behavior was changed to make this test pass.

For a separate six-client slice that executes PartyCombat as the real command
consumer, see [CONSUMER_LAB.md](CONSUMER_LAB.md). Its different mocks and scope
are listed explicitly; the two fixtures are not a single full-stack simulator.
