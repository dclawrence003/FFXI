# AutoWS2

AutoWS2 is an experimental Windower addon for aftermath-aware weapon-skill
automation. It preserves ordinary threshold-based AutoWS behavior while adding
a measured, hard-latched AM3 reserve cycle.

The addon is a clean implementation inspired by **AutoWS 0.3.1 by Lorand**.
Lorand remains the author of the original AutoWS concept and addon. AutoWS2 is
not presented as an official update and does not require `lor_libs`.

## Why it exists

Typical aftermath automation waits until AM3 has already expired before it
starts saving 3000 TP. That can create a long period without AM3. AutoWS2
estimates recent TP generation and begins saving late in the existing AM3
window, attempting to arrive at 3000 TP near expiration.

Once active reserve mode begins, it is deliberately irreversible:

1. No weapon skill may fire below exactly 3000 TP.
2. At 3000 TP, AutoWS2 holds while AM3 remains active.
3. Only after the AM3 buff is confirmed absent may the configured aftermath
   weapon skill fire.
4. A newly gained AM3 buff releases the latch and restarts normal weapon
   skills.

This hard latch is the final defense against an early, lower-tier aftermath.

## Current status

Prototype. Start with `shadow` mode. Shadow mode reports decisions but does not
reserve TP or choose the aftermath weapon skill. It still performs the normal
configured weapon skill, so do not run original AutoWS or GearSwap AutoWS at
the same time.

The first tested profile is Tizona:

| Setting | Tizona default |
| --- | --- |
| Aftermath type | Level 3 |
| Aftermath WS | Expiacion |
| AM3 duration | 180 seconds |
| Fallback full-build estimate | 18 seconds |
| Minimum/maximum reserve | 4/30 seconds |
| Safety margin | 3 seconds |
| Initial mode | Shadow |

Tizona AM3 provides a 40% chance of attacking twice and a 20% chance of
attacking three times. The additional attacks substantially improve TP
generation; they are not conventional Haste or Double Attack.

Version 0.3 also supplies non-aftermath defaults for the current Ambuscade
weapons:

| Main weapon | Weapon skill | TP threshold |
| --- | --- | ---: |
| Naegling | Savage Blade | 1000 |
| Tauret | Evisceration | 1000 |
| Maxentius | Black Halo | 1000 |

These profiles keep aftermath disabled. Before issuing a weapon skill,
AutoWS2 checks Windower's current weapon-skill availability table. An unknown
or unavailable skill is blocked and reported once per profile/skill instead
of producing chat spam. Equipping the granting weapon or unlocking the skill
makes subsequent attempts eligible automatically.

Version 0.3.1 migrates the Naegling, Tauret, and Maxentius profiles to a
1000-TP threshold for immediate follower throughput. A future TP Bonus
offhand or deliberate hold strategy can still be configured with `//aws2 tp`.

## Predictor

AutoWS2 samples positive TP changes during engaged combat over a rolling
window. When enough data exists, it calculates:

```text
TP deficit = 3000 - current TP
reserve seconds = TP deficit / recent TP per second + safety margin
```

The result is clamped between the configured minimum and maximum. Until enough
data is available, the fallback full-build estimate is scaled by the remaining
fraction of 3000 TP, then the safety margin is added.

Version 0.2 migrates profiles still using the original 20/12/35/4 defaults to
18/4/30/3. Explicitly customized values are preserved. This removes the v1
error that forecast an entire 3000 TP build even when substantial TP was
already available. Once the remaining AM3 time enters the calculated window,
active mode latches reserve.

Large implausible one-tick TP jumps are excluded from training. Zoning, logout,
job changes, and weapon-profile changes reset the estimator.

## Unknown timers

Windower exposes aftermath buff presence but not a convenient remaining-time
value. AutoWS2 starts its internal timer when it observes the configured buff
being gained.

