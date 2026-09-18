# Sortie regular-Demisang sweep canary

## Objective boundary

Sheet D is the sector-D traversal reward for defeating every regular Demisang
and then interacting with Diaphanous Bitzer #D. Demisang Deleterious is not
part of the required clear. Community references describe a large population
of regular Demisang, so this first attempt is a timing and control canary, not a
guaranteed same-run completion.

Primary/community references consulted 2026-09-09:

- BGWiki Sortie category: https://www.bg-wiki.com/ffxi/Category%3ASortie
- BGWiki Sortie strategies: https://www.bg-wiki.com/ffxi/Sortie_Strategies
- FFXIAH early Sortie guide: https://www.ffxiah.com/node/469

## Chosen control model

The existing COR/PLD/DNC/BRD/RDM/GEO composition is preserved. This v1 profile
is intentionally adapter-free and stationary. The operator moves the party,
chooses exact targets, and decides how many linked enemies to handle. Tackle
establishes each pull; Dolo selects the intended regular Demisang and presses
Ctrl-P or uses `//pt force`. The profile supplies all-six physical offense and
the already reviewed physical support presets.

There is deliberately no target-name exclusion. PartyCombat's current generic
exclusion vocabulary cannot express "regular Demisang but not Demisang
Deleterious" without a shared-core change. The profile therefore reports the
boundary to the operator instead of pretending it can enforce it. Accidentally
or deliberately fighting Deleterious remains possible and never locks manual
control.

## Canary observations to capture

- Remaining run time after the all-six Key B chest is secured.
- Number and arrangement of linked packs the party can handle comfortably.
- Whether all six stationary attackers begin each selected target in range.
- Practical full-clear time and whether any regular Demisang was missed.
- Whether touching Bitzer D after the apparent clear produces the all-six
  Sheet D chest evidence.

If the sweep is incomplete, exit or salvage other objectives normally. Do not
turn a missing Sheet D chest into a wait gate, and do not broaden shared combat
code from this one canary.
