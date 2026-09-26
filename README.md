# Typing Roguelite

A typing-driven pixel-art roguelite where every keystroke powers combat.

## Current Goal

Build a small playable vertical slice that proves the core loop:

```
words appear -> player types -> correct input triggers attacks -> enemies approach -> enemies die -> feedback/XP
```

The first prototype intentionally stays small. It is not the full game.

## Tech

- Godot 4.x
- GDScript
- Data-driven gameplay definitions
- GitHub for version control

## Prototype Scope

- 1 arena
- 1 player
- 3 weapons
- 3 effects
- 2 elemental reactions
- 10-15 upgrades
- 3 priority enemy types
- 1 elite
- 1 boss
- Standard Words and Narrative text modes
- 10-minute target run

See `docs/` for the current design and roadmap.

## Core Design Principles

- Typing is the primary control surface.
- Normal enemies are handled through continuous typing-powered combat.
- Priority enemies can interrupt the normal stream with direct typed commands.
- Different builds should reward different typing styles, not only raw WPM.
- Combat must remain readable even when the screen becomes chaotic.
- Content and balance should be data-driven so weapons, enemies, effects, and upgrades can be tuned without rewriting core systems.

## Status

Pre-alpha / prototype setup.
