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
  A simple module to generate date ranges
  """

  require Logger

  # -- module attributes -- #
  @default_tz "UTC"

  # -- public functions -- #

  @doc """
  Return a date range for the supplied period. Time periods can be requested
  as the period in atoms and an optional time zone. The default timezone is
  UTC.

  ### Time Periods

  | time period    | Period description       |
  |----------------|--------------------------|
  | :today         | Today                    |
  | :yesterday     | Yesterday                |
  | :this_week     | The current week         |
  | :this_month    | The current month        |
  | :this_year     | The current year         |
  | :this_quarter  | The current quarter      |
  | :last_week     | The last week (Mon-Sun)  |
  | :last_month    | The last full month      |
  | :last_year     | The last full year       |
  | :last_quarter  | The last quarter         |
  | :past_week     | Past 7 days              |
  | :past_month    | Past month (date to date)|
  | :past_year     | Past 365 days            |
  | :previous_year | 2 years ago              |

  ```elixir
  iex> Chronology.range(:today)
  {:ok,
   %{
     finish: #DateTime<2022-11-01 23:59:59.999999-07:00 PDT America/Los_Angeles>,
     start: #DateTime<2022-11-01 00:00:00.000000-07:00 PDT America/Los_Angeles>
   }}

  iex> Chronology.range(:yesterday, "America/Los_Angeles")
  {:ok,
   %{
     finish: #DateTime<2022-10-31 23:59:59.999999-07:00 PDT America/Los_Angeles>,
     start: #DateTime<2022-10-31 00:00:00.000000-07:00 PDT America/Los_Angeles>
   }}

  iex> Chronology.range(:last_quarter, "Asia/Calcutta")
  {:ok,
   %{
     finish: #DateTime<2022-09-30 23:59:59.999999+05:30 IST Asia/Calcutta>,
     start: #DateTime<2022-07-01 00:00:00.000000+05:30 IST Asia/Calcutta>
   }}
  ```
  """
  @spec range(period :: atom(), timezone :: String.t()) :: {:ok, map()} | {:error, term()}
  def range(period, timezone \\ @default_tz) do
    case period do
      :today ->
        start =
          Timex.now(timezone)
          |> Timex.beginning_of_day()

        finish =
          Timex.now(timezone)
          |> Timex.end_of_day()

        {:ok, %{start: start, finish: finish}}

      :yesterday ->
        start =
          Timex.now(timezone)
          |> Timex.shift(days: -1)
          |> Timex.beginning_of_day()

        finish =
          Timex.now(timezone)
          |> Timex.shift(days: -1)
          |> Timex.end_of_day()

        {:ok, %{start: start, finish: finish}}

      :this_week ->
        start =
          Timex.now(timezone)
          |> Timex.beginning_of_week()

        finish =
          Timex.now(timezone)
          |> Timex.end_of_day()

        {:ok, %{start: start, finish: finish}}

      :last_week ->
        start =
          Timex.now(timezone)
          |> Timex.shift(days: -7)
          |> Timex.beginning_of_week()

        finish =
          Timex.now(timezone)
          |> Timex.shift(days: -7)
          |> Timex.end_of_week()

        {:ok, %{start: start, finish: finish}}

      :past_week ->
        start =
          Timex.now(timezone)
          |> Timex.shift(days: -7)

        finish = Timex.now(timezone)

        {:ok, %{start: start, finish: finish}}

      :past_month ->
        start =
          Timex.now(timezone)
          |> Timex.shift(months: -1)

        finish = Timex.now(timezone)

        {:ok, %{start: start, finish: finish}}

      :past_year ->
        start =
          Timex.now(timezone)
          |> Timex.shift(years: -1)

        finish = Timex.now(timezone)

        {:ok, %{start: start, finish: finish}}

      :this_month ->
        start =
          Timex.now(timezone)
          |> Timex.beginning_of_month()

        finish =
          Timex.now(timezone)
          |> Timex.end_of_day()

        {:ok, %{start: start, finish: finish}}

      :last_month ->
        start =
          Timex.now(timezone)
          |> Timex.shift(months: -1)
          |> Timex.beginning_of_month()

        finish =
          Timex.now(timezone)
          |> Timex.shift(months: -1)
          |> Timex.end_of_month()

        {:ok, %{start: start, finish: finish}}

      :this_quarter ->
        start =
          Timex.now(timezone)
          |> Timex.beginning_of_quarter()

        finish =
          Timex.now(timezone)
          |> Timex.end_of_quarter()

        {:ok, %{start: start, finish: finish}}

      :last_quarter ->
        start =
          Timex.now(timezone)
          |> Timex.shift(months: -3)
          |> Timex.beginning_of_quarter()

        finish =
          Timex.now(timezone)
          |> Timex.shift(months: -3)
          |> Timex.end_of_quarter()

        {:ok, %{start: start, finish: finish}}

      :this_year ->
        start =
          Timex.now(timezone)
          |> Timex.beginning_of_year()

        finish =
          Timex.now(timezone)
          |> Timex.end_of_year()

        {:ok, %{start: start, finish: finish}}

      :last_year ->
        start =
          Timex.now(timezone)
          |> Timex.shift(years: -1)
          |> Timex.beginning_of_year()

        finish =
          Timex.now(timezone)
          |> Timex.shift(years: -1)
          |> Timex.end_of_year()

        {:ok, %{start: start, finish: finish}}

      :previous_year ->
        start =
          Timex.now(timezone)
          |> Timex.shift(years: -2)
          |> Timex.beginning_of_year()

        finish =
          Timex.now(timezone)
          |> Timex.shift(years: -2)
          |> Timex.end_of_year()

        {:ok, %{start: start, finish: finish}}

      _ ->
        Logger.error("Unsupported period provided")
        {:error, :invalid_period}
    end
  end
end