If AutoWS2 loads while AM3 is already active, it knows AM3 is present but not
its age. It continues normal behavior for that first partial cycle. When AM3
expires, active mode reserves to 3000 and applies it. Subsequent cycles have a
known timer.

The buff itself is authoritative:

- AutoWS2 never applies AM3 while the configured AM buff is still present.
- A timer reaching zero does not override an active buff.
- A lost-buff event immediately puts active mode into hard reserve.

## Installation

Copy the `AutoWS2` folder into:

```text
Windower\addons\AutoWS2
```

Load it:

```text
//lua load AutoWS2
```

Do not load original AutoWS at the same time. Disable GearSwap's own automatic
weapon-skill mode so there is only one WS decision-maker. GearSwap still sees
AutoWS2's normal `/ws` commands and equips the appropriate weapon-skill gear.

AutoWS2 always loads **off**. Configuration is saved per character, main job,
and equipped main weapon. Version 0.3 uses a separate
`data/settings_<Character>.xml` file for each client, preventing simultaneous
multibox profile saves from corrupting or overwriting a shared XML file. When
upgrading, copy the old `data/settings.xml` once for each character if its
existing profiles need to be retained.

## Recommended Tizona trial

Configure the normal WS, then observe shadow mode:

```text
//aws2 use Chant du Cygne
//aws2 aftermath on
//aws2 aftermath ws Expiacion
//aws2 aftermath duration 180
//aws2 aftermath mode shadow
//aws2 on
```

The display will show states such as:

```text
SHADOW
WOULD RESERVE
WOULD REAPPLY
```

After validating several full cycles:

```text
//aws2 aftermath mode active
```

Active mode states are:

```text
NORMAL
RESERVE
ARMED / HOLD
REAPPLY
```

## Commands

```text
//aws2 on
//aws2 off
//aws2 toggle
//aws2 status
//aws2 help

//aws2 use <normal weapon skill>
//aws2 tp <1000-3000>
//aws2 hp <minimum> <maximum>

//aws2 aftermath on
//aws2 aftermath off
//aws2 aftermath mode shadow
//aws2 aftermath mode active
//aws2 aftermath type lv1|lv2|lv3|relic
//aws2 aftermath ws <aftermath weapon skill>
//aws2 aftermath duration <seconds>

//aws2 aftermath reserve fallback <seconds>
//aws2 aftermath reserve min <seconds>
//aws2 aftermath reserve max <seconds>
//aws2 aftermath reserve safety <seconds>

//aws2 reserve reset
//aws2 display on
//aws2 display off
//aws2 display pos <x> <y>
```

`//aws2 reserve reset` is an explicit manual escape hatch. Turning the addon
off also releases the latch.

HP bounds are exclusive. The default `5 < target HP% < 100` avoids firing
immediately on engagement at 100% and avoids spending 3000 TP to maintain AM3
on a nearly defeated target.

## Safety limitations

- Automation cannot determine whether maintaining AM3 is worthwhile for the
  remaining lifetime of a target.
- Movement, invulnerability, terror, amnesia, or an inaccessible target can
  make the observed TP rate stale. Clamps and the safety margin reduce but do
  not eliminate this risk.
- The addon retries a failed WS command after its command cooldown if TP
  remains available.
- A configured WS that is not in the character's current available-ability
  table is never issued; check the main-hand weapon and job access if warned.
- Only one addon should own automatic weapon-skill decisions.
- This is third-party automation and is not supported by Square Enix or
  Windower.

## Attribution and license

AutoWS2 was generated by OpenAI Codex at the repository owner's direction. It
was designed after inspection of
[AutoWS 0.3.1 by Lorand](https://github.com/lorand-ffxi/addons/tree/master/AutoWS)
and intentionally retains explicit credit. The upstream repository does not
advertise a repository-level license through GitHub, so AutoWS2 does not
redistribute AutoWS source or `lor_libs`. AutoWS2's independently written
source contains its own BSD-style license and full disclaimer.
