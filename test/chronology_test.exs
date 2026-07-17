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
      # the DST-gap handling in to_datetime/3 resolves the non-existent midnight
      # to the first valid instant after the gap: 01:00 local (-02:00).
      assert Time.compare(DateTime.to_time(start), ~T[01:00:00]) == :eq
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

    test "unknown timezone with a supplied reference" do
      assert {:error, :time_zone_not_found} = Chronology.range(:today, "Not/AZone", @ref)
    end
  end

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
end
