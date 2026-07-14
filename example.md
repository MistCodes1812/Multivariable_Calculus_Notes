---
title: Week 3 — Recursion
---

# Week 3: Recursion

Some intro prose that sits outside any typed block, just plain page content.

::: {.pre-reading}
Before class, skim chapter 4 of the course text on stack frames.
You don't need to understand tail-call optimization yet — we'll build
that up together.
:::

::: {.course-material}
## Base cases and recursive cases

Every recursive function needs a base case that terminates the recursion
and a recursive case that makes progress toward it. Forgetting the base
case is the single most common cause of a stack overflow in student code.
:::

::: {.slot data-slot-type="video" data-src="https://example.com/embed/recursion-intro" data-title="Recursion, visually"}
:::

::: {.deep-dive}
## Why recursion and induction are the same idea

If you've done proof by induction, recursive functions should feel
familiar: the base case matches your base case, and the recursive step
matches your inductive step. This isn't a coincidence — it's the same
logical structure applied to computation instead of proof.
:::

::: {.slot data-slot-type="interactive" data-src="https://example.com/embed/call-stack-sim" data-title="Call stack simulator"}
:::

More closing prose, again outside any block.
