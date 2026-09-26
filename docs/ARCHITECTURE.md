# Architecture

## Engine

Godot 4.x with GDScript.

The project is intentionally structured so high-volume gameplay does not depend on thousands of heavyweight scene nodes.

## Performance Philosophy

For large hordes:

- Centralize enemy simulation.
- Pool or batch projectiles and effects.
- Avoid a CharacterBody2D + collision tree + timer + script per simple enemy.
- Use lightweight data objects for simple enemies.
- Add spatial partitioning when needed.
- Move rendering to MultiMesh / RenderingServer if normal Node2D rendering becomes the bottleneck.
- Move only proven hot paths to GDExtension/C++ if profiling justifies it.

Godot handles:
- windowing
- input
- text rendering
- UI
- audio
- scene management
- shaders
- localization

Our systems handle:
- typing state
- proc resolution
- enemy simulation
- targeting
- projectile simulation
- effects/reactions
- wave spawning
- data-driven content

## Data Direction

Final gameplay content should trend toward external definitions:

```
game/data/
  weapons/
  triggers/
  effects/
  reactions/
  mutations/
  enemies/
  difficulties/
  narrative/
  words/
```

Core logic should understand generic concepts such as trigger, effect, damage, cooldown, and targeting. Individual weapons should primarily compose those systems rather than duplicate bespoke logic.

## Prototype Exception

The first vertical slice keeps several values in one script so iteration is fast. Once the loop feels good, the stable concepts are extracted into reusable systems and data files.
