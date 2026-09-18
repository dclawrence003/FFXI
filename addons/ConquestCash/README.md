# ConquestCash

`ConquestCash` is a Windower 4 addon for converting San d'Oria conquest points
to gil on six clients concurrently. Each client independently:

1. reads its current conquest-point balance and free Inventory slots;
2. buys as many Royal Squire's halberds as fit without crossing its saved CP
   floor or projected gil cap;
3. walks the short Northern San d'Oria route from **Achantere, T.K.** to
   **Pirvidiauce**;
4. verifies Pirvidiauce's first appraisal, sells only the exact inventory slots
   acquired by the current run, then returns to Achantere; and
5. repeats until another 4,000-point purchase would cross the floor.

The addon is intentionally specific to the current six-character setup: every
character must be pledged to San d'Oria and be able to buy rank-3 rewards. It
does not pathfind elsewhere in the city.

## Item and route choice

The intended fallback name was corrected from “Royal Squire Headband” to
**Royal Squire's Halberd** (item ID `16844`). It costs 4,000 CP. Among San
d'Oria rewards that do not depend on the weekly conquest placement, the
rank-3 halberd has the strongest dependable gil-per-CP ratio in the current
retail-derived item and conquest tables.

The fixed route is:

- purchase: **Achantere, T.K.**, Northern San d'Oria (C-8), retail entity ID
  `17723471`, conquest menu `32762`;
- sell: **Pirvidiauce**, Northern San d'Oria (D-8), retail entity ID
  `17723486`.

Pirvidiauce is a San d'Orian national shop and is about 35 yalms from
Achantere. National vendors use San d'Oria fame pricing, which can beat a
neutral Jeuno vendor at high fame. The addon prints the actual first appraisal
instead of assuming an exact payout. It refuses to sell if that quote is below
the default 4,000-gil sanity threshold.

References used for the candidate implementation:

