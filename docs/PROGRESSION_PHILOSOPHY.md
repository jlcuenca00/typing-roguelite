# Progression Philosophy

## Fresh Profile Should Feel Vulnerable

A completely fresh profile should be noticeably difficult.

The first runs are not meant to feel like a fully powered character with content merely waiting to be unlocked. The player should immediately feel the gap between:

- a fresh run with almost no permanent progression
- a developed profile with meaningful long-term upgrades
- a lucky or well-built run that becomes absurdly powerful

That gap gives failed runs a purpose: **come back stronger, build smarter, type better.**

## Important Constraint

"Hard at the beginning" must not become "the game decides you lose."

A skilled player should still be capable of doing unusually well on a fresh profile. Permanent progression should improve consistency and open possibilities, not replace player skill.

Fast and accurate typing is allowed to be an advantage. We should not dynamically inflate enemy health just because the player has high WPM; that would erase the value of becoming a better typist.

Difficulty should come from authored run pacing, enemy combinations, higher Depth levels, bosses, and limited early resources.

Movement speed is treated primarily as an archetype identity rather than a universal wave-scaling stat. Later waves should become harder mainly because there are more threats, denser arrivals, stronger combinations, and more dangerous specialist enemies—not because every Basic enemy quietly becomes much faster.

## Three Progression Layers

### 1. Run Power

Reset every run:

- weapons
- elemental attachments
- triggers
- stat upgrades
- mutations
- reactions and synergies

The run should start simple and end dramatically stronger.

### 2. Permanent Power

Earned between runs:

- modest base damage / survivability improvements
- rerolls and banishes
- stronger starting options
- small utility advantages
- additional build paths

Permanent raw power should remain capped enough that the run build still matters. A developed profile should feel clearly stronger than a fresh one, but not several times stronger before the run even begins.

### 3. Permanent Unlocks / Knowledge

- weapons
- mutations
- maps
- word pools
- narrative/archive entries
- higher Depth levels
- characters
- alternate starting options

## Desired First-Run Emotion

The player should finish an early failed run thinking:

> I can already see how ridiculous this could become if I get stronger.

Not:

> I was mathematically prevented from winning.

That distinction is the balancing target.


## Wave XP Economy

Waves use a fixed **threat budget**, not a fixed enemy count and not dynamic scaling from the player's damage.

At the start of a wave, the game spends that wave's budget on enemy archetypes. Cheap enemies consume little budget and produce a larger horde; tougher archetypes consume more budget and therefore reduce the raw body count. The plan is generated before the wave plays, so dealing more damage never causes the director to secretly spawn extra enemies.

Horde threat and XP use separate authored budgets. Each planned enemy receives a proportional integer share of the wave XP budget using cumulative rounding. Perfect clears preserve the original XP totals even as body counts increase; enemies that reach the player take their assigned XP with them. Summoned Swarmers remain worth zero XP.

Only a small recent roster is eligible in a wave. New archetypes enter as the run advances, allowing composition to escalate while HP stays fixed per archetype.

The current perfect-clear XP curve is deliberately shaped so the prototype trends approximately:

- Waves 1-5: usually 1 level-up each
- Waves 6-7: up to 2
- Waves 8-9: around 2 on a strong clear
- Wave 10: up to 3 on a near-perfect clear

These are ceilings, not guaranteed rewards. Wave 1 is the onboarding exception and always produces the first level-up. Late-wave budgets are intentionally more aggressive so the prototype can eventually test the dense, chaotic payoff without making early waves overwhelming.

This preserves the desirable feedback loop: stronger builds do not make the director cheat harder; they simply kill more of the same planned threat budget and therefore recover more of its available XP.


## Initial Fixed HP Horde Balance — 2026-10-22

The following records the initial pass; horde counts and pacing are superseded by the run-upgrade pass below. Fixed HP and XP rules still apply.

Enemy HP is authored in `enemies.json` as `base_hp * hp_multiplier` and never increases with wave number or elapsed time. Basic HP is 44; Runner 31.68; Brute 103.4; Jammer 68.2; Bulwark 81.4; Caller 72.6; summoned Swarmer 14.28. Elites keep their additional 1.55 multiplier and regeneration. The Overseer has a dedicated base of 84.5 (591.5 final HP), preserving its previous wave-10 strength before the old elapsed-time bonus.

Threat budgets: 8, 14, 22, 34, 52, 80, 116, 184, 312, 484.
Perfect-clear XP: 8, 12, 18, 28, 42, 68, 100, 160, 280, 440.

Double-spawn chances ramp from 15% at wave 5 to 60% at wave 8; waves 9-10 retain batches of 2-3. Wave 7 now uses a 45% double-spawn chance at a nominal 0.39-second interval, softening its batch transition while introducing its first elite. Existing active-enemy caps, priority gates, and boss finale gate still apply.

Next playtest: compare waves 6-8 at the same typing speed, confirm quicker ordinary kills and a fuller screen, then check waves 9-10 for crowd-clearing capacity and visual readability. This is a first balance pass, not a claim that the run is fully tuned.


## Run-upgrade and Horde Pass — 2026-10-22

Run upgrades now offer piercing, split SMG fire, explosive pistol shots, Arc Coil chain lightning, larger shotgun barrages, and stronger damage/status/reaction picks. At least one crowd-clearing option appears whenever an eligible one remains. Permanent progression and final difficulty tuning are deferred.

Threat budgets: 8, 18, 32, 52, 84, 136, 216, 340, 520, 760.
Nominal spawn intervals: 0.82, 0.68, 0.56, 0.46, 0.38, 0.32, 0.27, 0.23, 0.19, 0.16 seconds.
Active caps: 12, 20, 30, 44, 60, 80, 104, 132, 164, 200.
Perfect-clear XP totals remain 8, 12, 18, 28, 42, 68, 100, 160, 280, 440. HP remains fixed per archetype; enemy count still depends on composition and summon activity.

The next hands-on test should judge whether run upgrades produce satisfying clearing and build variety with these larger hordes. The eventual goal of making waves 3-4 very difficult on a profile without permanent upgrades is a later tuning target, not a constraint imposed during this pass.


## Clustered Horde Pulses — 2026-10-22

The previous run-upgrade pass still emitted individual enemies in tiny batches from random locations. That did not create enough local density for crowd reactions. Its spawn cadence and threat figures above are superseded by clustered formations.

- Bodies per pulse by wave: 8, 12, 18, 26, 36, 48, 64, 80, 100, 120.
- Threat budgets: 8, 22, 44, 76, 124, 196, 308, 476, 720, 1040.
- Active caps: 16, 32, 52, 80, 116, 160, 212, 272, 336, 400.
- Base gaps between pulses: 2.8, 3.0, 3.2, 3.4, 3.6, 3.8, 4.0, 4.0, 4.0, 4.0 seconds.

Pulses approach in compact rows from a shared front, with occasional two-front surrounds in later waves. They are subject to the existing safety cap, priority limits, and boss finale gate. Actual body counts still depend on archetype composition; perfect-clear XP and fixed HP are unchanged. No automatic healing is introduced.

The reference demo's `run_defaults.json` includes surround-pulse count/gap/share settings and `weapon_upgrade.json` includes weapon/global upgrade curves. These readable data files informed the direction, not an assertion that the demo's engine implementation was available or reproduced. Its assets and code are not imported.

There are now 29 run cards, including 11 explicitly categorized as damage. Each offer reserves one eligible damage choice and one compatible crowd choice. Bigger payloads amplify the existing damage ranks, while wider explosions and reactions make packed enemies useful for synergies. Permanent upgrades and final difficulty tuning remain deferred.
