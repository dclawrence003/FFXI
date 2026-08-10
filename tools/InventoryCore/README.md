# InventoryCore and LootAdvisor

InventoryCore is a local, read-only inventory intelligence service for a
Windower multibox roster. It combines FindAll exports, Windower item resources,
a local BG Wiki mirror, NPC resale data, and Valefor FFXIAH history.

LootAdvisor is its lightweight in-game Windower frontend. It reports a
recommendation for every treasure-pool item, including items no character
currently owns.

## Prototype status

This snapshot was built for six characters on Valefor. Character enumeration
is configuration-driven and already supports any roster size, but market
fetching is currently hard-coded to Valefor. Paths, job priorities, and the
designated crafter must be configured locally.

## Safety

- InventoryCore never lots, passes, sells, sends, or drops anything.
- LootAdvisor only prints recommendations.
- `DROP` requires an item ID in the explicit `dropAllowlist`, which starts
  empty.
- Missing AH data never produces an invented price.
- The HTTP service binds only to `127.0.0.1`.
- Runtime inventory and price data stays under `%LOCALAPPDATA%\FFXIInventory`
  and is excluded from this repository.

## Requirements

- Windows with Windower 4
- Windower's FindAll addon, loaded on each character
- Node.js 22.5 or newer with `node:sqlite`
- A local BG Wiki item-page mirror
- Internet access for rate-limited FFXIAH and LandSandBoat lookups

## Configure

Copy the example:

```powershell
Copy-Item .\config.example.json .\config.json
```

Edit:

- `paths.findAll`: FindAll's `data` directory
- `paths.itemsResource`: Windower's `res\items.lua`
- `paths.wikiItems`: the item directory in your local BG Wiki mirror
- `paths.lootAdvisor`: the installed LootAdvisor folder
- `characters`: one entry per character, with primary/secondary jobs
- `crafter`: `true` for the character that should receive crafting guidance
- `dropAllowlist`: item IDs explicitly approved for DROP recommendations

Do not commit `config.json`; it is ignored.

## Install LootAdvisor

Copy `windower\LootAdvisor` to:

```text
Windower\addons\LootAdvisor
```

Then load it in every desired client:

```text
//lua load LootAdvisor
```

LootAdvisor commands:

```text
//la pool
//la item <exact English item name>
//la reload
//la telemetry
```

Owned items use the generated recommendation cache. Unowned items query the
localhost service. If Valefor history is missing, the first response still
contains item/category/vendor guidance and queues a market refresh. Repeat
`//la pool` after a few seconds for the completed price.

## Start InventoryCore

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-InventoryCore.ps1
```

The launcher:

1. Refreshes FindAll, wiki, vendor, and cached market data.
2. Writes SQLite under `%LOCALAPPDATA%\FFXIInventory`.
3. Generates LootAdvisor's compact `data\recommendations.lua`.
4. Starts the localhost dashboard at <http://127.0.0.1:8787>.
5. Watches FindAll character files and refreshes after changes.

### Start automatically with Windows

Install the per-user scheduled task once:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-AutoStart.ps1
```

The task starts InventoryCore at logon, keeps the server attached to the task so
Windows can restart it after a failure, and does not open the dashboard. It
serves the existing database immediately; FindAll's file watcher performs the
next refresh after inventory changes. The launcher checks the normal Node.js
install locations and Codex's bundled Node runtime in addition to `PATH`.

Manual commands:

```powershell
npm test
npm run refresh
npm start
```

## Recommendation meanings

| Action | Meaning |
| --- | --- |
| `KEEP` | Wearable equipment aligned with a current or planned roster job |
| `UPGRADE` | Protected AF/relic/empyrean/Limbus or REMA progression reagent |
| `AH` | Marketable item with sufficient Valefor price/activity evidence |
| `VENDOR` | Safe material whose NPC resale beats weak or stale AH evidence |
| `HOLD` | Potential crafting use for the designated crafter |
| `REVIEW` | Insufficient evidence; never auto-drop |
| `DROP` | Explicitly allowlisted by item ID |

## Data sources and freshness

- FindAll files are watched continuously with a five-second debounce.
- FFXIAH results use a 12-hour local cache and rate-limited fetching.
- LandSandBoat `item_basic.sql` supplies a weekly cached NPC resale fallback.
- The local BG Wiki mirror supplies descriptions, uses, and progression
  classification.

## Current limitations

- Valefor is currently embedded in `src\ffxiah.js`.
- Wiki classification depends on the layout and freshness of the local mirror.
- AH recommendations are estimates from public history, not guarantees.
- There is no authentication because the service is localhost-only.

## Dashboard and character telemetry

The browser has three views:

- **Inventory** starts with current gil and two Limbus rotation panels, then
  shows the existing dense bag inventory.
- **Key Items** is a searchable roster matrix populated from each active
  Windower client.
- **Currencies** is a searchable roster matrix for every numeric field in the
  game's Currencies and Currencies 2 packets, including Nyzul tokens and
  Temenos/Apollyon units.

LootAdvisor is also the small Windower-to-InventoryCore telemetry bridge. Load
it on every tracked character. It posts only to the localhost service, sends a
full character snapshot once per minute, refreshes currency packets every five
minutes, and refreshes after login or zoning. `//la telemetry` forces an
immediate snapshot and currency request.

Limbus chest tracking is automatic. LootAdvisor identifies the active sector
from the area's temporary floor-data item, notices interaction with the final
Treasure Chest, and confirms the opening from the resulting 3,000- or
5,000-unit currency increase. InventoryCore retains a continuous per-character
history rather than resetting it weekly.

Each area displays the five most recent chest openings, marks the last 5,000
bonus in gold, and lists **Next** as the least recently opened of the four
sectors. Until all four sectors have been observed, it displays learning
progress instead. "Next" is a rotation recommendation, not a prediction of the
next bonus: the game may select the same bonus chest again.

Key items and currencies require LootAdvisor to be loaded on each tracked
character and InventoryCore to be running locally.

## Authorship

InventoryCore and LootAdvisor were generated by OpenAI Codex at the direction
of the repository owner.

The service reads output created by the user's installed FindAll addon.
FindAll's installed source identifies **Zohno** as its addon author and retains
a BSD-style copyright notice for **Giuliano Riccio**. FindAll source is not
bundled or modified.

[FFXIAH](https://www.ffxiah.com/),
[BG Wiki](https://www.bg-wiki.com/),
[LandSandBoat](https://github.com/LandSandBoat/server), FindAll, and
[Windower](https://github.com/Windower) remain independent data or software
projects. Their code and the user's local wiki mirror are not redistributed by
InventoryCore, and none is affiliated with or has endorsed this tool.