- [BG Wiki: San d'Oria conquest rewards](https://www.bg-wiki.com/ffxi/Conquest_Points/San_d%27Oria_Items)
- [Windower packet definitions](https://github.com/Windower/Lua/blob/dev/addons/libs/packets/fields.lua)
- [LandSandBoat conquest implementation](https://github.com/LandSandBoat/server/blob/base/scripts/globals/conquest.lua)
- [LandSandBoat Northern San d'Oria entity data](https://github.com/LandSandBoat/server/blob/base/data/zones/northern_san_doria/npcs.yaml)

LandSandBoat is useful retail-derived evidence, not an authoritative statement
of the live server's current behavior. The first one-item canary below is
therefore mandatory before a six-client run.

## Transaction speed

Conquest gear is non-stackable, so there is no legitimate single transaction
that buys or sells an entire inventory. The addon removes menu navigation while
retaining one server transaction per item:

- purchases use the conquest event's validation response before finalizing;
- the native conquest menu and its event-parameter update are hidden while the
  addon owns the transaction, so they cannot capture local movement input;
- consecutive conquest purchases have at least a one-second post-purchase
  cooldown; an unanswered initial interaction is retried at most three times,
  but validation and finalized transactions are never retried;
- if all three Achantere interactions remain unanswered after at least one
  successful purchase, the addon drains possible late responses, vendors the
  safe partial batch, and retries after the normal round trip instead of
  stopping the run;
- if the client remains in Event status beyond the normal post-purchase
  cooldown, the addon applies one client-side menu-release sequence, then waits
  without sending another server transaction, vendors the safe partial batch
  as soon as Idle returns, and continues instead of timing out;
- after arriving at Pirvidiauce, the addon gives server-side position an extra
  moment to settle; an unanswered shop-open interaction is retried at most
  three times, but appraisal and sale-confirmation packets are never retried;
- the first sale is appraised and sanity-checked;
- later sales send the native appraisal/confirm pair, one item at a time, and
  wait for the server's completed-sale response plus the inventory removal;
- the shop is reopened every 40 completed sales to stay below the retail
  per-session distinct-slot limit.

It never uses SellNPC's instant whole-inventory flood. That is faster on paper,
but it cannot correlate individual failures and is a higher-risk packet pattern.

## Install

Copy the complete `ConquestCash` directory to `Windower/addons/` on the machine
that runs the six clients, then load it on each client:

```text
//send @all lua load ConquestCash
```

Do **not** start while another addon owns movement or mirrors/intercepts NPC
transactions. Prepare all six clients first:

```text
//send @all ffo stop
//send @all lua unload NpcInteract
//send @all lua unload SellNPC
```

NpcInteract is especially unsafe here: it can mirror ConquestCash's injected
NPC interactions and duplicate or corrupt the per-client state machines.
FastFollow can overwrite the same movement control. SellNPC can react to the
shop-open packet before ConquestCash has verified what it owns.

Place the characters at Achantere or Pirvidiauce, or on the unobstructed line
between them. Start is refused when a character is more than the configured
route tolerance from that corridor.

## Set the conquest-point floor

The floor is per-character and persists in a separate
`data/settings_<character>.xml` file. Separate files prevent six concurrent
clients from racing while they save their settings:

```text
//ccash floor 50000
```

Set the same floor on every loaded client in one command:

```text
//ccash all floor 50000
```

The floor cannot be changed while that client is active. Stop the run first;
this keeps the boundary fixed across any purchase already being validated.

The purchase condition is strict and simple:

```text
current CP - 4000 >= configured floor
```

For example, with 58,500 CP and a 50,000 floor, the addon buys two halberds and
stops at an estimated 50,500 CP. It will not buy a third.

## Progress HUD

Starting a run reveals a three-panel display for **CP**, **GIL**, and **ETA**.
It deliberately shares THHUD's original blue/silver/gold frame,
Consolas typography, value colors, dark outline, scale range, opacity range,
and drag-to-place workflow. The copied frame assets make ConquestCash
self-contained; THHUD does not need to be loaded. ConquestCash renders the
frame slightly larger than THHUD and uses a fixed, smaller value font so rapid
transaction updates never resize the text.

CP and gil use compact rounded notation to stay visually centered: `1,000`
becomes `1K`, `100,000` becomes `100K`, `1,000,000` becomes `1M`, and a value
such as `1,140,000` becomes `1.1M`. All three live values use THHUD's gold for
stronger contrast against the blue panel.

`CP` is the addon's latest server-reported or transaction-adjusted
conquest-point balance. `GIL` totals only completed vendor responses from
the current `start`; unrelated gil changes are excluded. `ETA` says `CALC...`
until one complete buy/move/sell cycle supplies a real measured rate. It then
uses a smoothed per-item cycle rate and includes already-purchased unsold items
in the remaining workload. ETA is rounded to minutes and uses compact,
unambiguous notation such as `37m`, `2h31m`, or `28h05m`; it never displays
seconds. A stopped run displays `PAUSED`, while a completed floor run displays
`DONE`.

The default position is directly below THHUD's default position. Settings are
saved independently for each character:

```text
//ccash hud show
//ccash hud hide
//ccash hud config [on|off]
//ccash hud pos <x> <y>
//ccash hud scale <0.5-3.0>
//ccash hud opacity <0-255>
//ccash hud reset
```

In placement mode, all three panels show representative values. Drag any
panel, then run `//ccash hud config off` to save the coordinated strip. Prefix
the command with `all` to apply the same display setting to all six clients.

## Required first live canary

Do this on **one character** before using `all start`:

1. Stand beside Achantere with exactly one free Inventory slot.
2. Stop FastFollow and unload NpcInteract and SellNPC on that client.
3. Set the floor so exactly one purchase is possible.
4. Run:

   ```text
   //ccash preview
   //ccash start confirm
   ```

5. Watch it buy one halberd, walk to Pirvidiauce, print the verified gil quote,
   sell that one slot, return, and stop at the floor.

If the menu ID, validation parameters, route, or sale response differs on the
live client, use `//ccash stop`, do not run all six, and capture one manual
purchase:

```text
//ccash capture start
```

Buy one Royal Squire's halberd manually from Achantere, then run:

```text
//ccash capture stop
```

The diagnostic file is written under
`Windower/addons/ConquestCash/data/capture_<Character>.log`. It contains only
the relevant parsed menu/transaction fields, not account credentials or chat.

Version `0.2.4-candidate` handles conquest validation as incoming packet
`0x05C` (the event-work update used by retail), blocks the owned native
conquest and shop menus, and tolerates intermittently dropped initial
interactions at Achantere or Pirvidiauce without ever retrying a purchase or
sale transaction. It accepts either the shop-open packet (`0x03E`) or the
following item-list packet (`0x03C`) as acknowledgement from Pirvidiauce.

## Six-client operation

After the one-item canary succeeds, give every character enough free Inventory
space and place all six on the route corridor:

```text
//ccash all status
//ccash all start confirm
```

The clients start with a small deterministic stagger (at most 0.59 seconds),
then operate independently and concurrently. No leader can spend another
character's points or advance another character's transaction.

Stop every client immediately with:

```text
//ccash all stop
```

Pressing a movement key stops the focused client. Combat, zoning, an unexpected
NPC/menu/item, loss of route progress, a changed run-owned inventory slot, a low
appraisal, or gil-cap risk also stops that client. Only an unanswered initial
NPC interaction can be retried. Exhausted Achantere interaction retries may
close and vend a nonempty partial batch, because no purchase has yet been
submitted. A completed, tracked purchase that leaves Windower reporting stale
Event status gets one local release attempt, then waits without moving or
sending another server transaction and vendors the partial batch when Idle
returns. Other timeouts after validation or finalization stop without retrying
the uncertain transaction.

## Commands

```text
//ccash help
//ccash status
//ccash floor <points>
//ccash preview
//ccash start confirm
//ccash stop
//ccash adopt confirm
//ccash resolve none confirm
//ccash resolve sale-none confirm
//ccash capture start
//ccash capture stop

//ccash all status
//ccash all floor <points>
//ccash all adopt confirm
//ccash all start confirm
//ccash all stop
```

`start confirm` is deliberate. It is a reminder that movement and packet-based
transactions are about to begin and that conflicting addons must be stopped.

## Recovery and limits

- While the addon remains loaded, stopping mid-run preserves the exact acquired
  slot list. Fix the reported problem and use `start confirm` to resume selling.
- If Windower still reports Event status after a completed purchase, the active
  run applies one standard local release sequence and stays in a safe release
  wait instead of timing out. A confirmed restart may enter the same recovery
  only when all completed halberds are already tracked and no purchase or sale
  result is pending. The release is client-side and cannot buy an item; no
  movement or server transaction occurs until Idle returns.
- The local menu-release sequence follows the established recovery used by
  EventGuard and Superwarp (credited to Ivaar). If that one attempt does not
  restore Idle, the addon keeps waiting rather than repeatedly altering client
  state or guessing at a server transaction.
- A timeout after the final purchase packet is deliberately never retried. Wait
  for the item update. If it never arrives, inspect both CP and Inventory and
  use `//ccash resolve none confirm` only after verifying that no purchase
  occurred.
- A stop or timeout after a vendor confirmation is likewise never retried. A
  delayed response is reconciled while the addon remains loaded. If it never
  arrives, verify that the item is still in its exact slot and that gil did not
  change, then use `//ccash resolve sale-none confirm`.
- Do not sort or move inventory while run-owned halberds are pending. A slot
  mismatch stops rather than selecting a replacement item.
- An unload/client crash intentionally does not guess which pre-existing
  halberds are expendable and a new run refuses to ignore them. After verifying
  that **every** Royal Squire's halberd in Inventory may be sold, use
  `//ccash adopt confirm` (or `//ccash all adopt confirm`) to restore tracking.
- The route is a straight, collision-aware progress check, not general city
  navigation. It stops if the direct path is obstructed.
- This is third-party automation, unsupported by Square Enix and Windower. Any
  packet-injecting or unattended automation may expose the account to action.

## Attribution and license

ConquestCash-specific code uses the MIT license in `LICENSE`.  The local
menu-release sequence comes through EventGuard from Superwarp by **Akaden
of Asura**, whose reset functions credit **Ivaar**.  The applicable upstream
BSD notice is retained in `ConquestCash.lua`; the MIT notice does not replace
it.  These authors have not endorsed ConquestCash.

Upstream: <https://github.com/AkadenTK/superwarp>

## Running the tests

From the repository root:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File addons/ConquestCash/tests/run_tests.ps1
```

The suite parses every Lua file and runs pure floor/inventory/route tests plus
a complete mocked purchase, movement, appraisal, sale, and floor-stop cycle.
