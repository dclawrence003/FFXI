# LimbusTracker

LimbusTracker is a standalone Windower 4 addon that detects, records, saves,
and displays the modern Limbus chest rotation entirely in game. It does not
require LootAdvisor or InventoryCore to perform those functions.

## How it works

For each local character, the addon:

1. Recognizes only the four authoritative final-floor chest targets in
   Temenos and the four in Apollyon.
2. Ignores unrelated Limbus interactions, including the roaming `???` that
   can also award 3,000 units.
3. Matches the local character's original `Acquired Temenos Units: ...` or
   `Acquired Apollyon Units: ...` system message to that coffer interaction.
4. Records the actual 3,000-to-5,000-unit receipt, independently of currency
   balance snapshots. Small kill/Code gains do not confirm a coffer.
5. Saves the event immediately under its own `data` directory.

History is not reset at the weekly tally. It remains available after zoning,
logout, Windower reloads, and computer restarts.

Version 0.5.1 fixes acquisition parsing for **multi-line FFXI messages**.
The visible `Acquired`, `Remaining`, and `Total` lines can arrive in one
incoming-text callback, separated by FFXI's `0x07` line break. Version 0.5.0
incorrectly anchored its match to the end of the entire message, rejecting
that complete receipt even though the individual Acquired line was valid.
Color controls are now removed first (a color argument can also be `0x07`),
then the parser checks each logical line. CR/LF-separated variants work too.
Only the Acquired line supplies the reward; Remaining/Total never do.

While a coffer is pending, unit-related messages also retain their original
bytes (up to 512 bytes, hex-encoded), chat mode, and parse result in the bounded
diagnostic trail. Rejected unit messages are retained as well as accepted ones,
so another formatting problem does not erase the evidence needed to fix it.

Version 0.5.0 replaces currency-difference inference with acquisition-message
confirmation. Balance snapshots are not transaction receipts: they can combine
a Code, kill rewards, spending, and a coffer, or already include the coffer by
the time its interaction is observed. The August 30 North miss was consistent
with 54,830 + 2,170 from a Code + 3,000 from the coffer = 60,000. The final
North target and all interaction stages were captured, but the old balance
gate never saw an isolated +3,000. Increasing polling frequency or rebasing
the counter could not make that inference reliable.

The new listener uses the untouched original system message, even if another
addon hides or reformats the displayed copy. It never changes chat filtering.
An acquisition without a pending recognized coffer is ignored; a different
NPC interaction cancels the pending coffer. No area-wide or party-wide reward
is copied to another character. Balance packets now update status/diagnostics
only and **cannot create, label, or clear a chest opening**.

The last 48 structured detection observations are saved under
`runtime.observations` in each character's history: coffer stages, relevant
balance changes, acquisition amounts/decisions, cancellation, and expiry.
This is a bounded local diagnostic trail, not a general chat or packet log.
`//lt status` includes the loaded version so deployment can be checked.

### Earlier detection revisions (superseded by 0.5.0)

Version 0.4.5 clears and saves a pending coffer observation as soon as a real
interaction with a different object is seen. This applies at the initial
click, incoming NPC menu, and outgoing dialog stages, including injected or
mirrored interactions. A Code shiny's 3,000-unit reward therefore cannot satisfy
an abandoned coffer request. The shiny still updates the currency balance but
does not create chest history. Repeated packets for the same coffer preserve
its observation, and combat actions do not clear it.

Version 0.4.4 advances the pending coffer's baseline when a currency refresh
reports a separate non-chest gain or spending before the reward. For example,
12,420 -> 12,504 (+84 earned separately) -> 17,504 now correctly records the
SE coffer's 5,000-unit bonus. Earlier versions froze the initial 12,420 balance
and rejected the apparent 5,084 total. The updated balance and pending coffer
are saved together, including across reloads. An ambiguous 5,084-unit change
in a **single** update is still not rounded into a bonus.

