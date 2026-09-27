# Typing Roguelite Devlog

Keep this log short. Record decisions, experiments, what worked, what failed, and what should be tested next. It is not meant to be a diary.

## Entry format

### YYYY-MM-DD — Short title
**Changed**
- What was implemented.

**Why**
- What problem or design goal motivated it.

**Result**
- What the playtest showed.

**Next**
- The next concrete test or implementation step.

---

### 2026-09-27 — Prototype run loop becomes real

**Changed**
- Built a two-line Monkeytype-style typing area.
- Added XP collection particles and a minimalist XP bar.
- Added typed upgrade selection.
- Added wave-gated upgrade breaks with typed READY confirmation.
- Reworked waves around fixed threat budgets instead of fixed enemy counts.
- Expanded the prototype to 10 waves.
- Added offscreen enemy entry.
- Added sticky automatic targeting.
- Added the first priority enemy prototype, Jammer.
- Added TAB-based priority typing that pauses the normal word stream and resumes exactly where it stopped.

**Why**
- The prototype needed to stop feeling like a loose combat sandbox and start testing the actual identity of the game: flow-state typing, buildcraft, escalating hordes, and direct priority commands.

**Result**
- Progressive build construction feels better than beginning with a completed build.
- Constant level-up interruptions felt wrong, so upgrades now resolve only between waves.
- Per-word recentering and continuous scrolling both caused eye jumping; the two-line layout is the current solution under test.
- A fixed enemy count was too rigid; threat budgets better support mixed hordes and future late-game chaos.

**Next**
- Playtest sticky targeting and the Jammer interaction.
- Add two more priority enemy behaviors.
- Add an elite.
- Add boss encounter architecture.
- Tune wave 8–10 density/readability and overall 10-minute pacing.
- Add sound before doing major visual polish.


### 2026-09-27 — Priority threats become real mechanics

**Changed**
- Added Bulwark and Caller priority enemies alongside Jammer.
- Jammer reduces normal weapon damage while visible.
- Bulwark protects non-priority enemies with a visible damage-reduction shield.
- Caller periodically summons fast, zero-XP Swarmers while it remains alive.
- Priority words now choose their own target from typed prefixes after TAB.
- Summoned enemies do not alter the authored wave threat/XP budget.

**Why**
- Priority enemies needed to create battlefield decisions rather than only being special-colored enemies with words.
- The player should be able to identify and remove the threat through typing without fighting a target selector.

**Result**
- Three priority mechanics now pressure different parts of the run: player firepower, enemy durability, and screen density.
- The threat-budget director remains intact because Caller summons are already paid for by Caller's higher threat cost.

**Next**
- Playtest Waves 4-10 for priority frequency and readability.
- Add an elite archetype.
- Build boss encounter architecture.
- Tune the late-wave density curve and overall 10-minute run pacing.


### 2026-09-27 — Elite pressure prototype

**Changed**
- Added budgeted elite promotion beginning on Wave 7.
- Waves 7-8 receive one elite; Waves 9-10 can receive two.
- Elite promotion consumes extra threat budget instead of being free difficulty.
- The first elite trait is Regenerator: after 1.35 seconds without taking damage, it heals roughly 5.5% max HP per second.
- Direct damage, reaction damage, and damage-over-time ticks suppress regeneration.
- Elites have a thin gold ring and a compact HP bar so regeneration is visible.

**Why**
- Elites should alter how the player handles a target, not just be enemies with inflated HP.
- Regeneration specifically rewards the sticky-targeting system: sustained focus kills the elite efficiently, while switching away gives it room to recover.

**Next**
- Playtest Waves 4-10 with priority enemies + elites together.
- Decide whether Regenerator feels threatening or annoying.
- Build the boss encounter architecture after this combined threat test.


### 2026-09-27 — Separate testability from real balance

**Changed**
- Added debug-build-only prototype controls.
- F1 fully heals and can revive a failed test run.
- F2 toggles god mode.
- F3 clears the remaining authored wave and awards the XP still available from unresolved planned enemies.
- F4 restarts the run.
- Added a small debug hint that is only visible in debug builds.

**Why**
- Midgame is intentionally becoming dangerous, but that should not block testing Waves 7-10, priority enemies, elites, and later bosses.
- Development conveniences should not force us to weaken the actual fresh-profile balance.

**Next**
- Use the controls only when needed to reach untested systems.
- Play one normal run first, then use F1/F2/F3 if needed to inspect late-wave behavior.
- After this combined threat test, build the boss encounter architecture.


### 2026-09-27 — Priority pacing + first boss architecture

