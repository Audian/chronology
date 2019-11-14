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

  @doc "Return a range for the supplied time period"
  @spec range(period :: atom(), timezone :: String.t()) :: map()
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
