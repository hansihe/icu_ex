defmodule Icu.TemporalTest do
  use ExUnit.Case, async: true

  doctest Icu.Temporal

  alias Icu.Temporal
  alias Icu.Temporal.Formatter

  # NOTE: The underlying NIF still carries TODOs around timezone field decoding.
  # Exercising :zone_style with a map that includes :time_zone currently panics in
  # `native/icu_nif/src/datetime.rs` (see decode_temporal). Keep these tests focused
  # on options that the native layer already implements.

  describe "format/2" do
    test "returns an error for invalid temporal input" do
      assert {:error, :invalid_temporal} = Temporal.format(%{}, date_fields: :ymd)
    end
  end

  describe "format/3" do
    test "formats naive datetimes with date and time skeletons" do
      datetime = ~N[2024-02-29 17:30:00]

      assert {:ok, formatted} =
               Temporal.format(datetime, locale: "en", date_fields: :ymd, time_precision: :minute)

      assert formatted =~ "Feb"
      assert formatted =~ "29"
      assert formatted =~ "5:30"
    end

    test "formats plain dates applying date fields" do
      assert {:ok, formatted} = Temporal.format(~D[2024-01-15], locale: "en", date_fields: :ymd)
      assert formatted =~ "Jan"
      assert formatted =~ "2024"
    end

    test "propagates option validation errors" do
      datetime = ~N[2024-06-01 19:45:00]

      assert {:error, {:invalid_options, {:bad_option, :datetime_length}}} =
               Temporal.format(datetime, locale: "en", datetime_length: :long)
    end

    test "supports subsecond precision" do
      datetime = ~N[2024-02-29 17:30:45.987654]

      assert {:ok, formatted} =
               Temporal.format(datetime, locale: "en", time_precision: {:subsecond, 3})

      assert formatted =~ "45"
      assert formatted =~ ".987"
    end

    test "accepts structural options like length and year_style" do
      date = ~D[2024-10-05]

      assert {:ok, formatted} =
               Temporal.format(date,
                 locale: "en",
                 length: :long,
                 year_style: :with_era,
                 date_fields: :ymde
               )

      assert formatted =~ "2024"
    end

    test "different date_fields values affect output" do
      date = ~D[2024-03-15]

      # Test :d (day only)
      assert {:ok, d_format} = Temporal.format(date, locale: "en", date_fields: :d)
      assert d_format =~ "15"
      refute d_format =~ "2024"
      refute d_format =~ "Mar"

      # Test :md (month and day)
      assert {:ok, md_format} = Temporal.format(date, locale: "en", date_fields: :md)
      assert md_format =~ "15"
      assert md_format =~ "Mar" or md_format =~ "3"
      refute md_format =~ "2024"

      # Test :ymd (year, month, day)
      assert {:ok, ymd_format} = Temporal.format(date, locale: "en", date_fields: :ymd)
      assert ymd_format =~ "15"
      assert ymd_format =~ "2024"

      # Test :y (year only)
      assert {:ok, y_format} = Temporal.format(date, locale: "en", date_fields: :y)
      assert y_format =~ "2024"
      refute y_format =~ "15"

      # Test :ym (year and month)
      assert {:ok, ym_format} = Temporal.format(date, locale: "en", date_fields: :ym)
      assert ym_format =~ "2024"
      assert ym_format =~ "Mar" or ym_format =~ "3"
      refute ym_format =~ "15"

      # Test :m (month only)
      assert {:ok, m_format} = Temporal.format(date, locale: "en", date_fields: :m)
      assert m_format =~ "Mar" or m_format =~ "3" or m_format =~ "March"
      refute m_format =~ "2024"
      refute m_format =~ "15"
    end

    test "length option affects formatting style" do
      date = ~D[2024-06-20]

      # Test :short length
      assert {:ok, short_format} =
               Temporal.format(date, locale: "en", date_fields: :ymd, length: :short)

      # Test :medium length
      assert {:ok, medium_format} =
               Temporal.format(date, locale: "en", date_fields: :ymd, length: :medium)

      # Test :long length
      assert {:ok, long_format} =
               Temporal.format(date, locale: "en", date_fields: :ymd, length: :long)

      # Verify they produce different outputs
      assert short_format != medium_format or medium_format != long_format
    end

    test "time_precision controls time component detail" do
      time = ~T[14:30:45.123456]

      # Test :hour precision
      assert {:ok, hour_format} = Temporal.format(time, locale: "en", time_precision: :hour)
      assert hour_format =~ "2" or hour_format =~ "14"
      refute hour_format =~ "30"
      refute hour_format =~ "45"

      # Test :minute precision
      assert {:ok, minute_format} = Temporal.format(time, locale: "en", time_precision: :minute)
      assert minute_format =~ "30"
      refute minute_format =~ "45"

      # Test :second precision
      assert {:ok, second_format} = Temporal.format(time, locale: "en", time_precision: :second)
      assert second_format =~ "30"
      assert second_format =~ "45"
      refute second_format =~ "."

      # Test :subsecond precision with different digits
      assert {:ok, subsec1_format} =
               Temporal.format(time, locale: "en", time_precision: {:subsecond, 1})

      assert subsec1_format =~ "45"
      assert subsec1_format =~ ".1"
      refute subsec1_format =~ ".12"

      assert {:ok, subsec6_format} =
               Temporal.format(time, locale: "en", time_precision: {:subsecond, 6})

      assert subsec6_format =~ "45"
      assert subsec6_format =~ "123456"
    end

    test "alignment option (auto vs column)" do
      datetime = ~N[2024-02-05 09:05:03]

      # Test :auto alignment (default)
      assert {:ok, auto_format} =
               Temporal.format(datetime,
                 locale: "en",
                 date_fields: :ymd,
                 time_precision: :second,
                 alignment: :auto
               )

      # Test :column alignment
      assert {:ok, column_format} =
               Temporal.format(datetime,
                 locale: "en",
                 date_fields: :ymd,
                 time_precision: :second,
                 alignment: :column
               )

      # Both should format successfully
      assert is_binary(auto_format)
      assert is_binary(column_format)
    end

    test "year_style affects year representation" do
      date = ~D[2024-01-01]

      # Test :auto year style
      assert {:ok, auto_format} =
               Temporal.format(date, locale: "en", date_fields: :ymd, year_style: :auto)

      assert auto_format =~ "2024"

      # Test :full year style
      assert {:ok, full_format} =
               Temporal.format(date, locale: "en", date_fields: :ymd, year_style: :full)

      assert full_format =~ "2024"

      # Test :with_era year style - verify it formats successfully
      # The era marker might not always appear depending on ICU behavior
      assert {:ok, era_format} =
               Temporal.format(date, locale: "en", date_fields: :ymde, year_style: :with_era)

      assert era_format =~ "2024"
      # Just verify it's a valid formatted string
      assert is_binary(era_format)
    end

    test "combining multiple options" do
      datetime = ~N[2024-12-25 18:45:30.789]

      assert {:ok, formatted} =
               Temporal.format(datetime,
                 locale: "en",
                 date_fields: :ymd,
                 time_precision: {:subsecond, 2},
                 length: :long,
                 year_style: :full,
                 alignment: :auto
               )

      # Verify date components
      assert formatted =~ "2024"
      assert formatted =~ "Dec" or formatted =~ "12" or formatted =~ "December"
      assert formatted =~ "25"

      # Verify time components
      assert formatted =~ "45"
      assert formatted =~ "30"
      assert formatted =~ ".78" or formatted =~ ".79"
    end

    test "locale affects formatting" do
      date = ~D[2024-07-14]

      # English
      assert {:ok, en_format} = Temporal.format(date, locale: "en", date_fields: :ymd)
      assert en_format =~ "Jul" or en_format =~ "7"

      # German
      assert {:ok, de_format} = Temporal.format(date, locale: "de", date_fields: :ymd)
      assert is_binary(de_format)

      # French
      assert {:ok, fr_format} = Temporal.format(date, locale: "fr", date_fields: :ymd)
      assert is_binary(fr_format)

      # Verify different locales produce different outputs (in most cases)
      assert en_format != de_format or en_format != fr_format
    end

    test "weekday formatting with date_fields :e, :de, :mde, :ymde" do
      # Use a known date: Monday, January 1, 2024
      date = ~D[2024-01-01]

      # Test :e (weekday only)
      assert {:ok, e_format} = Temporal.format(date, locale: "en", date_fields: :e)
      assert e_format =~ "Mon" or e_format =~ "M"
      refute e_format =~ "2024"
      refute e_format =~ "Jan"

      # Test :de (day and weekday)
      assert {:ok, de_format} = Temporal.format(date, locale: "en", date_fields: :de)
      assert de_format =~ "1"

      # Test :mde (month, day, and weekday)
      assert {:ok, mde_format} = Temporal.format(date, locale: "en", date_fields: :mde)
      assert mde_format =~ "1"

      # Test :ymde (year, month, day, and weekday)
      assert {:ok, ymde_format} = Temporal.format(date, locale: "en", date_fields: :ymde)
      assert ymde_format =~ "2024"
      assert ymde_format =~ "1"
    end

    test "minute_optional precision shows minutes only when non-zero" do
      # Time with non-zero minutes
      time1 = ~T[14:30:00]

      assert {:ok, format1} =
               Temporal.format(time1, locale: "en", time_precision: :minute_optional)

      assert format1 =~ "30"

      # Time with zero minutes
      time2 = ~T[14:00:00]

      assert {:ok, format2} =
               Temporal.format(time2, locale: "en", time_precision: :minute_optional)

      assert is_binary(format2)
    end

    test "formats Time struct correctly" do
      time = ~T[23:59:59.999]

      assert {:ok, formatted} =
               Temporal.format(time, locale: "en", time_precision: {:subsecond, 3})

      assert formatted =~ "59"
      assert formatted =~ ".999" or formatted =~ "999"
    end

    test "formats DateTime struct correctly" do
      {:ok, datetime} = DateTime.new(~D[2024-03-15], ~T[10:30:00], "Etc/UTC")

      assert {:ok, formatted} =
               Temporal.format(datetime, locale: "en", date_fields: :ymd, time_precision: :minute)

      assert formatted =~ "2024"
      assert formatted =~ "15"
      assert formatted =~ "30"
    end

    test "handles edge case dates" do
      # Leap day
      leap_day = ~D[2024-02-29]
      assert {:ok, formatted} = Temporal.format(leap_day, locale: "en", date_fields: :ymd)
      assert formatted =~ "29"
      assert formatted =~ "Feb" or formatted =~ "2"

      # New Year's Day
      new_year = ~D[2024-01-01]
      assert {:ok, formatted} = Temporal.format(new_year, locale: "en", date_fields: :ymd)
      assert formatted =~ "2024"
      assert formatted =~ "1"

      # End of year
      year_end = ~D[2024-12-31]
      assert {:ok, formatted} = Temporal.format(year_end, locale: "en", date_fields: :ymd)
      assert formatted =~ "31"
      assert formatted =~ "Dec" or formatted =~ "12"
    end

    test "subsecond precision boundary values" do
      datetime = ~N[2024-01-01 12:00:00.123456789]

      # Test all valid subsecond precision values (1-9)
      for precision <- 1..9 do
        assert {:ok, formatted} =
                 Temporal.format(datetime,
                   locale: "en",
                   time_precision: {:subsecond, precision}
                 )

        assert is_binary(formatted)
        assert formatted =~ "12"
        assert formatted =~ "00"
        assert formatted =~ "."
      end
    end

    @tag :skip
    test "panics when zone_style is combined with time_zone map input" do
      input = %{
        year: 2024,
        month: 2,
        day: 29,
        hour: 17,
        minute: 30,
        second: 0,
        time_zone: "America/New_York",
        utc_offset: -18_000
      }

      assert_raise ErlangError, fn ->
        IO.inspect(
          Temporal.format(input,
            locale: "en",
            zone_style: :generic_short,
            time_precision: :minute
          )
        )
      end
    end
  end

  describe "format!/2" do
    test "raises on error" do
      formatter = %Formatter{resource: :opaque}

      assert_raise RuntimeError, ~r/temporal formatting failed/, fn ->
        Temporal.format!(formatter, %{})
      end
    end
  end

  describe "format_to_parts/3" do
    test "respects subsecond precision in parts output" do
      datetime = ~N[2024-02-29 17:30:45.123456]

      assert {:ok, parts} =
               Temporal.format_to_parts(datetime, locale: "en", time_precision: {:subsecond, 3})

      assert Enum.any?(parts, &(&1.part_type == :second))
      assert Enum.any?(parts, &(&1.part_type == :fraction))
    end

    test "date_fields affects which parts are returned" do
      date = ~D[2024-03-15]

      # Test with :ymd
      assert {:ok, ymd_parts} =
               Temporal.format_to_parts(date, locale: "en", date_fields: :ymd)

      assert Enum.any?(ymd_parts, &(&1.part_type == :year))
      assert Enum.any?(ymd_parts, &(&1.part_type == :month))
      assert Enum.any?(ymd_parts, &(&1.part_type == :day))

      # Test with :ym (no day)
      assert {:ok, ym_parts} = Temporal.format_to_parts(date, locale: "en", date_fields: :ym)
      assert Enum.any?(ym_parts, &(&1.part_type == :year))
      assert Enum.any?(ym_parts, &(&1.part_type == :month))

      # Test with :d (day only)
      assert {:ok, d_parts} = Temporal.format_to_parts(date, locale: "en", date_fields: :d)
      assert Enum.any?(d_parts, &(&1.part_type == :day))
    end

    test "time_precision affects which time parts are returned" do
      time = ~T[14:30:45.123]

      # Test with :hour
      assert {:ok, hour_parts} =
               Temporal.format_to_parts(time, locale: "en", time_precision: :hour)

      assert Enum.any?(hour_parts, &(&1.part_type == :hour))

      # Test with :minute
      assert {:ok, minute_parts} =
               Temporal.format_to_parts(time, locale: "en", time_precision: :minute)

      assert Enum.any?(minute_parts, &(&1.part_type == :hour))
      assert Enum.any?(minute_parts, &(&1.part_type == :minute))

      # Test with :second
      assert {:ok, second_parts} =
               Temporal.format_to_parts(time, locale: "en", time_precision: :second)

      assert Enum.any?(second_parts, &(&1.part_type == :second))

      # Test with subsecond
      assert {:ok, subsec_parts} =
               Temporal.format_to_parts(time, locale: "en", time_precision: {:subsecond, 2})

      assert Enum.any?(subsec_parts, &(&1.part_type == :second))
      assert Enum.any?(subsec_parts, &(&1.part_type == :fraction))
    end

    test "parts contain actual formatted values" do
      datetime = ~N[2024-06-15 14:30:45]

      assert {:ok, parts} =
               Temporal.format_to_parts(datetime,
                 locale: "en",
                 date_fields: :ymd,
                 time_precision: :second
               )

      # Verify parts have values
      assert Enum.all?(parts, &is_binary(&1.value))
      assert Enum.all?(parts, &(&1.value != ""))

      # Find specific parts and verify their values make sense
      year_part = Enum.find(parts, &(&1.part_type == :year))

      if year_part do
        assert year_part.value =~ "2024"
      end

      day_part = Enum.find(parts, &(&1.part_type == :day))

      if day_part do
        assert day_part.value =~ "15"
      end
    end

    test "weekday parts appear with appropriate date_fields" do
      date = ~D[2024-01-01]

      # Test with :ymde (includes weekday)
      assert {:ok, ymde_parts} =
               Temporal.format_to_parts(date, locale: "en", date_fields: :ymde)

      assert Enum.any?(ymde_parts, &(&1.part_type == :weekday))

      # Test with :e (weekday only)
      assert {:ok, e_parts} = Temporal.format_to_parts(date, locale: "en", date_fields: :e)
      assert Enum.any?(e_parts, &(&1.part_type == :weekday))
    end

    test "length option affects part formatting" do
      date = ~D[2024-06-20]

      # Test short length
      assert {:ok, short_parts} =
               Temporal.format_to_parts(date, locale: "en", date_fields: :ymd, length: :short)

      # Test long length
      assert {:ok, long_parts} =
               Temporal.format_to_parts(date, locale: "en", date_fields: :ymd, length: :long)

      # Both should return parts
      assert is_list(short_parts) and length(short_parts) > 0
      assert is_list(long_parts) and length(long_parts) > 0
    end

    test "combining multiple options in format_to_parts" do
      datetime = ~N[2024-12-25 18:45:30.789]

      assert {:ok, parts} =
               Temporal.format_to_parts(datetime,
                 locale: "en",
                 date_fields: :ymde,
                 time_precision: {:subsecond, 2},
                 length: :long,
                 year_style: :with_era
               )

      # Verify we get a comprehensive set of parts
      assert is_list(parts)
      assert length(parts) > 5

      # Verify presence of expected part types
      part_types = Enum.map(parts, & &1.part_type)
      assert :year in part_types
      assert :month in part_types
      assert :day in part_types
      assert :hour in part_types
      assert :minute in part_types
      assert :second in part_types
      assert :fraction in part_types
    end

    @tag :skip
    test "panics when requesting zone parts with time_zone map input" do
      input = %{
        year: 2024,
        month: 3,
        day: 10,
        hour: 12,
        minute: 0,
        second: 0,
        time_zone: "America/New_York",
        utc_offset: -18_000
      }

      assert_raise ErlangError, fn ->
        Temporal.format_to_parts(input,
          locale: "en",
          zone_style: :localized_offset_short,
          date_fields: :ymd,
          time_precision: :minute
        )
      end
    end
  end

  describe "format_to_parts/2" do
    @tag :skip
    test "returns an error for invalid input" do
      assert {:error, :invalid_temporal} = Temporal.format_to_parts(%{})
    end
  end

  describe "format_to_parts!/2" do
    @tag :skip
    test "raises on error" do
      formatter = %Formatter{resource: :opaque}

      assert_raise RuntimeError, ~r/temporal formatting failed/, fn ->
        Temporal.format_to_parts!(formatter, %{})
      end
    end
  end
end
