# Combat Architecture

The combat layer is intentionally compositional. Typing events do not directly know which weapon fires, and weapons do not directly own elemental reactions.

## Pipeline

```
Typing input
   |
   v
Trigger event
(correct_key, word_complete, perfect_word, ...)
   |
   v
CombatSystem
   |
   +--> active weapons matching that trigger
   |
   v
Attack descriptors
(damage, projectile count, spread, tags, attached effects)
   |
   v
Hit resolution
   |
   +--> direct damage
   +--> status/effect application
   +--> reaction resolver
   |
   v
Reaction events
(Shatter, Overload, ...)
```

## Weapons

Weapons define **what attack is produced** when their trigger occurs.

Prototype weapons:
- SMG -> correct key
- Pistol -> word complete
- Shotgun -> word complete
- Arc Coil -> word complete (chained direct hits)

Weapon definitions do not hard-code elemental effects. This keeps "weapon" separate from "effect."

## Triggers

Triggers describe **when** combat logic should fire.

Current:
- `correct_key`
- `word_complete`

Planned:
- `perfect_word`
- `long_word`
- `short_word`
- `streak_milestone`
- `sentence_complete`
- `priority_enemy_kill`

The typing layer emits trigger IDs plus context. It does not contain weapon-specific branches.

## Effects

Effects are statuses that can be attached to weapons by a loadout or later by upgrades.

Prototype:
- Burn
- Shock
- Freeze

The prototype loadout binds:
- Freeze chance to SMG
- Shock chance to Pistol

Those bindings live in data, not in the weapon definitions.

## Damage Tags

Attacks can carry semantic tags such as:
- `kinetic`
- `blast`

Tags are not statuses. They describe the incoming attack and can participate in reaction rules.

## Reactions

Reaction definitions inspect:
1. statuses already active on the target
2. tags on the incoming attack

Prototype:
- Freeze + Blast -> Shatter
- Shock + Blast -> Overload

A reaction can consume one or more statuses and emit area damage or other future payloads.

## Why this structure

This lets upgrades compose behavior without creating a unique script for every combination.

Examples:

```
SMG
  + correct_key
  + Freeze attachment

Shotgun
  + word_complete
  + Blast tag

=> Freeze + Blast => Shatter
```

or later:

```
Perfect Word
  -> Arc Coil
  -> Shock

Sentence Complete
  -> Mortar
  -> Blast

=> Shock + Blast => Overload
```

The goal is for content growth to happen mostly through data and reusable systems rather than branching weapon code.


## Crowd-clearing run upgrades

Attack descriptors can carry `pierce`, `explosion_radius`, and `explosion_ratio`. The main scene resolves shared damage, statuses, Bulwark protection, and boss phase gates for projectile, chain, and splash hits through `_apply_combat_hit`.

`projectile_hits.gd` performs swept segment-circle collision and sorts hits by travel order. Each bullet tracks hit UIDs and a remaining hit count, so piercing cannot damage the same enemy repeatedly or skip enemies during a slow frame. Split Feed aims SMG projectiles at distinct visible normal targets when available. In-flight shots whose original target died can hit surviving enemies along their path.

The Arc Coil uses `attack_type: chain`, `chain_count`, and `chain_range`. Each enemy is hit at most once per trigger, with a nearest-neighbor search after each jump. Intrinsic weapon effects combine with upgrade attachments. Lightning visuals expire after 0.16 seconds and have a fixed feedback cap.

Explosive pistol hits queue splash after direct-hit resolution. Splash carries the Blast tag and can trigger Shatter/Overload; those reactions consume statuses and do not emit more projectile explosions. Waves wait for pending damage to drain before ending. Priority enemies and shielded boss phases remain immune to these normal damage paths.

Upgrade definitions include a category and maximum ranks. Each choice screen reserves one slot for an available crowd upgrade, while keeping command initials distinct and respecting weapon prerequisites and rank/effect-chance caps. The cards show the rank being offered. All changes reset with the run.

## Headless checks

From the repository root:

```sh
godot --headless --path game --script res://tests/horde_balance.gd
godot --headless --path game --script res://tests/crowd_combat.gd
```

The first checks 1,000 wave plans and fixed HP/XP invariants. The second checks projectile geometry, piercing, targeting, chains, splash/reactions, shields, boss gates, upgrade choices, reset behavior, and a stationary 200-enemy integration fixture. These checks validate mechanics; they do not establish real-player difficulty or visual readability.


## Increasing upgrade ranks

Upgrade definitions may provide a `ranks` array of overrides. `_upgrade_for_next_rank` reads the current pick count and creates a detached offer snapshot with its exact description and values. `_apply_upgrade` resolves raw definitions through the same helper; already-resolved offers are idempotent. Each ranked definition has exactly `max_picks` entries.

Optional per-rank `stat_bonuses` add secondary weapon stats after the main action. Higher Long Circuit ranks add jump range, and higher Burst Rounds ranks add blast radius. Damage, coverage, and secondary stats are earned only by upgrade picks; wave transitions do not grant attack modifiers or healing.

`godot --headless --path game --script res://tests/upgrade_ranks.gd` checks rank previews/application, caps, cumulative stats, boss phase protection, run reset, and no healing on wave completion/continuation.


## Horde formations and damage offers

The director now releases formations rather than one-to-three independently scattered enemies per spawn tick. `horde_formation.gd` generates compact rows outside one screen edge; every third pulse from wave 6 onward uses opposite fronts. A formation shares a base movement speed, with archetype multipliers preserving Runner/Brute identities. Pulse sizes grow from 8 to 120; the normal gap is approximately 3-4 seconds with pacing jitter. A timer schedules the next group, not each member.

The current pulse retains its entry positions and cursor when an active cap or priority/boss gate blocks spawning. Resume it before generating another pulse. Finishing or development-clearing a wave resets pulse state; the boss remains a separate finale after the authored horde, summons, queued damage, and XP particles resolve.

Upgrade offers reserve both a crowd card and a damage card when a compatible pair is eligible, then fill the remaining slot. Shared command initials cannot silently remove the damage slot. Four new weapon-specific payload cards add base damage, Echo Chamber adds pistol projectiles, and Drill Shot adds shotgun piercing. Wide Detonation requires Burst Rounds, while Reaction Bloom requires an actual reaction-capable build.

Flat payload additions apply before weapon multipliers and then global damage. Reaction Bloom multiplies Shatter/Overload radius; its multiplier resets with the loadout. Explosive and reaction radius remain separate stats.

Run `godot --headless --path game --script res://tests/horde_pulses.gd` for formation geometry, same-update group spawning, gaps, capacity/priority/boss waits, a 25-enemy Shatter cluster, damage offers, payload composition, Echo targeting, prerequisites, and reaction-radius reset checks.
