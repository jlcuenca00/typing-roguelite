# Game Design

## High Concept

A pixel-art typing roguelite / bullet-heaven where the player stays focused on the keyboard. Continuous typing powers normal combat while dangerous priority enemies can demand direct typed commands.

The game should begin readable and restrained, then escalate into absurd chain-reaction chaos.

## Core Loop

1. Read the current typing stream.
2. Type accurately.
3. Correct inputs trigger combat effects.
4. Kill enemies and gain experience.
5. Choose upgrades that change how typing maps to combat.
6. Survive escalating waves and bosses.
7. Finish the run or continue deeper in Endless.

## Typing Layers

- Keystroke: frequent, low-impact effects.
- Word completion: primary weapon triggers.
- Perfect word: bonus proc.
- Streak milestone: stronger proc.
- Sentence completion: major payoff.
- Priority word: direct interaction with a dangerous enemy.

## Hybrid Priority Targeting

Most enemies are handled by the normal typing stream and automatic targeting.

Priority enemies occasionally display their own word or command. The player can interrupt normal typing, resolve the priority word, then resume the original stream exactly where it paused.

## Build Architecture

### Weapons
Define what attacks.

Examples:
- Pistol: word completion fires a strong shot.
- SMG: every correct keystroke fires a weak shot.
- Shotgun: completed words fire a spread.
- Railgun: word length scales damage.
- Arc Coil: perfect words release chain lightning.
- Mortar: sentence completion launches an AoE.

### Triggers
Define when something happens.

Examples:
- Correct Key
- Word Complete
- Perfect Word
- Long Word
- Short Word
- Repeated Letter
- Streak Milestone
- Sentence Complete
- Priority Enemy Kill

### Effects
Define what happens.

Prototype targets:
- Burn
- Shock
- Freeze

Later:
- Poison
- Blast
- Crit
- Ricochet
- Split
- Pull

### Reactions
Effects can combine into emergent results.

Prototype targets:
- Freeze + heavy impact -> Shatter
- Shock + explosive impact -> Overload

### Mutations
Rare rule-changing upgrades that alter typing behavior rather than simply adding stats.

Examples:
- Verbose: longer words, stronger word-completion effects.
- Short Fuse: short words trigger completion effects twice.
- No Corrections: backspace disabled, perfect-word effects amplified.
- Overtype: optional extra letters can be typed for a larger reward.
- Momentum: streak persists until a mistake.

## Text Modes

### Narrative
Contextual narrative and lore tied to gameplay events.

### Standard Words
Pure Monkeytype-style word streams with no story interruptions.

### Quotes
Longer natural sentences and quote-like material.

### Custom
Later feature allowing imported text or custom word lists.

Text style should not alter rewards or difficulty.

## Narrative Direction

The typed text can sometimes manifest in the world.

Example:
- "The lights went out." -> arena darkens.
- "Then we heard them coming." -> a wave begins.

The central question can gradually become whether the player is reading a record or causing it.

## Run Structure

Target full run: about 20 minutes.

- 0-5 min: Arrival
- 5-10 min: Disturbance
- 10-15 min: Escalation
- 15-20 min: Collapse
- ~20 min: final encounter

After victory:
- Return / Extract
- Continue / Endless

## Readability Priority

1. Typing text
2. Player
3. Priority enemies
4. Dangerous projectiles
5. Everything else

Typing text should sit close to the player, below the character, using a crisp readable font. Do not put the primary typing line at the bottom edge of the screen.
