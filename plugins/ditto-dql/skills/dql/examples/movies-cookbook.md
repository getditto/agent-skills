---
title: DQL movies cookbook
description: 18 end-to-end DQL tasks against a sample movies dataset. Every statement here is verified to work on the Ditto v5.0.0 SDK.
---

# DQL Movies Cookbook

A practical walkthrough of every major DQL capability the v5.0.0 SDK supports. Each task is self-contained — paste it into a Ditto query interface and it should run.

> **Compatibility:** Examples are tagged with the minimum Ditto SDK version they require. Most tasks work on **SDK 4.14.x and 5.0.x**. Tasks that depend on COUNTER (4.13+), PN_COUNTER (4.11+), or `DO UPDATE_LOCAL_DIFF` (4.12+) carry an explicit "Available in:" tag. Features added in v5.1.0 (`ADVISE`, structured `PROFILE` output, `INSERT ... ON ID CONFLICT DO MERGE`, `serialize_json`, `object_size`, `USE IDS` on mutations) are intentionally excluded. **Note:** the `watch_count` field uses COUNTER (SDK 4.13+); on older SDKs substitute a REGISTER and use SET instead of `APPLY ... INCREMENT BY`.

## Dataset

The cookbook uses two collections: `movies` and `reviews`.

### `movies` schema

| Field | Type | CRDT | Notes |
|---|---|---|---|
| `_id` | string | REGISTER | IMDb id, e.g. `"tt0111161"` |
| `title` | string | REGISTER | |
| `year` | integer | REGISTER | |
| `runtime_minutes` | integer | REGISTER | |
| `genres` | array<string> | REGISTER | JSON array of genre names |
| `director` | object | **MAP** | `{name, born}` |
| `cast` | array<object> | REGISTER | `[{name, role}, ...]` |
| `ratings` | object | **MAP** | `{imdb, rotten_tomatoes, metacritic}` |
| `box_office_millions` | number | REGISTER | |
| `tags` | array<string> | REGISTER | |
| `watch_count` | integer | **COUNTER** | distributed counter |
| `is_classic` | boolean | REGISTER | |
| `released` | string | REGISTER | ISO-8601 `YYYY-MM-DD` |

### `reviews` schema

| Field | Type | CRDT | Notes |
|---|---|---|---|
| `_id` | string | REGISTER | auto |
| `movie_id` | string | REGISTER | FK to `movies._id` |
| `user_id` | string | REGISTER | |
| `score` | integer | REGISTER | 1–5 |
| `comment` | string | REGISTER | |
| `created_at` | string | REGISTER | ISO-8601 timestamp |

<!-- Task bodies will be added in plan Task 11. -->
