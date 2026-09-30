# Object lifetimes and retention — TODO_LANGUAGE

> **Sources for this file.** The API reference for each handle type, and SDK source for
> whether a parent reference is strong or weak — this is rarely documented and is the
> fact the whole file turns on.

<!--
  This file holds the per-handle TABLE and the teardown detail. SKILL.md § Object
  lifetimes and retention holds the instance rule plus the most surprising retention
  fact, and links here. Spec §5.

  Add a `## Contents` list once this file passes 200 lines — CI enforces it (spec §3).
-->

What must be held to stay alive, what happens when it is dropped, and where to cancel.
The rule that changes code by default is in
[`SKILL.md` § Object lifetimes and retention](../SKILL.md#object-lifetimes-and-retention);
this file carries the table.

## The one strong reference

<!--
  Whether the aggregates (store, sync, presence, auth, …) hold a strong or weak
  reference to the instance, and what happens on use-after-release: a catchable error,
  an unrecoverable abort, or undefined behaviour. Name the exact message.
-->

TODO

## What to retain, and the symptom if you don't

| Handle | Retain it | Symptom if you get it wrong |
|---|---|---|
| TODO | TODO | TODO |

## Where to cancel

<!--
  Per UI framework / application lifecycle where the language has more than one. Note
  any handle whose release semantics INVERT the others — those are the ones that get
  written wrong.
-->

TODO
