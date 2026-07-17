#
# Copyright 2021, Audian, Inc.
#
# Licensed under the MIT License
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#

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
