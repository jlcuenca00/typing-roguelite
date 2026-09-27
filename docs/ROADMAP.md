# Roadmap

## Phase 0 - Setup
- [x] Create GitHub repository.
- [x] Add design documentation.
- [x] Add Godot project scaffold.
- [x] Add first playable typing/combat slice.

## Phase 1 - Feel
- [ ] Tune typing responsiveness.
- [x] Add better current/completed/upcoming word styling.
- [x] Add hit flash / particles.
- [ ] Add satisfying typing and weapon audio.
- [x] Tune enemy approach speed and offscreen spawn pressure.
- [x] Add sticky auto-targeting so normal fire does not randomly switch targets.
- [x] Add screen shake only for high-impact effects.

## Phase 2 - Buildcraft
- [x] Separate weapons, triggers, and effects.
- [x] Add 3 prototype weapons.
- [x] Add 3 prototype effects.
- [x] Add 2 reactions.
- [x] Add 10-15 upgrades.
- [x] Add upgrade selection screen.

## Phase 2.5 - Run Loop
- [x] Add prototype 10-wave structure; upgrades only resolve between waves.
- [x] Require an explicit typed READY between waves; never auto-start the next wave.
- [x] Generate waves from fixed threat budgets; enemy count emerges from enemy costs.
- [x] Add data-driven enemy archetypes and wave roster unlocks.
- [x] Add minimalist physical XP HUD and readable particle travel.
- [x] Add slower level thresholds for run pacing.
- [x] Add death / restart flow.
- [x] Start runs with one weapon instead of a completed build.
- [x] Use a two-line Monkeytype-style typing area with faded completed words and line shifts.
- [x] Type upgrade command words instead of number keys.

## Phase 3 - Threats
- [x] Add first priority enemy prototype (Jammer).
- [x] Add 2 more priority enemies (Bulwark, Caller).
- [x] Add priority typing interruption/resume.
- [x] Give priority enemies distinct battlefield mechanics beyond direct typing.
- [x] Add elite modifier system (Regenerator prototype).
- [ ] Add boss.
- [ ] Add 10-minute run pacing.

## Phase 4 - Permanent Progression
- [ ] Add meta currency earned from runs.
- [ ] Add permanent combat/utility upgrade trees.
- [ ] Keep fresh-profile runs intentionally difficult.
- [ ] Cap raw permanent power so typing skill and run builds still matter.
- [ ] Add permanent unlock paths for weapons, mutations, characters, and Depths.

## Phase 5 - Text Modes
- [ ] Standard Words.
- [ ] Narrative.
- [ ] Context-sensitive narrative events.
- [ ] Archive hooks.

## Phase 6 - Prototype Review
- [x] Add debug-only test controls for healing, god mode, wave clearing, and restart.
- [ ] Profile enemy/projectile performance.
- [ ] Playtest typing feel at different WPM ranges.
- [ ] Evaluate readability under late-run chaos.
- [ ] Decide what systems graduate into full production.