Version 0.4.3 reads the untouched packet before any addon-modified copy,
derives the Limbus area from the authoritative coffer target rather than a
timing-sensitive live-zone lookup, and persists the currency baseline and
pending coffer observation immediately. This prevents another addon, a zone
state timing race, or a LimbusTracker reload from silently discarding the
coffer-to-reward correlation. Ordinary 3,000-unit Code and roaming `???`
rewards still cannot create history by themselves.

Version 0.4.2 recognizes each final coffer through three independent packet
stages: the initial action, the server's NPC menu, and the outgoing dialog
choice. This covers normal, injected, and mirrored interactions while retaining
the authoritative eight-target allowlist. Multiple stages for one opening share
one preserved currency baseline and therefore cannot create duplicate history.
The pending observation window is two minutes, measured from the latest stage.
In 0.4.4, packet stages preserve the current pre-reward balance; subsequent
currency observations, not repeated menu packets, may advance that balance.

Version 0.4.1 added migration of older local history on load: unrecognized
targets are removed and recognized final-chest targets are relabeled from the
authoritative mapping. This repairs stale temporary-item labels left by 0.3.x.

## Installation

Copy the complete folder to `Windower\addons\LimbusTracker` and load it on
every character whose openings should be tracked:

```text
//lua load LimbusTracker
```

After updating an active six-character setup, copy the included
`scripts\reload_limbustracker_safe.txt` to `Windower\scripts` and run this once
from any client:

```text
//exec reload_limbustracker_safe.txt
```

The script reloads one client every two seconds instead of reloading all six
simultaneously.

Every client writes only its own file:

```text
Windower\addons\LimbusTracker\data\history_<character>.lua
```

Separate files prevent six Windower processes from overwriting one another.
Writes use a temporary file and recoverable `.bak` replacement. The roster
view reads the character history files that currently exist in this folder.

## Display

The default `limbus` mode automatically appears in Temenos or Apollyon and
hides everywhere else. Settings and display coordinates are stored separately
for each character.

The self view shows:

- the least recently opened sector as `Next` once all four are learned;
- the most recently confirmed bonus receipt (more than 3,000 units) as `Bonus`;
- the five latest openings, newest first;
- `5*` for 5,000 received and `3` for 3,000 received; a capped 4,000-unit
  bonus, for example, appears as `4*` without rounding its actual award.

Example:

```text
LimbusTracker [Dolomedes]
Temenos  Next: West  Bonus: Central
  Recent: North:3 > Central:5* > East:3 > West:3 > North:3
Apollyon  Next: NE  Bonus: SW
  Recent: NW:3 > SW:5* > SE:3 > NE:3 > NW:3
```

`Next` is a rotation recommendation, not a prediction of the next bonus. The
game can choose the same 5,000-unit bonus chest again.

Storage caps can hide the nominal bonus: a bonus coffer can pay only 3,000.
A 3,000 receipt is still recorded as an opening, but is not proof of a bonus
or proof that it was an ordinary coffer. The tracker does not guess. More
than 3,000 does prove a bonus, even when the payout is clipped below 5,000.

## Commands

```text
//lt status
//lt refresh
//lt toggle
//lt mode limbus
//lt mode always
//lt mode off
//lt view self
//lt view roster
//lt pos <x> <y>
//lt sync on|off|now
//lt record apollyon|temenos <sector> 3000|5000
```

- `limbus` shows the panel only inside Temenos or Apollyon.
- `always` keeps it visible everywhere for setup or review.
- `off` hides it while leaving collection active.
- `self` shows full history for the local character.
- `roster` reads all saved character files and shows each character's next
  Temenos and Apollyon sector.
- `refresh` reloads the local character's history from disk.
- `record` repairs a missed opening when its sector and award are known. For
  example: `//lt record apollyon sw 5000`.

Collection remains active while the display is hidden.

## Optional InventoryCore mirror

Standalone tracking and persistence do not use InventoryCore. When the
localhost InventoryCore service is present, the default `sync on` setting also
mirrors confirmed events to its browser dashboard. Failed syncs remain marked
in the local history and are retried, so an unavailable service does not lose
the in-game record.

