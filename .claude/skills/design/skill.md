---
name: design
description: Collaborative design session for new systems or mechanics. Produces a spec doc at docs/specs/ that /implement executes against.
disable-model-invocation: true
argument-hint: <system or mechanic to design>
---

# Design: $ARGUMENTS

## Mode

Design is collaborative — you bring codebase knowledge, the user owns design intent and final calls. The deliverable is a spec that a future `/implement` session executes against, not code.

Two altitudes exist and blur together:
- **High-level** — mechanic shape, feel, identity. Stay in docs, skip code.
- **Technical** — naming primitives, fields, dispatch paths, Resource shapes. Full code reads required.

The user's prompt signals which altitude opens the session. Shift as discussion requires.

In both modes: drive decisions with rationale instead of bouncing options back. Signal honest confidence on judgment calls. Close load-bearing decisions in-session — open questions in the spec become silent license for the implementer to guess.

## Step 1: Map the surface area

Read any existing spec for the topic. Derive which systems are touched, what infrastructure is depended on, what future systems must stay compatible. This map guides reading and becomes the spec skeleton.

## Step 2: Read at the right depth

**High-level mode:** Stay in docs. Read CLAUDE.md, `docs/architecture.md`, adjacent specs. Skip code.

**Technical mode:** Read the code that the commission touches — every file the new system must compose with. Read `docs/traps.md` for cross-system interactions. The understanding of how systems intersect must exist in YOUR context.

Report what you read and what you observed — never say "I have the full picture."

## Step 3: Evaluate the commission

For every new primitive the design introduces:

- **Abstraction level:** Does it belong on a specific effect, or on a container (AbilityDefinition, StatusEffectDefinition) where anything can use it? Match existing generality.
- **Data-driven:** New content should be new data, not new code branches. If the design implies `if entity_id == "specific_thing"` branches, reshape it.
- **Scale:** Can N entities do this simultaneously? No O(N²) hot paths, no per-frame allocations, squared distances for proximity.
- **Recursion guards:** Any primitive that could fire recursively needs a depth guard or recursion cap.
- **Interaction audit:** Trace same-entity interactions, cross-entity interactions, edge cases (no enemies, entity dies mid-execution, entity stunned/disabled).

## Step 4: Present architecture for review

Before the deliverable, present the full commission for the user to evaluate:
1. Surface area — what systems are touched
2. Commissioned primitives — new Resources, fields, dispatch paths
3. Composition surface — which existing systems it plugs into
4. Interaction risks — what could break

Refine based on feedback. When blessed, write the deliverable.

## Step 5: Write the spec

**Location:** `docs/specs/<descriptive_name>.md`

```markdown
# <Feature Name>

## Overview
[1-3 sentences: what this commissions and why.]

## Commissioned Primitives
[New Resource classes, fields, dispatch paths, signals. For each: where it
lives in the codebase and what its shape is.]

## Composition Surface
[Which existing systems the new primitives plug into and how.
Reference by file/function where integration points matter.]

## Implementation Approach
[How to build this at a shape level. Ordered where order matters.
Reference existing files as composition points.]

## Interaction Checklist
[Specific interactions to verify during testing.
Format: "When X happens while Y is active, verify Z."]
```

The spec is read by a fresh context. It must be self-contained — the implementer executes against it without needing the design conversation.

## Rules

- Read full files, never grep snippets — interactions live in surrounding context
- Do not write GDScript or modify `.gd` files — the implementer writes code
- When a mechanic requires plumbing that doesn't exist, that IS the point — spec the plumbing generic and Resource-driven, matching existing patterns