**Changed**
- Priority enemies are now distributed across the full wave instead of relying on a pure shuffle.
- Only one priority enemy can be active at a time; normal enemies are pulled forward while the next priority threat waits.
- Added an always-visible-in-debug-build controls panel showing F1-F4 test shortcuts.
- Added the Wave 10 Overseer boss prototype.
- Overseer enters after the Wave 10 horde, stops outside the player's danger ring, and periodically emits damaging pulses.
- At 66% and 33% HP, Overseer locks normal damage and exposes a priority command. TAB + typing the command breaches the phase and resumes normal fire.
- Boss phase gates clamp at their thresholds so high late-game damage cannot skip the typing interaction.

**Why**
- Priority enemies should create short attention spikes throughout a wave, not dump several mandatory commands on the player at once.
- The boss needs to test the game's core identity: normal typing damage interrupted by deliberate direct-command moments.

**Next**
- Playtest the full 10-wave run using debug controls when necessary.
- Evaluate whether one-active-priority is too forgiving in Waves 9-10.
- Tune Overseer pulse timing, HP, and command cadence.
- Then move into full 10-minute pacing and late-chaos/performance tuning.


### 2026-09-27 — Late-wave density and chaos pass

**Changed**
- Spawn cadence now accelerates across the 10-wave run without changing wave completion rules.
- Waves 7-8 can spawn small irregular two-enemy clumps; Waves 9-10 can spawn two- or three-enemy clumps.
- Spawn timing gains slight randomness and each wave naturally compresses toward a denser back half.
- Added per-wave active-enemy safety caps that rise from 12 early to 140 on Wave 10.
- Boss spawning now waits for the authored Wave 10 horde, Caller leftovers, and travelling XP to clear before entering.
- Added transient feedback caps for particles, damage numbers, and reaction waves; XP-carrying particles are never discarded.
- Debug HUD now shows live enemy, bullet, and particle counts to help spot performance problems during the chaos test.

**Why**
- Late-game payoff should become visibly denser and less metronomic without making enemy count depend on player damage.
- We need enough chaos to expose performance/readability problems before committing to final art or permanent progression.

**Next**
- Full 10-wave playtest.
- Record approximate run duration and peak active-enemy/particle counts from the debug panel.
- Tune Wave 8-10 density, boss pressure, and final run duration from actual playtest data.


### 2026-09-27 — Fix late-wave priority tails and excessive knockback

**Changed**
- Priority enemies are now capped by wave: none early, one in early priority waves, two in Waves 7-8, and up to three in Waves 9-10.
- Late-wave rosters always keep Basic plus the two newest normal archetypes before adding priority archetypes.
- Priority placement now stays within the middle portion of the wave, preserving normal enemies after the final priority threat.
- When a priority enemy is already active, the director only pulls nearby normal enemies forward instead of draining the entire remaining normal tail.
- Global knockback was reduced.
- Elites resist most knockback and bosses are nearly knockback-immune.
- Knockback velocity now decays faster.

**Why**
- Waves 8-10 were turning into a slow priority-only cleanup after the normal horde was exhausted.
- Heavy knockback could push combo targets and the boss offscreen, undermining sticky targeting and readability.

**Next**
- Re-test Waves 8-10 and verify that normal enemies remain present around priority encounters.
- Verify that normal targets stay onscreen during sustained combos and Overseer remains anchored in the arena.
- Continue balance/performance tuning from the full-run test.


### 2026-09-27 — Reference-informed pressure pass

**Changed**
- Removed the universal per-wave movement-speed increase from normal enemies.
- Removed wave-based speed scaling from Caller-spawned Swarmers; their speed now comes from their archetype multiplier.
- Later-wave difficulty remains driven by spawn density, horde composition, HP pressure, elites, priority mechanics, and the boss.
- Priority enemy mechanics no longer activate merely because the enemy exists offscreen.
- A priority enemy must enter roughly 34 px inside the visible arena, pause for a ~0.55 second cast, then activate its mechanic.
- Jammer, Bulwark, and Caller now show a cast/activation combat cue and a visual state change.
- Caller cannot begin summoning until its activation cast completes.

**Why**
- Reference footage reinforced that late-run intensity is carried more by body count, build escalation, and enemy composition than by globally accelerating every basic enemy.
- Priority effects need a visible cause before their consequence appears so the player can read the battlefield at typing speed.

**Result to test**
- Basic enemies should feel more consistent across the run while Runners/Swarmers retain explicit speed identities.
- Priority enemies should create a readable arrival beat: enter -> pause/cast -> effect active -> continue advancing.
- Late waves should feel like a dense horde containing priority threats, not a set of invisible debuffs or uniformly faster enemies.

**Next**
- Full Wave 1-10 test focused on late density and priority readability.
- If the horde still feels too evenly distributed, add temporary directional spawn-pressure bias.
- After pacing is stable, expand run upgrades toward more behavior-changing synergies rather than mostly numeric increases.
