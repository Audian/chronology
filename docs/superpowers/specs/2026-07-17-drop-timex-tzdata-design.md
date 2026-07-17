# Drop Timex & tzdata — migrate to `tz` + native Elixir `DateTime`

**Date:** 2026-07-17
**Status:** Approved design
**Scope:** `chronology` library (single public function `Chronology.range/2`)

## Goal

Remove the `timex` dependency and the `tzdata` timezone database it pulls in.
Replace the date/time arithmetic with native Elixir `DateTime`/`Date` functions
(available on this repo's Elixir 1.19), and supply timezone data via the
pure-Elixir `tz` package. Along the way, fix the concrete gaps found in the
current implementation.

Also add two explicit-period functions requested alongside the migration:
`quarter/3` (full quarter from a year + quarter number) and `week/3` (full
ISO-8601 week from a year + week number).

Non-goals: no change to the `{:ok, %{start:, finish:}}` return shape, no
unrelated refactoring.

## Motivation

`timex ~> 3.7` drags in a heavy chain:
`timex → tzdata → hackney → {certifi, idna, mimerl, ssl_verify_fun, metrics,
parse_trans, unicode_util_compat}` plus `combine` and `gettext`. The library
uses Timex only for basic "now / shift / beginning-of / end-of" operations that
Elixir's standard library now covers directly. Elixir's stdlib ships only
`Calendar.UTCOnlyTimeZoneDatabase`, so a timezone database is still required for
named zones — `tz` provides one as pure Elixir with **no runtime dependencies**
(its `castore`/`mint` deps are `optional: true`, needed only for HTTP
auto-updates, which we do not enable).

## Dependencies

`mix.exs`:

- Remove `{:timex, "~> 3.7"}`.
- Add `{:tz, "~> 0.28"}`.

Dev/test tooling (`ex_doc`, `credo`, `dialyxir`, `sobelow`, `mix_audit`)
unchanged. `extra_applications` unchanged — `tz` needs no OTP app started when
auto-update is off; its data is compiled in.

## Timezone database wiring

No global mutation of `Calendar` config. The module holds:

```elixir
@tzdb Tz.TimeZoneDatabase
```

and passes it explicitly as the positional database argument to every stdlib
call that needs one. Verified signatures on Elixir 1.19.5:

- `DateTime.now(time_zone, @tzdb)` → `{:ok, dt} | {:error, :time_zone_not_found}`
- `DateTime.shift(dt, duration, @tzdb)` (calendar-aware; clamps e.g.
  `Jan 31 − 1 month → Dec 31`, matching Timex)
- `DateTime.new(date, time, time_zone, @tzdb)` →
  `{:ok, dt} | {:gap, before, after} | {:ambiguous, first, second} | {:error, _}`

This keeps the library self-contained: consumers do **not** need to call
`Calendar.put_time_zone_database/1`.

## Public API

Signature gains an optional reference instant (default arg chain generates
`range/1`, `range/2`, `range/3`):

```elixir
@spec range(atom(), String.t(), DateTime.t() | nil) :: {:ok, map()} | {:error, term()}
def range(period, timezone \\ "Etc/UTC", reference \\ nil)
```

- `reference == nil` → uses `DateTime.now(timezone, @tzdb)` as "now".
- A supplied `reference` is converted into `timezone` (via `DateTime.shift_zone/3`)
  and used as "now". This makes every branch deterministically testable and is
  useful to callers who want ranges relative to a fixed instant.

Return shape is unchanged: `{:ok, %{start: DateTime.t(), finish: DateTime.t()}}`
or `{:error, term()}`.

**`now` is sampled once** per call and both `start` and `finish` are derived
from it. (Current code calls `Timex.now/1` twice per branch, so `start` and
`finish` come from two different instants microseconds apart — fixed here.)

## New functions: `quarter/3` and `week/3`

Both return the same shape as `range/2` — `{:ok, %{start:, finish:}}` — for the
**full** period (no to-date semantics), reusing the same boundary/DST helpers.
Neither takes a `reference`: year + number fully determine the range.

### `quarter(year, quarter, timezone \\ "UTC")`

```elixir
@spec quarter(pos_integer(), 1..4, String.t()) :: {:ok, map()} | {:error, term()}
```

- Validate `quarter in 1..4`, else `{:error, :invalid_quarter}`.
- First month `= (quarter - 1) * 3 + 1`; last month `= quarter * 3`.
- `start` = `beginning_of_day` of day 1 of the first month, in `timezone`.
- `finish` = `end_of_day` of `Date.end_of_month/1` of the last month, in `timezone`.
- Example: `quarter(2026, 3)` → `2026-07-01 00:00:00.000000` ..
  `2026-09-30 23:59:59.999999`.

### `week(year, week, timezone \\ "UTC")` — ISO 8601

Week starts Monday; week 1 is the week containing the first Thursday
(equivalently, containing Jan 4). Years have 52 or 53 ISO weeks.

- **Anchor:** `week1_monday = Date.beginning_of_week(Date.new!(year, 1, 4))`.
- **Weeks in year (validation upper bound):**
  `last_week_monday = Date.beginning_of_week(Date.new!(year, 12, 28))`
  (Dec 28 is always in the last ISO week);
  `weeks_in_year = div(Date.diff(last_week_monday, week1_monday), 7) + 1`.
- Validate `week in 1..weeks_in_year`, else `{:error, :invalid_week}`.
- `target_monday = Date.add(week1_monday, (week - 1) * 7)`.
- `start` = `beginning_of_day(target_monday)`; `finish` =
  `end_of_day(Date.add(target_monday, 6))` (Sunday), both in `timezone`.
- Example (ISO): `week(2026, 1)` → Mon `2025-12-29` .. Sun `2026-01-04`;
  `week(2026, 30)` → Mon `2026-07-20` .. Sun `2026-07-26`.

Note: because the year+number map to a `Date`, then to a wall-clock boundary in
`timezone`, the same `resolve/1` DST policy and `{:error, :time_zone_not_found}`
handling apply.

## Error handling

- Unknown timezone: return `{:error, :time_zone_not_found}` (propagated from
  `DateTime.now/2` / `DateTime.new/4`) instead of the current messy crash when a
  bad zone is piped through Timex.
- Unknown period (`range/2`): unchanged — log an error and return
  `{:error, :invalid_period}`.
- Invalid quarter: `{:error, :invalid_quarter}`. Invalid week:
  `{:error, :invalid_week}`.

## DST boundary resolution

Constructing a wall-clock boundary (e.g. midnight) in a zone via
`DateTime.new/4` can hit a DST transition:

- `{:gap, _before, after}` — the wall-clock time does not exist (spring-forward).
  Resolve to `after` (first valid instant after the gap).
- `{:ambiguous, first, _second}` — the wall-clock time occurs twice
  (fall-back). Resolve to `first` (earlier instant).

A private `resolve/1` helper centralizes this policy and is documented in the
moduledoc.

## Boundary helpers (replace Timex calls)

All operate on the single sampled `now` (a `DateTime` in the target zone),
extract its `Date`, compute a boundary `Date`, then build a zoned `DateTime` at
`~T[00:00:00.000000]` (start) or `~T[23:59:59.999999]` (finish) via
`DateTime.new/4` + `resolve/1`:

- `beginning_of_day` / `end_of_day` — same date, min/max time.
- `beginning_of_week` / `end_of_week` — `Date.beginning_of_week/1` /
  `Date.end_of_week/1` (default Monday start / Sunday end, matching Timex).
- `beginning_of_month` / `end_of_month` — `Date.beginning_of_month/1` /
  `Date.end_of_month/1`.
- `beginning_of_quarter` / `end_of_quarter` — via `Date.quarter_of_year/1`:
  first month `= (q-1)*3 + 1`, last month `= q*3`; build day 1 of first month /
  `Date.end_of_month` of last month.
- `beginning_of_year` / `end_of_year` — Jan 1 / Dec 31 of `now`'s year.
- `shift(dt, duration)` — thin wrapper over `DateTime.shift(dt, duration, @tzdb)`.

## Period → range mapping

`now` = the sampled reference `DateTime` in the target zone.
**Behavior-preserving except the two rows marked CHANGED** (per approved
decision: all `:this_*` periods are "to-date", i.e. finish = end of today).

| period | start | finish |
|---|---|---|
| `:today` | `beginning_of_day(now)` | `end_of_day(now)` |
| `:yesterday` | `beginning_of_day(shift(now, day: -1))` | `end_of_day(shift(now, day: -1))` |
| `:this_week` | `beginning_of_week(now)` | `end_of_day(now)` |
| `:last_week` | `beginning_of_week(shift(now, day: -7))` | `end_of_week(shift(now, day: -7))` |
| `:past_week` | `shift(now, day: -7)` | `now` |
| `:past_month` | `shift(now, month: -1)` | `now` |
| `:past_year` | `shift(now, year: -1)` | `now` |
| `:this_month` | `beginning_of_month(now)` | `end_of_day(now)` |
| `:last_month` | `beginning_of_month(shift(now, month: -1))` | `end_of_month(shift(now, month: -1))` |
| `:this_quarter` | `beginning_of_quarter(now)` | `end_of_day(now)` **CHANGED** (was end_of_quarter) |
| `:last_quarter` | `beginning_of_quarter(shift(now, month: -3))` | `end_of_quarter(shift(now, month: -3))` |
| `:this_year` | `beginning_of_year(now)` | `end_of_day(now)` **CHANGED** (was end_of_year) |
| `:last_year` | `beginning_of_year(shift(now, year: -1))` | `end_of_year(shift(now, year: -1))` |
| `:previous_year` | `beginning_of_year(shift(now, year: -2))` | `end_of_year(shift(now, year: -2))` |
| _other_ | — | `Logger.error` + `{:error, :invalid_period}` |

Note `:past_week/:past_month/:past_year` use raw shifted instants (no boundary
snapping) — preserved as-is.

## Testing

The current suite is dead and must be replaced:

- `test/chronology_test.exs` calls `Chronology.hello/0`, which does not exist —
  `mix test` fails to compile.
- The moduledoc `doctest` uses hardcoded 2022 `#DateTime<…>` literals compared
  against live `now` — it can never pass.

New suite, using the injectable `reference` for determinism:

1. **Per-period boundary assertions** for all 14 periods against a fixed
   `reference`, asserting exact `start`/`finish` values.
2. **Timezone correctness** across UTC and a positive-offset zone
   (`Asia/Calcutta`, +05:30) — verify offsets and that boundaries are computed
   in the target zone, not UTC.
3. **DST transition** — a spring-forward day (e.g. `America/Los_Angeles`
   2026-03-08) asserting correct offsets on `:today`; and, if a suitable
   historical zone/date is available (e.g. `America/Sao_Paulo` midnight
   spring-forward), a targeted `resolve/1` gap test.
4. **Error paths** — unknown timezone → `{:error, :time_zone_not_found}`;
   unknown period → `{:error, :invalid_period}`; `quarter/3` outside 1..4 →
   `{:error, :invalid_quarter}`; `week/3` outside the year's range →
   `{:error, :invalid_week}`.
5. **`quarter/3`** — all four quarters for a year assert exact start/finish;
   validation rejects 0 and 5.
6. **`week/3`** — ISO edge cases: week 1 of 2026 spilling into 2025
   (`2025-12-29` .. `2026-01-04`); a mid-year week; a 53-week year (e.g. 2020,
   which has 53 ISO weeks) accepting week 53 and rejecting week 54; a 52-week
   year rejecting week 53.
7. Replace the illustrative moduledoc examples so they are not executed as
   doctests (or make them deterministic via `reference`), so `mix test` is green.

## Documentation

- Update `README.md`: it currently says "a simple wrapper around Timex" and has
  a truncated period table. Reword to describe the `tz` + native `DateTime`
  implementation, document the optional `reference` argument, and note that `tz`
  is bundled (no host tz-db configuration required). Full period table with the
  corrected `:this_quarter`/`:this_year` semantics, plus `quarter/3` and
  `week/3` (state the ISO-8601 convention explicitly for `week/3`).
- Update the moduledoc similarly.

## Gaps found in the current implementation (summary)

1. **Dead tests** — `Chronology.hello/0` reference breaks compilation; doctests
   can never pass. Zero working coverage today.
2. **`:this_*` inconsistency** — `:this_week`/`:this_month` were to-date but
   `:this_quarter`/`:this_year` returned future-dated (full-period) finishes.
   Resolved to uniform to-date semantics.
3. **Double `now` sampling** — `start`/`finish` derived from two different
   instants per call. Fixed by sampling once.
4. **DST day-boundary handling** — Timex hid gap/ambiguous wall-clock times;
   native code must resolve them explicitly (now documented via `resolve/1`).
5. **Invalid-timezone crash** — piping a bad zone through Timex crashed; now a
   clean `{:error, :time_zone_not_found}`.
6. **Stale docs** — README/moduledoc describe a Timex wrapper and are truncated.