Disable this optional integration without affecting tracking:

```text
//lt sync off
```

## Detection limitations

- Acquisition parsing currently recognizes the English FFXI system message,
  including multi-line receipts, color controls, and comma-formatted amounts. It observes the
  original incoming text, not the addon-modified display text.
- LimbusTracker still requests Currencies 2 for informational balances on
  load/login/zoning, interactions, and every five minutes. No baseline,
  combined updates, spending, or an already-updated balance blocks a receipt.
- An award is intentionally ignored unless it follows interaction with one of
  the eight recognized final-floor rotation chests. This prevents roaming
  3,000-unit `???` rewards from polluting rotation history.
- Interacting with another object clears the pending final-coffer observation
  immediately and persists that cancellation across reloads. Only another
  recognized final-coffer interaction can start a new observation.
- The tracker listens for the initial action, incoming NPC menu, and outgoing
  dialog choice. It prefers the untouched packet over copies modified by other
  addons. Seeing several stages for the same coffer extends one pending event
  without replacing the original interaction or creating duplicate openings.
- Repeated packets or interactions for the same final chest within five
  minutes are treated as one opening.
- Load it before opening the chest. Loading it for the first time after the
  reward cannot reconstruct an earlier event.
- If the original acquisition event never reaches Windower, the tracker will
  not guess from the final balance. A coffer observation expires after two
  minutes; the diagnostic trail explains what was observed.
- Receipts below 3,000 are not classified as coffer rewards because small
  combat gains can arrive while a coffer is pending. A capped amount of
  exactly 3,000 cannot reveal whether the nominal chest was a bonus.

## Regression checks

`tests/test_currency_correlation.lua` executes the actual addon with isolated
in-memory files, packet/text events, time, and HTTP. It covers all eight final
targets, Code exclusion at every interaction stage, the North 2,170 + 3,000
case, the earlier 84 + 5,000 case, misleading exact balance changes, no
baseline, already-paid balances, original/hidden/formatted text, capped
bonuses, reloads, duplicate receipts, expiry, and offline mirror retry.
The full three-line Tackleberry North receipt is a regression fixture, along
with both areas and `0x07`, LF, and CR/LF separators. Tests check that neither
Remaining nor Total can be mistaken for the reward and that diagnostic bytes
survive a rejected match.
`tests/test_limbustracker_detection.py` guards the detector's source boundaries.

## Authorship and license

LimbusTracker was generated by OpenAI Codex at the direction of Dolomedes. It
is original integration code using Windower's documented addon APIs and
bundled `texts`, `config`, `packets`, `socket.http`, and `ltn12` libraries. It
does not contain code from LootAdvisor, FindAll, BG Wiki, FFXIAH, or
LandSandBoat. The final-chest target identifiers were validated against live
packets and cross-checked with Superwarp's Limbus support (Superwarp by Akaden;
Apollyon/Temenos support credited there to Staticvoid). No Superwarp source
code is incorporated.

The acquisition message wording was cross-checked against
[LimbusHelper by Kaius @ Bahamut (djlabbe)](https://github.com/djlabbe/LimbusHelper/blob/main/limbusHelper.lua).
The author's [discussion of capped rewards](https://www.ffxiah.com/forum/topic/58899/limbushelper-find-the-5000-unit-chest)
also documents why a 3,000 payout need not reveal the nominal bonus. No
LimbusHelper source code is incorporated. The original-message callback is
documented in [Windower's Events API](https://github.com/Windower/Lua/wiki/Events).
The compound Acquired/Remaining/Total message with embedded `0x07` separators
is also preserved in [Nynja's firsthand Limbus message report](https://www.ffxiah.com/forum/topic/58447/limbus-2025/63/).
The local three-line reward amounts in the regression fixture come from
Tackleberry's August 30 screenshot, not from that discussion.

The source carries a BSD 3-Clause license header. Windower and the referenced
projects remain independent and have not endorsed this addon.
