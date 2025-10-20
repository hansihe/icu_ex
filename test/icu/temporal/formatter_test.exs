defmodule Icu.Temporal.FormatterTest do
  use ExUnit.Case, async: true

  alias Icu.Temporal.Formatter

  describe "normalize_options/1" do
    test "accepts keyword input with supported values" do
      assert {:ok,
              %{
                length: :long,
                date_fields: :ymd,
                time_precision: :minute,
                zone_style: :generic_short,
                alignment: :column,
                year_style: :with_era
              }} =
               Formatter.normalize_options(
                 length: :long,
                 date_fields: :ymd,
                 time_precision: :minute,
                 zone_style: :generic_short,
                 alignment: :column,
                 year_style: :with_era
               )
    end

    test "normalizes locale structs and removes nil values" do
      locale = Icu.LanguageTag.parse!("en")
      resource = locale.resource

      assert {:ok, %{locale: ^resource}} =
               Formatter.normalize_options(%{locale: locale, alignment: nil})
    end

    test "rejects invalid option keys" do
      assert {:error, {:bad_option, :unsupported}} =
               Formatter.normalize_options(%{unsupported: true})
    end

    test "rejects invalid option values" do
      assert {:error, {:invalid_option_value, :zone_style}} =
               Formatter.normalize_options(%{zone_style: :foo})
    end

    test "supports subsecond precision tuple values" do
      assert {:ok, %{time_precision: {:subsecond, 4}}} =
               Formatter.normalize_options(%{time_precision: {:subsecond, 4}})
    end

    test "rejects invalid length values" do
      assert {:error, {:invalid_option_value, :length}} =
               Formatter.normalize_options(%{length: :gigantic})
    end

    test "rejects invalid time precision tuples" do
      assert {:error, {:invalid_option_value, :time_precision}} =
               Formatter.normalize_options(%{time_precision: {:subsecond, 12}})
    end
  end

  describe "normalize_input/1" do
    test "encodes Date structs with calendar information" do
      assert {:ok,
              %{
                year: 2024,
                month: 5,
                day: 20,
                calendar: :gregorian
              }} = Formatter.normalize_input(~D[2024-05-20])
    end

    test "encodes Time structs and fills microsecond tuple" do
      assert {:ok,
              %{
                hour: 8,
                minute: 15,
                second: 30,
                microsecond: {123_000, 3},
                calendar: Calendar.ISO
              }} = Formatter.normalize_input(~T[08:15:30.123])
    end

    test "encodes NaiveDateTime structs into full maps" do
      naive = ~N[2024-02-29 17:30:45.456]

      assert {:ok,
              %{
                year: 2024,
                month: 2,
                day: 29,
                hour: 17,
                minute: 30,
                second: 45,
                microsecond: {456_000, 3},
                calendar: Calendar.ISO,
                calendar_identifier: :gregorian
              }} = Formatter.normalize_input(naive)
    end

    test "encodes DateTime structs including zone data" do
      datetime = %DateTime{
        year: 2024,
        month: 2,
        day: 29,
        hour: 17,
        minute: 30,
        second: 0,
        microsecond: {123_000, 3},
        calendar: Calendar.ISO,
        time_zone: "Etc/UTC",
        zone_abbr: "UTC",
        utc_offset: 0,
        std_offset: 0
      }

      assert {:ok,
              %{
                time_zone: "Etc/UTC",
                utc_offset: 0,
                microsecond: {123_000, 3},
                calendar: Calendar.ISO,
                calendar_identifier: :gregorian
              }} = Formatter.normalize_input(datetime)
    end

    test "rejects plain map inputs with nanosecond fields" do
      assert {:error, :invalid_temporal} =
               Formatter.normalize_input(%{
                 hour: 10,
                 minute: 5,
                 second: 0,
                 nanosecond: 250_000_000,
                 time_zone: "UTC"
               })
    end

    test "rejects plain map inputs missing microsecond data" do
      assert {:error, :invalid_temporal} =
               Formatter.normalize_input(%{hour: 6, minute: 45, second: 12})
    end

    test "rejects plain map inputs with calendar identifiers" do
      assert {:error, :invalid_temporal} =
               Formatter.normalize_input(%{
                 year: 2023,
                 month: 11,
                 day: 9,
                 hour: 9,
                 minute: 30,
                 second: 0,
                 calendar: Calendar.ISO
               })
    end

    test "rejects invalid time data" do
      assert {:error, :invalid_temporal} =
               Formatter.normalize_input(%{hour: 25, minute: 0, second: 0})
    end

    test "rejects invalid time zone data" do
      assert {:error, :invalid_temporal} =
               Formatter.normalize_input(%{
                 year: 2024,
                 month: 5,
                 day: 1,
                 time_zone: :invalid
               })
    end

    test "rejects out-of-range nanosecond values" do
      assert {:error, :invalid_temporal} =
               Formatter.normalize_input(%{
                 hour: 1,
                 minute: 0,
                 second: 0,
                 nanosecond: 1_000_000_000
               })
    end
  end
end
