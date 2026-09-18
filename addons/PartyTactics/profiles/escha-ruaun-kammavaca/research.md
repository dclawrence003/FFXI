# Escha - Ru'Aun Kammavaca ordered-add party research

Retrieved and reviewed 2026-09-02. This document records the evidence and
decisions for profile `escha-ruaun-kammavaca` v1.2.0. The encounter state
machine and every exact enemy name remain local to this profile directory.

## Sources and encounter facts

- The locally cached [BG Wiki Kammavaca page](https://www.bg-wiki.com/ffxi/Kammavaca)
  identifies a level-125 Geas Fete NM in Escha - Ru'Aun. Kammavaca is assisted
  by a Clionid, Limule, Murex, and Amoeba. They must die in exactly that order;
  a wrong-order kill causes adds to respawn. The
  [Escha - Ru'Aun entity listing](https://www.ffxidb.com/zones/289/) and an
  [official version-update list](https://forum.square-enix.com/ffxi/threads/48564)
  give the exact in-game names as `Kammavaca's Clionid`, `Kammavaca's Limule`,
  `Kammavaca's Murex`, and `Kammavaca's Amoeban`.
- The same page says the alliance is drawn in and hit by Exponential Burst
  while adds remain. After the minions die, draw-in is limited to the
  character with the most hate.
- Kammavaca's landed melee attacks can inflict ten-second Amnesia. It casts
  tier-II Ancient Magic, tier-IV elemental -ga spells, and Meteor, and it can
  use Chainspell. Shell and layered healing therefore remain enabled.
- BG Wiki states that adds will not be summoned while Kammavaca is Silenced.
  It does not say whether this only prevents later summons or can suppress the
  initial pack. The runtime supports both observed outcomes without guessing.
- [Kammavaca's binding](https://www.bg-wiki.com/ffxi/Kammavaca%27s_binding)
  is purchased from Dremi for five Vedrfolnir's Wings. The local resource ID
  is 2944. Every participant also needs
  [Tribulens](https://www.bg-wiki.com/ffxi/Tribulens) or
  [Radialens](https://www.bg-wiki.com/ffxi/Radialens), IDs 2894 and 3031.
- The user-supplied
  [Kammavaca discussion page](https://www.bg-wiki.com/ffxi/Talk:Kammavaca)
  reports that the adds accepted Dream Flower, recommends Echo Drops, and
  warns about Slowga. It supports sleep-and-recovery control, but this profile
  uses the requested regular party with Barney as the primary sleeper.

The offline baseline is
`C:/Users/DC03/Documents/Tesseract/FFXI/reference/bg-wiki/mobs/kammavaca.md`,
with cached pages for the binding, lenses, and Bard mechanics. The cache is
the first research source when the live wiki blocks automated retrieval.

## v1.2 live-driven automation design

The first live clear exposed an orchestration problem: PartyCombat was
unloaded, so `//pc on` and `//pt force` had no handler. The next live attempt
showed that v1.1 solved that dependency but imposed the wrong fight policy.
Kammavaca dies quickly enough that waiting for affirmative Silence and
full-pack Sleep made the clear slower and less reliable. A boss action could
also move PartyCombat back to Kammavaca after a correct add force.

Version 1.2 therefore treats Silence and Sleep as useful, non-blocking support.
The only damage invariant is the mechanic the encounter actually requires:
any associated living add supersedes Kammavaca, and living adds are forced in
Clionid -> Limule -> Murex -> Amoeban order.

The bounded profile-local runtime now works as follows:

1. Activation turns native auto-target off on each client; deactivation
   restores it. PartyCombat remains the sole owner of selection, approach,
   engagement, and disengagement.
2. A live exact-name Kammavaca must be party-claimed before encounter logic
   begins. An exact add belongs to that encounter only if it is party-claimed,
   or if it is unclaimed (`claim_id` nil/zero), has valid x/y/z coordinates,
   and lies within 20 yalms of the active claimed boss. Any nonzero foreign
   claim is rejected even when nearby; an unclaimed add with missing or distant
   coordinates is also rejected.
3. Dolo cannot submit a combat force until the current six-client ACK and
   required preflight barrier is genuinely ready. Non-damaging support may
   queue before that barrier completes.
4. Smalls submits one semantic exact-ID Silence reservation to the RDM
   GearSwap priority queue. That controller owns next-action priority, casting,
   bounded retries, and completion; the fight runtime owns encounter-level
   rearm and its 40-second refresh cycle. The runtime does not cast Silence
   directly and never spends Stymie or Saboteur. Silence results are telemetry
   only and cannot block or choose a combat target.
5. Barney maintains Barsilencera before the encounter. When an add appears,
   PartyCombat selects the first legal CLMA ID on target-only Barney without
   engaging him. After his current target matches, the normal GearSwap Bard
   queue attempts Horde Lullaby II against `<t>` as its next action. Numeric-ID
   Bard casts remain prohibited. Sleep confirmation is telemetry, not a damage
   gate.
6. Dolo immediately submits the first legal CLMA ID even if Kammavaca was the
   previous lock or support is still pending. A desired-ID change bypasses all
   old throttles. If Dolo's current target drifts back to the boss, the runtime
   reasserts the add in a bounded three-request burst, cools down, and rearms
   while the add remains alive. Matching the desired target quiets the loop.
7. After each add dies, the next living legal CLMA ID is forced. Kammavaca is
   forced only when no associated add is visible. The initial boss-only path
   uses a short 0.75-second entity-settle window; any later add immediately
   supersedes the boss.
8. Target observation and queued sleep also use bounded rolling retry cycles.
   A transient startup, selection, or distance miss cannot permanently exhaust
   automation, but no loop can issue faster than its throttle.

All actions still pass through ordinary GearSwap/controller paths. The runtime
has no equip, instrument, slot-lock, raw movement, or packet interface. Existing
PLD, DNC, GEO, AutoWS2, Roller2, and HealBot controllers resume their normal
roles once PartyCombat establishes the exact target.

## Party strategy and safety boundary

Preflight verifies the lens, Dolo's binding, reviewed weapons, Silence and
Horde Lullaby II, recovery spells, and at least twelve Echo Drops in each
Inventory. The party stacks within Barney's effective Horde Lullaby coverage.
Dolo uses DualSavage/Savage Blade and Kick uses Tauret/Evisceration. Tackle and
Achoo engage for hate/geomancy with AutoWS2 Off. No AoE damage is used.

The legal progression is always **Kammavaca's Clionid -> Kammavaca's Limule
-> Kammavaca's Murex -> Kammavaca's Amoeban -> Kammavaca**. PartyCombat
revalidates each live target and distance; the profile additionally verifies
Dolo's current target and reasserts a living add after a boss drift.

Only queue-capable manual fallbacks remain in the profile: `//pt sleep` uses
Barney's current-target Bard queue, and `//pt silence` resolves party-claimed
Kammavaca before submitting the same RDM exact-ID queue request. Alt-L shares
the Bard queue. Built-in `//pt force` remains an explicit operator override and
bypasses automatic target choice; `//pt off` is the full emergency stop.

Recommended subjobs are COR/DNC (COR/NIN accepted), PLD/WAR, DNC/WAR, BRD/WHM,
RDM/WHM, and GEO/WHM. RDM/BLM remains optional only for emergency Sleepga or
Stun; the fast normal clear favors /WHM recovery. On a wipe or loss of control,
use `//pt off`, recover, let Confrontation end, restore the binding/lens state,
and pass a fresh preflight before another pop.

## First v1.2 live-review questions

1. Does the first legal add replace a boss lock within one 0.2-second profile
   poll on all four attackers?
2. Does Dolo remain on the forced add through boss action packets without
   excessive force chatter?
3. Does the RDM queue place Silence opportunistically without delaying cures?
4. Does Barney's queued Horde Lullaby occur promptly while ordered damage is
   already running?
5. Are all four spawned adds either party-claimed or within the documented
   20-yalm association bound of Kammavaca?
