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
