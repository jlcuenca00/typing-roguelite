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
