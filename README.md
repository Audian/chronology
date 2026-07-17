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
iex> Chronology.range(:this_week, "Etc/UTC", ~U[2026-07-17 15:30:00.000000Z])
{:ok, %{start: ~U[2026-07-13 00:00:00.000000Z], finish: ~U[2026-07-17 23:59:59.999999Z]}}

# A specific quarter or ISO week:
iex> Chronology.quarter(2026, 3)
{:ok, %{start: ~U[2026-07-01 00:00:00.000000Z], finish: ~U[2026-09-30 23:59:59.999999Z]}}

iex> Chronology.week(2026, 30)
{:ok, %{start: ~U[2026-07-20 00:00:00.000000Z], finish: ~U[2026-07-26 23:59:59.999999Z]}}
```

## Time Periods

| time period    | Period description           |
|----------------|-------------------------------|
| :today         | Today                        |
| :yesterday     | Yesterday                    |
| :this_week     | Week-to-date (Mon–today)      |
| :this_month    | Month-to-date (1st–today)     |
| :this_quarter  | Quarter-to-date (ends today) |
| :this_year     | Year-to-date (ends today)    |
| :last_week     | The last week (Mon-Sun)      |
| :last_month    | The last full month          |
| :last_quarter  | The last quarter             |
| :last_year     | The last full year           |
| :previous_year | The year before last         |
| :past_week     | Past 7 days                  |
| :past_month    | Past month (date to date)    |
| :past_year     | Past year (date to date)     |

`quarter(year, quarter)` and `week(year, week)` return the **full** period.
`week/3` uses ISO-8601 numbering (weeks start Monday; week 1 contains Jan 4).
