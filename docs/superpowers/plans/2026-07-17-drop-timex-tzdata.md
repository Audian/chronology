# Drop Timex/tzdata → tz + native DateTime — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `timex`/`tzdata` from the `chronology` library, reimplement all date-range logic on native Elixir `DateTime`/`Date` backed by the pure-Elixir `tz` timezone database, and add `quarter/3` and `week/3`.

**Architecture:** A single `Chronology` module. `range/3` samples "now" once (via `DateTime.now/2` with `Tz.TimeZoneDatabase`, or a caller-supplied reference converted with `DateTime.shift_zone/3`) and derives `start`/`finish` through private boundary helpers. Boundary helpers build wall-clock instants with `DateTime.new/4` and resolve DST gaps/ambiguities. `quarter/3` and `week/3` map a year + number to a full-period range using the same helpers; `week/3` uses ISO-8601 numbering.

**Tech Stack:** Elixir 1.19, `tz ~> 0.28` (pure Elixir, no runtime deps), ExUnit.

## Global Constraints

- Elixir floor: bump mix.exs to `elixir: "~> 1.17"`. The code relies on `DateTime.shift/3`, introduced in Elixir 1.17.0, so the published compatibility contract must require 1.17+ (the original `~> 1.14` would let consumers on 1.14–1.16 resolve the lib and then crash with `UndefinedFunctionError`). The repo runs 1.19.5 and CI uses 1.18.4, both of which satisfy `~> 1.17`.
- Timezone database is passed **explicitly** as `@tzdb Tz.TimeZoneDatabase` to every `DateTime` call. Never call `Calendar.put_time_zone_database/1`.
- Public return shape is exactly `{:ok, %{start: DateTime.t(), finish: DateTime.t()}}` or `{:error, term()}`. Map keys are `:start` and `:finish`.
- Start-of-period time is `~T[00:00:00.000000]`; end-of-period time is `~T[23:59:59.999999]`.
- Week numbering is ISO-8601: weeks start Monday; week 1 contains Jan 4; a year has 52 or 53 weeks.
- Default timezone is `"Etc/UTC"` (canonical UTC — matches `~U[...]` sigils and native `DateTime.utc_now/0`; passing the non-canonical `"UTC"` yields `time_zone: "UTC"` which won't struct-match `~U` sigils).
- Error atoms: `:invalid_period`, `:invalid_quarter`, `:invalid_week`; timezone failures propagate `:time_zone_not_found` from stdlib.

---

### Task 1: Dependency swap + native `range/3` rewrite

Removes Timex, adds tz, and reimplements `range/3` (with an optional reference instant and the corrected `:this_*` semantics). Replaces the dead test scaffolding with a real `range/3` suite. This task is atomic because `chronology.ex` cannot compile once `timex` is gone until the native implementation lands.

**Files:**
- Modify: `mix.exs` (deps)
- Modify: `lib/chronology.ex` (full rewrite of the module body)
- Test: `test/chronology_test.exs` (replace entirely)

**Interfaces:**
- Produces:
  - `Chronology.range(period :: atom(), timezone :: String.t() \\ "Etc/UTC", reference :: DateTime.t() | nil \\ nil) :: {:ok, %{start: DateTime.t(), finish: DateTime.t()}} | {:error, term()}`
  - Private helpers used by Tasks 2–3: `to_datetime(date, time, timezone) :: {:ok, DateTime.t()} | {:error, term()}` and `to_datetime!(date, time, timezone) :: DateTime.t()` (both apply DST resolution).

- [ ] **Step 1: Swap the dependency in `mix.exs`**

Replace the `deps/0 ` list. Change only the first entry (timex → tz); leave dev/test tools as-is:

```elixir
  defp deps do
    [
      # timezone database (pure Elixir, no runtime deps)
      {:tz, "~> 0.28"},

      # code quality and documentation
      {:ex_doc,     "~> 0.38",  only: [:dev], runtime: false},
      {:credo,      "~> 1.7",   only: [:dev], runtime: false},
      {:dialyxir,   "~> 1.4",   only: [:dev], runtime: false},
      {:sobelow,    "~> 0.13",  only: [:dev]},
      {:mix_audit,  "~> 2.1",   only: [:dev], runtime: false}
    ]
  end
```

- [ ] **Step 2: Fetch deps**

Run: `mix deps.get`
Expected: resolves and fetches `tz`; `timex`, `tzdata`, `hackney`, `combine`, `gettext` and their transitive deps disappear from the dependency set. `mix.lock` updates.

- [ ] **Step 3: Write the failing `range/3` test suite**

Replace the entire contents of `test/chronology_test.exs`:

```elixir
defmodule ChronologyTest do
  use ExUnit.Case, async: true

  # Friday, 2026-07-17 15:30 UTC — fixed reference for deterministic ranges.
  @ref ~U[2026-07-17 15:30:00.000000Z]

  describe "range/3 in UTC" do
    test ":today" do
      assert {:ok, %{start: ~U[2026-07-17 00:00:00.000000Z], finish: ~U[2026-07-17 23:59:59.999999Z]}} =
               Chronology.range(:today, "Etc/UTC", @ref)
    end

    test ":yesterday" do
      assert {:ok, %{start: ~U[2026-07-16 00:00:00.000000Z], finish: ~U[2026-07-16 23:59:59.999999Z]}} =
               Chronology.range(:yesterday, "Etc/UTC", @ref)
    end

    test ":this_week (Mon start .. end of today)" do
      assert {:ok, %{start: ~U[2026-07-13 00:00:00.000000Z], finish: ~U[2026-07-17 23:59:59.999999Z]}} =
               Chronology.range(:this_week, "Etc/UTC", @ref)
    end

    test ":last_week (full previous Mon..Sun)" do
      assert {:ok, %{start: ~U[2026-07-06 00:00:00.000000Z], finish: ~U[2026-07-12 23:59:59.999999Z]}} =
               Chronology.range(:last_week, "Etc/UTC", @ref)
    end

    test ":past_week (raw -7d .. now)" do
      assert {:ok, %{start: ~U[2026-07-10 15:30:00.000000Z], finish: ~U[2026-07-17 15:30:00.000000Z]}} =
               Chronology.range(:past_week, "Etc/UTC", @ref)
    end

    test ":past_month (raw -1mo .. now)" do
      assert {:ok, %{start: ~U[2026-06-17 15:30:00.000000Z], finish: ~U[2026-07-17 15:30:00.000000Z]}} =
               Chronology.range(:past_month, "Etc/UTC", @ref)
    end

    test ":past_year (raw -1yr .. now)" do
      assert {:ok, %{start: ~U[2025-07-17 15:30:00.000000Z], finish: ~U[2026-07-17 15:30:00.000000Z]}} =
               Chronology.range(:past_year, "Etc/UTC", @ref)
    end

    test ":this_month (1st .. end of today)" do
      assert {:ok, %{start: ~U[2026-07-01 00:00:00.000000Z], finish: ~U[2026-07-17 23:59:59.999999Z]}} =
               Chronology.range(:this_month, "Etc/UTC", @ref)
    end

    test ":last_month (full previous month)" do
      assert {:ok, %{start: ~U[2026-06-01 00:00:00.000000Z], finish: ~U[2026-06-30 23:59:59.999999Z]}} =
               Chronology.range(:last_month, "Etc/UTC", @ref)
    end

    test ":this_quarter (Q start .. end of today) — corrected semantics" do
      assert {:ok, %{start: ~U[2026-07-01 00:00:00.000000Z], finish: ~U[2026-07-17 23:59:59.999999Z]}} =
               Chronology.range(:this_quarter, "Etc/UTC", @ref)
    end

    test ":last_quarter (full previous quarter)" do
      assert {:ok, %{start: ~U[2026-04-01 00:00:00.000000Z], finish: ~U[2026-06-30 23:59:59.999999Z]}} =
               Chronology.range(:last_quarter, "Etc/UTC", @ref)
    end

    test ":this_year (Jan 1 .. end of today) — corrected semantics" do
      assert {:ok, %{start: ~U[2026-01-01 00:00:00.000000Z], finish: ~U[2026-07-17 23:59:59.999999Z]}} =
               Chronology.range(:this_year, "Etc/UTC", @ref)
    end

    test ":last_year (full previous year)" do
      assert {:ok, %{start: ~U[2025-01-01 00:00:00.000000Z], finish: ~U[2025-12-31 23:59:59.999999Z]}} =
               Chronology.range(:last_year, "Etc/UTC", @ref)
    end

    test ":previous_year (year before last)" do
      assert {:ok, %{start: ~U[2024-01-01 00:00:00.000000Z], finish: ~U[2024-12-31 23:59:59.999999Z]}} =
               Chronology.range(:previous_year, "Etc/UTC", @ref)
    end
  end

  describe "range/3 in a positive-offset zone" do
    test ":today in Asia/Calcutta uses the zone's wall clock and +05:30 offset" do
      {:ok, %{start: start, finish: finish}} = Chronology.range(:today, "Asia/Calcutta", @ref)

      assert start.time_zone == "Asia/Calcutta"
      assert start.utc_offset == 19_800
      assert DateTime.to_date(start) == ~D[2026-07-17]
      assert DateTime.to_time(start) == ~T[00:00:00.000000]
      assert DateTime.to_time(finish) == ~T[23:59:59.999999]
    end
  end

  describe "range/3 across a DST transition" do
    test ":today spans a spring-forward day with differing start/finish offsets" do
      # America/Los_Angeles springs forward 2026-03-08 02:00 PST -> 03:00 PDT.
      ref = ~U[2026-03-08 20:00:00.000000Z]
      {:ok, %{start: start, finish: finish}} = Chronology.range(:today, "America/Los_Angeles", ref)

      assert DateTime.to_date(start) == ~D[2026-03-08]
      assert start.utc_offset + start.std_offset == -8 * 3600
      assert finish.utc_offset + finish.std_offset == -7 * 3600
    end

    test "beginning-of-day gap is resolved to the first valid instant" do
      # Historical midnight gap: America/Sao_Paulo sprang forward
      # 2017-10-15 00:00 -> 01:00, so midnight that day did not exist.
      ref = ~U[2017-10-15 12:00:00.000000Z]
      {:ok, %{start: start}} = Chronology.range(:today, "America/Sao_Paulo", ref)

      assert start.time_zone == "America/Sao_Paulo"
      # resolve/1 advanced past the non-existent midnight
      assert Time.compare(DateTime.to_time(start), ~T[00:00:00.000000]) == :gt
    end
  end

  describe "range/3 without a reference uses the current time" do
    test "returns an ok range whose start precedes finish" do
      assert {:ok, %{start: start, finish: finish}} = Chronology.range(:today)
      assert DateTime.compare(start, finish) == :lt
    end
  end

  describe "range/3 errors" do
    test "unknown timezone" do
      assert {:error, :time_zone_not_found} = Chronology.range(:today, "Not/AZone")
    end

    test "unknown period" do
      assert {:error, :invalid_period} = Chronology.range(:nonsense, "Etc/UTC", @ref)
    end
  end
end
```

- [ ] **Step 4: Run the suite to confirm it fails**

Run: `mix test test/chronology_test.exs`
Expected: compilation error / failures — `chronology.ex` still references `Timex`, which is no longer available. This confirms the tests exercise new behavior before the rewrite.

- [ ] **Step 5: Rewrite `lib/chronology.ex`**

Replace everything from `defmodule Chronology do` to the final `end` (keep the license header comment block at the top of the file) with:

```elixir
defmodule Chronology do
  @moduledoc """
  Generate date ranges for humanized references such as `:last_week`,
  `:past_year`, or a specific `quarter/3` or ISO-8601 `week/3`.

  All calculations use native Elixir `DateTime`/`Date` backed by the pure-Elixir
  `tz` timezone database (`Tz.TimeZoneDatabase`), passed explicitly — callers do
  not need to configure `Calendar.put_time_zone_database/1`.

  ## DST resolution

  When a wall-clock boundary (e.g. midnight) falls in a DST gap the first valid
  instant after the gap is used; when it is ambiguous the earlier instant is used.
  """

  require Logger

  # -- module attributes -- #
  @default_tz "Etc/UTC"
  @tzdb Tz.TimeZoneDatabase
  @start_time ~T[00:00:00.000000]
  @end_time ~T[23:59:59.999999]

  # -- public functions -- #

  @doc """
  Return a `%{start:, finish:}` date range for `period` in `timezone`
  (default `"UTC"`).

  Pass an optional `reference` `DateTime` to compute the range relative to a
  fixed instant instead of "now"; it is converted into `timezone`.

  ## Periods

  | period          | start                     | finish            |
  |-----------------|---------------------------|-------------------|
  | `:today`        | start of today            | end of today      |
  | `:yesterday`    | start of yesterday        | end of yesterday  |
  | `:this_week`    | Monday of this week       | end of today      |
  | `:last_week`    | Monday of last week       | Sunday of last wk |
  | `:past_week`    | 7 days ago (now)          | now               |
  | `:past_month`   | 1 month ago (now)         | now               |
  | `:past_year`    | 1 year ago (now)          | now               |
  | `:this_month`   | 1st of this month         | end of today      |
  | `:last_month`   | 1st of last month         | last day last mo  |
  | `:this_quarter` | 1st day of this quarter   | end of today      |
  | `:last_quarter` | 1st day of last quarter   | last day last qtr |
  | `:this_year`    | Jan 1 of this year        | end of today      |
  | `:last_year`    | Jan 1 of last year        | Dec 31 last year  |
  | `:previous_year`| Jan 1 two years ago       | Dec 31 two yrs ago|
  """
  @spec range(atom(), String.t(), DateTime.t() | nil) :: {:ok, map()} | {:error, term()}
  def range(period, timezone \\ @default_tz, reference \\ nil) do
    with {:ok, now} <- reference_now(reference, timezone) do
      build_range(period, now)
    end
  end

  @doc """
  Return the full range for `quarter` (1..4) of `year` in `timezone`.

  Returns `{:error, :invalid_quarter}` when `quarter` is outside `1..4`.
  """
  @spec quarter(pos_integer(), 1..4, String.t()) :: {:ok, map()} | {:error, term()}
  def quarter(year, quarter, timezone \\ @default_tz)

  def quarter(year, quarter, timezone) when quarter in 1..4 do
    first_month = (quarter - 1) * 3 + 1
    last_month = quarter * 3
    last_day = Date.end_of_month(Date.new!(year, last_month, 1))

    with {:ok, start} <- to_datetime(Date.new!(year, first_month, 1), @start_time, timezone),
         {:ok, finish} <- to_datetime(last_day, @end_time, timezone) do
      {:ok, %{start: start, finish: finish}}
    end
  end

  def quarter(_year, _quarter, _timezone), do: {:error, :invalid_quarter}

  @doc """
  Return the full range for ISO-8601 `week` of `year` in `timezone`.

  Weeks start Monday; week 1 is the week containing Jan 4. A year has 52 or 53
  weeks. Returns `{:error, :invalid_week}` when `week` is outside that range.
  """
  @spec week(pos_integer(), pos_integer(), String.t()) :: {:ok, map()} | {:error, term()}
  def week(year, week, timezone \\ @default_tz) do
    week1_monday = Date.beginning_of_week(Date.new!(year, 1, 4))
    last_week_monday = Date.beginning_of_week(Date.new!(year, 12, 28))
    weeks_in_year = div(Date.diff(last_week_monday, week1_monday), 7) + 1

    if week in 1..weeks_in_year do
      monday = Date.add(week1_monday, (week - 1) * 7)
      sunday = Date.add(monday, 6)

      with {:ok, start} <- to_datetime(monday, @start_time, timezone),
           {:ok, finish} <- to_datetime(sunday, @end_time, timezone) do
        {:ok, %{start: start, finish: finish}}
      end
    else
      {:error, :invalid_week}
    end
  end

  # -- private functions -- #

  defp reference_now(nil, timezone), do: DateTime.now(timezone, @tzdb)
  defp reference_now(%DateTime{} = reference, timezone),
    do: DateTime.shift_zone(reference, timezone, @tzdb)

  defp build_range(period, now) do
    case period do
      :today ->
        {:ok, %{start: beginning_of_day(now), finish: end_of_day(now)}}

      :yesterday ->
        day = shift(now, day: -1)
        {:ok, %{start: beginning_of_day(day), finish: end_of_day(day)}}

      :this_week ->
        {:ok, %{start: beginning_of_week(now), finish: end_of_day(now)}}

      :last_week ->
        week = shift(now, day: -7)
        {:ok, %{start: beginning_of_week(week), finish: end_of_week(week)}}

      :past_week ->
        {:ok, %{start: shift(now, day: -7), finish: now}}

      :past_month ->
        {:ok, %{start: shift(now, month: -1), finish: now}}

      :past_year ->
        {:ok, %{start: shift(now, year: -1), finish: now}}

      :this_month ->
        {:ok, %{start: beginning_of_month(now), finish: end_of_day(now)}}

      :last_month ->
        month = shift(now, month: -1)
        {:ok, %{start: beginning_of_month(month), finish: end_of_month(month)}}

      :this_quarter ->
        {:ok, %{start: beginning_of_quarter(now), finish: end_of_day(now)}}

      :last_quarter ->
        quarter = shift(now, month: -3)
        {:ok, %{start: beginning_of_quarter(quarter), finish: end_of_quarter(quarter)}}

      :this_year ->
        {:ok, %{start: beginning_of_year(now), finish: end_of_day(now)}}

      :last_year ->
        year = shift(now, year: -1)
        {:ok, %{start: beginning_of_year(year), finish: end_of_year(year)}}

      :previous_year ->
        year = shift(now, year: -2)
        {:ok, %{start: beginning_of_year(year), finish: end_of_year(year)}}

      _ ->
        Logger.error("Unsupported period provided")
        {:error, :invalid_period}
    end
  end

  defp shift(datetime, duration), do: DateTime.shift(datetime, duration, @tzdb)

  defp beginning_of_day(dt), do: to_datetime!(DateTime.to_date(dt), @start_time, dt.time_zone)
  defp end_of_day(dt), do: to_datetime!(DateTime.to_date(dt), @end_time, dt.time_zone)

  defp beginning_of_week(dt),
    do: to_datetime!(Date.beginning_of_week(DateTime.to_date(dt)), @start_time, dt.time_zone)

  defp end_of_week(dt),
    do: to_datetime!(Date.end_of_week(DateTime.to_date(dt)), @end_time, dt.time_zone)

  defp beginning_of_month(dt),
    do: to_datetime!(Date.beginning_of_month(DateTime.to_date(dt)), @start_time, dt.time_zone)

  defp end_of_month(dt),
    do: to_datetime!(Date.end_of_month(DateTime.to_date(dt)), @end_time, dt.time_zone)

  defp beginning_of_quarter(dt) do
    date = DateTime.to_date(dt)
    first_month = (Date.quarter_of_year(date) - 1) * 3 + 1
    to_datetime!(Date.new!(date.year, first_month, 1), @start_time, dt.time_zone)
  end

  defp end_of_quarter(dt) do
    date = DateTime.to_date(dt)
    last_month = Date.quarter_of_year(date) * 3
    last_day = Date.end_of_month(Date.new!(date.year, last_month, 1))
    to_datetime!(last_day, @end_time, dt.time_zone)
  end

  defp beginning_of_year(dt),
    do: to_datetime!(Date.new!(DateTime.to_date(dt).year, 1, 1), @start_time, dt.time_zone)

  defp end_of_year(dt),
    do: to_datetime!(Date.new!(DateTime.to_date(dt).year, 12, 31), @end_time, dt.time_zone)

  # Build a zoned DateTime, resolving DST gaps/ambiguities.
  defp to_datetime(%Date{} = date, %Time{} = time, timezone) do
    case DateTime.new(date, time, timezone, @tzdb) do
      {:ok, dt} -> {:ok, dt}
      {:gap, _before, dt_after} -> {:ok, dt_after}
      {:ambiguous, dt_first, _second} -> {:ok, dt_first}
      {:error, reason} -> {:error, reason}
    end
  end

  # Same as to_datetime/3 but for a timezone already known valid (raises otherwise).
  defp to_datetime!(date, time, timezone) do
    {:ok, dt} = to_datetime(date, time, timezone)
    dt
  end
end
```

- [ ] **Step 6: Run the suite to confirm it passes**

Run: `mix test test/chronology_test.exs`
Expected: all `range/3` tests PASS. (Tests for `quarter/3`/`week/3` are added in Tasks 2–3.)

- [ ] **Step 7: Compile cleanly**

Run: `mix compile --warnings-as-errors`
Expected: compiles with no warnings (no leftover `Timex` references, no unused vars).

- [ ] **Step 8: Commit**

```bash
git add mix.exs mix.lock lib/chronology.ex test/chronology_test.exs
git commit -m "Replace Timex/tzdata with tz + native DateTime in range/3"
```

---

### Task 2: `quarter/3`

The `quarter/3` function is already written in Task 1's module body. This task adds its test coverage and validates behavior independently.

**Files:**
- Test: `test/chronology_test.exs` (append a `describe "quarter/3"` block)

**Interfaces:**
- Consumes: `Chronology.quarter(year, quarter, timezone \\ "Etc/UTC")` from Task 1.

- [ ] **Step 1: Write the failing tests**

Append this block inside `test/chronology_test.exs` (before the final `end`):

```elixir
  describe "quarter/3" do
    test "each quarter of 2026 in UTC" do
      assert {:ok, %{start: ~U[2026-01-01 00:00:00.000000Z], finish: ~U[2026-03-31 23:59:59.999999Z]}} =
               Chronology.quarter(2026, 1)

      assert {:ok, %{start: ~U[2026-04-01 00:00:00.000000Z], finish: ~U[2026-06-30 23:59:59.999999Z]}} =
               Chronology.quarter(2026, 2)

      assert {:ok, %{start: ~U[2026-07-01 00:00:00.000000Z], finish: ~U[2026-09-30 23:59:59.999999Z]}} =
               Chronology.quarter(2026, 3)

      assert {:ok, %{start: ~U[2026-10-01 00:00:00.000000Z], finish: ~U[2026-12-31 23:59:59.999999Z]}} =
               Chronology.quarter(2026, 4)
    end

    test "honors the timezone" do
      {:ok, %{start: start, finish: finish}} = Chronology.quarter(2026, 2, "Asia/Calcutta")
      assert start.time_zone == "Asia/Calcutta"
      assert start.utc_offset == 19_800
      assert DateTime.to_date(start) == ~D[2026-04-01]
      assert DateTime.to_time(start) == ~T[00:00:00.000000]
      assert DateTime.to_date(finish) == ~D[2026-06-30]
      assert DateTime.to_time(finish) == ~T[23:59:59.999999]
    end

    test "rejects quarters outside 1..4" do
      assert {:error, :invalid_quarter} = Chronology.quarter(2026, 0)
      assert {:error, :invalid_quarter} = Chronology.quarter(2026, 5)
    end

    test "unknown timezone propagates an error" do
      assert {:error, :time_zone_not_found} = Chronology.quarter(2026, 1, "Not/AZone")
    end
  end
```

- [ ] **Step 2: Run the tests**

Run: `mix test test/chronology_test.exs`
Expected: all `quarter/3` tests PASS (the implementation shipped in Task 1).

- [ ] **Step 3: Commit**

```bash
git add test/chronology_test.exs
git commit -m "Add quarter/3 tests"
```

---

### Task 3: `week/3` (ISO-8601)

`week/3` is already written in Task 1's module body. This task adds its test coverage, including ISO edge cases.

**Files:**
- Test: `test/chronology_test.exs` (append a `describe "week/3"` block)

**Interfaces:**
- Consumes: `Chronology.week(year, week, timezone \\ "Etc/UTC")` from Task 1.

- [ ] **Step 1: Write the failing tests**

Append this block inside `test/chronology_test.exs` (before the final `end`):

```elixir
  describe "week/3 (ISO-8601)" do
    test "week 1 of 2026 spills into December 2025" do
      assert {:ok, %{start: ~U[2025-12-29 00:00:00.000000Z], finish: ~U[2026-01-04 23:59:59.999999Z]}} =
               Chronology.week(2026, 1)
    end

    test "a mid-year week" do
      assert {:ok, %{start: ~U[2026-07-20 00:00:00.000000Z], finish: ~U[2026-07-26 23:59:59.999999Z]}} =
               Chronology.week(2026, 30)
    end

    test "accepts week 53 in a 53-week year (2020)" do
      assert {:ok, %{start: ~U[2020-12-28 00:00:00.000000Z], finish: ~U[2021-01-03 23:59:59.999999Z]}} =
               Chronology.week(2020, 53)
    end

    test "rejects week 54 in a 53-week year" do
      assert {:error, :invalid_week} = Chronology.week(2020, 54)
    end

    test "rejects week 53 in a 52-week year (2025)" do
      assert {:error, :invalid_week} = Chronology.week(2025, 53)
    end

    test "rejects week 0" do
      assert {:error, :invalid_week} = Chronology.week(2026, 0)
    end

    test "honors the timezone" do
      {:ok, %{start: start, finish: finish}} = Chronology.week(2026, 30, "Asia/Calcutta")
      assert start.time_zone == "Asia/Calcutta"
      assert start.utc_offset == 19_800
      assert DateTime.to_date(start) == ~D[2026-07-20]
      assert DateTime.to_time(start) == ~T[00:00:00.000000]
      assert DateTime.to_date(finish) == ~D[2026-07-26]
      assert DateTime.to_time(finish) == ~T[23:59:59.999999]
    end

    test "unknown timezone propagates an error" do
      assert {:error, :time_zone_not_found} = Chronology.week(2026, 1, "Not/AZone")
    end
  end
```

- [ ] **Step 2: Run the tests**

Run: `mix test test/chronology_test.exs`
Expected: all `week/3` tests PASS.

- [ ] **Step 3: Commit**

```bash
git add test/chronology_test.exs
git commit -m "Add week/3 (ISO-8601) tests"
```

---

### Task 4: Documentation + full verification

Update `README.md` to drop the Timex framing and document the new API, then run the full quality gate.

**Files:**
- Modify: `README.md`

**Interfaces:** none (docs only).

- [ ] **Step 1: Rewrite the README intro and usage**

Replace the top of `README.md` (from the title through the Usage examples) with:

````markdown
# Chronology

Date-range helpers for humanized references such as `last week` or `past year`,
plus explicit `quarter/3` and ISO-8601 `week/3` ranges.

Implemented on native Elixir `DateTime`/`Date` and the pure-Elixir
[`tz`](https://hex.pm/packages/tz) timezone database — no Timex, no tzdata. The
`tz` data is bundled, so consumers do not need to configure a timezone database.

## Installation

```elixir
def deps do
  [
    {:chronology, github: "audian/chronology"}
  ]
end
```

## Usage

```elixir
iex> Chronology.range(:today)
{:ok, %{start: ~U[2026-07-17 00:00:00.000000Z], finish: ~U[2026-07-17 23:59:59.999999Z]}}

iex> Chronology.range(:last_quarter, "Asia/Calcutta")
{:ok, %{start: #DateTime<...+05:30 Asia/Calcutta>, finish: #DateTime<...+05:30 Asia/Calcutta>}}

# Range relative to a fixed instant:
iex> Chronology.range(:this_week, "UTC", ~U[2026-07-17 15:30:00.000000Z])
{:ok, %{start: ~U[2026-07-13 00:00:00.000000Z], finish: ~U[2026-07-17 23:59:59.999999Z]}}

# A specific quarter or ISO week:
iex> Chronology.quarter(2026, 3)
{:ok, %{start: ~U[2026-07-01 00:00:00.000000Z], finish: ~U[2026-09-30 23:59:59.999999Z]}}

iex> Chronology.week(2026, 30)
{:ok, %{start: ~U[2026-07-20 00:00:00.000000Z], finish: ~U[2026-07-26 23:59:59.999999Z]}}
```
````

- [ ] **Step 2: Update the period table**

Ensure the `## Time Periods` table in `README.md` lists all 14 periods and reflects the corrected semantics: `:this_quarter` and `:this_year` finish at **end of today** (not end of period). Add rows if the existing table is truncated:

```markdown
| :this_quarter  | Quarter-to-date (ends today) |
| :this_year     | Year-to-date (ends today)    |
| :previous_year | The year before last         |
```

Add a note below the table:

```markdown
`quarter(year, quarter)` and `week(year, week)` return the **full** period.
`week/3` uses ISO-8601 numbering (weeks start Monday; week 1 contains Jan 4).
```

- [ ] **Step 3: Full test run**

Run: `mix test`
Expected: all tests PASS, 0 failures.

- [ ] **Step 4: Quality gate**

Run: `mix compile --warnings-as-errors && mix credo --strict && mix dialyzer && mix deps.audit`
Expected: compile clean; credo clean; dialyzer reports no issues (first run builds the PLT and is slow); `deps.audit` reports no vulnerabilities. If `mix dialyzer`/`mix deps.audit` aliases are unavailable, run the underlying tasks (`mix dialyxir`, `mix_audit`) — but the deps are already declared, so the mix tasks should exist.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "Update README for tz + native DateTime, quarter/3 and week/3"
```

---

## Self-Review Notes

- **Spec coverage:** dependency swap (T1), tz wiring via `@tzdb` (T1), `range/3` + reference + single `now` sampling + corrected `:this_*` (T1), DST `resolve` policy (T1 impl + tests), error tuples (T1–T3), `quarter/3` (T1 impl, T2 tests), `week/3` ISO (T1 impl, T3 tests), test-suite replacement (T1–T3), README/moduledoc (T1 moduledoc, T4 README). All spec sections mapped.
- **Type consistency:** `to_datetime/3` (tuple) and `to_datetime!/3` (bare) names are used consistently across `range`, `quarter`, and `week`. `@tzdb`, `@start_time`, `@end_time` referenced uniformly. Map keys `:start`/`:finish` everywhere.
- **No placeholders:** every step contains full code or an exact command with expected output. Test expected values were computed against Elixir 1.19.5.
