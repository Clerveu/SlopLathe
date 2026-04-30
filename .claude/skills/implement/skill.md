---
name: implement
description: Implementation workflow — content vs infrastructure gate, pattern-aware reading, verification, ship. Invoke at the start of every coding session.
disable-model-invocation: true
argument-hint: [what to implement]
---

# Implement: $ARGUMENTS

## Step 1: Read the spec, then gate content vs infrastructure

If a spec exists at `docs/specs/`, read it in full first. Every mechanic, interaction, and composition hint is load-bearing.

### Content vs infrastructure gate

Does the code already contain the pattern you need to follow?

- **Infrastructure** = creating or modifying a fundamental system (effect dispatch, damage pipeline, entity lifecycle, movement, targeting, modifier system). The change affects how the machine works, not just adds another entry.
- **Content** = adding to a system with an established pattern. New Resource instances, new match arms, new fields using established patterns (bool flags with counters, lifecycle hook arrays, dispatch branches). You can point to an existing factory or component that does the exact same kind of thing with different values.

**Volume of new code is irrelevant.** Adding a field + counter in 6 lifecycle sites + dispatch branch is a lot of lines, every one following a pattern. Volume ≠ infrastructure. Novel architectural decisions = infrastructure.

**Infrastructure path → Step 2A.** Present approach to user before coding.
**Content path → Step 2B.** Proceed directly to implementation.

Re-evaluate continuously. If you classified as infrastructure but then find 10 existing fields with the same handler shape, reclassify as content.

## Step 2A: Infrastructure — full reads

Read every file the new system touches. Read `docs/traps.md` for cross-system interactions. Read `docs/architecture.md` for tick order and data flow. Full context is non-negotiable for infrastructure — you're establishing patterns future content copies.

Report what you read — never claim "I have the full picture."

Proceed to Step 3.

## Step 2B: Content — targeted reads

All infrastructure exists. You're wiring data using established patterns.

**Always read (full):**
- `entities/entity.gd` — animation state machine, hit-frame dispatch, choreography. Non-negotiable full read.
- The factory or file where you'll add code

**Spot-check** the specific primitives you need:
- `systems/effect_dispatcher.gd` — confirm effect types are dispatched
- `entities/components/behavior_component.gd` — confirm targeting types exist
- `entities/components/ability_component.gd` — confirm condition types exist
- `entities/components/status_effect_component.gd` — confirm lifecycle hooks are wired

**Pattern reference:** Read ONE existing factory that uses similar patterns to match its shape.

Proceed to Step 3.

## Step 3: Match existing patterns exactly

Before writing anything new, find the existing pattern and match it. Four things of the same type must use the same method. Consistency in how established patterns are used is as important as the patterns themselves.

- Before a new status effect → read existing ones with similar mechanics
- Before a new ability → read an existing one with similar targeting/effects
- Before a new dispatch branch → check how every existing one is structured
- Before extending a Resource → check how existing fields are consumed

When no existing pattern fits, that's infrastructure — flag it and design the pattern deliberately.

## Step 4: Scale check

Every system must handle high entity counts. Concretely:
- SpatialGrid for proximity queries, not full-array scans
- `distance_squared_to()` over `distance_to()`
- Inline iteration over `.filter()` in hot paths
- Signal listeners early-return when irrelevant

## Step 5: Generalization audit (infrastructure only)

For new fields, methods, or dispatch paths:
- Abstraction level — does it belong on the specific effect or on a container any ability/status can use?
- No type-check branches in generic paths — new content = new data, not new code branches
- Recursion guards on chain-capable primitives
- Future content test — will the next several features of this shape work without modification?

## Step 6: Interaction audit

Trace before writing code:
- Same-entity: what happens when the new feature is active alongside existing abilities/statuses?
- Cross-entity: what happens with receivers' existing modifiers and states?
- Edge cases: no enemies on screen, entity dies mid-execution, entity stunned/disabled

## Step 7: Spec is the contract

If a `/design` spec exists, build what it describes. Every mechanic, every interaction. The spec reflects decisions already made — do not reopen them to shrink scope at implementation time.

## Step 8: Build, then verify

Build the feature, then verify it works:

1. Add debug prints framed around end-state — the final effect produced, not intermediate triggers
2. Launch the scene and test the golden path
3. For infrastructure: test one edge case per category (state removal, phase boundaries, dead-entity fallback)
4. For content: golden path is usually sufficient — the engine's shared systems are already proven
5. Strip debug prints after verification

**Visual correctness (sprite alignment, VFX timing, animation feel) is the user's domain, not yours.** Flag visual concerns, don't claim they're correct.

## Step 9: Ship

1. Strip debug prints from Step 8
2. Update docs only if future-you would lose something by not having the update:
   - `docs/traps.md` — add cross-file interaction traps the code introduced
   - `docs/content_guide.md` — add entries if a new effect/condition type was created
3. Commit and push

## Rules

- Never use `:=` when the expression involves Resource property access — use explicit `var x: float =`
- Read full files, never grep snippets — interactions live in surrounding context
- When a feature requires plumbing that doesn't exist, build it generic and Resource-driven — do not shrink the mechanics to avoid building infrastructure
- `git add -A` when committing; `git push` is the natural conclusion of every commit
