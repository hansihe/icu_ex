defmodule Icu.Number.CompactTest do
  use ExUnit.Case, async: true

  alias Icu.Number
  alias Icu.Number.Formatter

  # Expected strings are what ICU4X actually produces at the pinned rev; a few
  # are non-obvious (German short does not abbreviate thousands, Russian uses a
  # NO-BREAK SPACE) so they are asserted verbatim rather than guessed from CLDR.

  describe "format_compact/2 (English, short)" do
    test "abbreviates thousands with half-even rounding by default" do
      assert {:ok, %{formatted: "194K", displayed_value: 194_000}} =
               Number.format_compact(194_438, locale: "en")
    end

    test "half-even keeps a fractional digit for single-digit significands" do
      assert {:ok, %{formatted: "6.7K", displayed_value: 6700}} =
               Number.format_compact(6_718, locale: "en")
    end

    test "trunc never rounds up and floors to whole units" do
      assert {:ok, %{formatted: "194K", displayed_value: 194_000}} =
               Number.format_compact(194_438, locale: "en", rounding_mode: :trunc)

      assert {:ok, %{formatted: "6K", displayed_value: 6000}} =
               Number.format_compact(6_718, locale: "en", rounding_mode: :trunc)
    end

    test "small numbers are not abbreviated" do
      for mode <- [:half_even, :trunc] do
        assert {:ok, %{formatted: "780", displayed_value: 780}} =
                 Number.format_compact(780, locale: "en", rounding_mode: mode)
      end
    end

    test "long display spells the magnitude out" do
      assert {:ok, %{formatted: "194 thousand", displayed_value: 194_000}} =
               Number.format_compact(194_438,
                 locale: "en",
                 compact_display: :long,
                 rounding_mode: :trunc
               )
    end

    test "negative values floor towards zero in magnitude" do
      assert {:ok, %{formatted: "-13K", displayed_value: -13_000}} =
               Number.format_compact(-13_132, locale: "en", rounding_mode: :trunc)
    end
  end

  describe "format_compact/2 (Russian)" do
    test "uses тыс.-style suffix with a no-break space" do
      assert {:ok, %{formatted: "194 тыс.", displayed_value: 194_000}} =
               Number.format_compact(194_438, locale: "ru", rounding_mode: :trunc)

      assert {:ok, %{formatted: "12 тыс.", displayed_value: 12_000}} =
               Number.format_compact(12_000, locale: "ru", rounding_mode: :trunc)
    end
  end

  describe "format_compact/2 (Japanese / Chinese, 万-based grouping)" do
    test "thousands below 10,000 are not abbreviated" do
      assert {:ok, %{formatted: formatted, displayed_value: 3000}} =
               Number.format_compact(3_000, locale: "ja", rounding_mode: :trunc)

      refute formatted =~ "万"
    end

    test "trunc floors at the 万 boundary" do
      assert {:ok, %{formatted: "1万", displayed_value: 10_000}} =
               Number.format_compact(15_000, locale: "ja", rounding_mode: :trunc)

      assert {:ok, %{formatted: "1万", displayed_value: 10_000}} =
               Number.format_compact(15_000, locale: "zh", rounding_mode: :trunc)
    end

    test "half-even keeps the significand" do
      assert {:ok, %{formatted: "1.5万", displayed_value: 15_000}} =
               Number.format_compact(15_000, locale: "ja")
    end
  end

  describe "format_compact/2 (German)" do
    test "short notation does not abbreviate thousands (CLDR)" do
      assert {:ok, %{formatted: "194.438", displayed_value: 194_438}} =
               Number.format_compact(194_438, locale: "de", rounding_mode: :trunc)
    end

    test "long notation abbreviates with Tausend" do
      assert {:ok, %{formatted: "194 Tausend", displayed_value: 194_000}} =
               Number.format_compact(194_438,
                 locale: "de",
                 compact_display: :long,
                 rounding_mode: :trunc
               )
    end
  end

  describe "displayed_value invariants" do
    @cases [
      {"en", 194_438},
      {"en", 6_718},
      {"en", 780},
      {"ru", 194_438},
      {"ja", 3_000},
      {"ja", 15_000},
      {"zh", 15_000},
      {"de", 194_438}
    ]

    test "trunc never overstates the input and the string matches the value" do
      for {locale, n} <- @cases do
        assert {:ok, %{formatted: formatted, displayed_value: displayed}} =
                 Number.format_compact(n, locale: locale, rounding_mode: :trunc)

        assert displayed <= n, "#{locale} #{n}: displayed #{displayed} overstates input"

        # The compact string must denote exactly the displayed value: formatting
        # the displayed value itself (which is already compact-round) is a no-op.
        assert {:ok, %{formatted: ^formatted}} =
                 Number.format_compact(displayed, locale: locale, rounding_mode: :trunc)
      end
    end
  end

  describe "notation via format/2" do
    test "notation: :compact returns just the string" do
      assert {:ok, "194K"} = Number.format(194_438, locale: "en", notation: :compact)
    end

    test "format!/2 with compact notation" do
      assert "194K" = Number.format!(194_438, locale: "en", notation: :compact)
    end

    test "format_compact/2 forces compact even if :standard is passed" do
      assert {:ok, %{formatted: "194K"}} =
               Number.format_compact(194_438, locale: "en", notation: :standard)
    end
  end

  describe "compact formatter constraints" do
    test "format_to_parts is rejected for a compact formatter" do
      {:ok, formatter} = Formatter.new(locale: "en", notation: :compact)
      assert {:error, :invalid_options} = Formatter.format_to_parts(formatter, 194_438)
    end

    test "format_compact is rejected for a standard formatter" do
      {:ok, formatter} = Formatter.new(locale: "en")
      assert {:error, :invalid_formatter} = Formatter.format_compact(formatter, 194_438)
    end

    test "rejects invalid option values" do
      assert {:error, _} = Number.format_compact(1000, locale: "en", rounding_mode: :bogus)
      assert {:error, _} = Number.format_compact(1000, locale: "en", compact_display: :bogus)
      assert {:error, _} = Number.format(1000, locale: "en", notation: :bogus)
    end

    test "rejects non-numeric values" do
      assert {:error, :invalid_number} = Number.format_compact(:nope, locale: "en")
    end
  end

  describe "standard notation is unchanged" do
    test "default notation still formats plainly" do
      assert {:ok, "1,234.500"} = Number.format(1234.5, locale: "en")
      assert {:ok, "194,438.000"} = Number.format(194_438, locale: "en")
    end
  end

  describe "bucket boundaries (en)" do
    test "zero and sub-thousand are not abbreviated" do
      assert {:ok, %{formatted: "0", displayed_value: 0}} =
               Number.format_compact(0, locale: "en", rounding_mode: :trunc)

      assert {:ok, %{formatted: "999", displayed_value: 999}} =
               Number.format_compact(999, locale: "en", rounding_mode: :trunc)
    end

    test "thousand and million crossovers with trunc" do
      assert {:ok, %{formatted: "1K", displayed_value: 1_000}} =
               Number.format_compact(1_000, locale: "en", rounding_mode: :trunc)

      assert {:ok, %{formatted: "9K", displayed_value: 9_000}} =
               Number.format_compact(9_999, locale: "en", rounding_mode: :trunc)

      assert {:ok, %{formatted: "10K", displayed_value: 10_000}} =
               Number.format_compact(10_000, locale: "en", rounding_mode: :trunc)

      assert {:ok, %{formatted: "999K", displayed_value: 999_000}} =
               Number.format_compact(999_999, locale: "en", rounding_mode: :trunc)

      assert {:ok, %{formatted: "1M", displayed_value: 1_000_000}} =
               Number.format_compact(1_000_000, locale: "en", rounding_mode: :trunc)
    end

    test "half-even rounds up at boundaries where trunc floors" do
      # 9_999 rounds to 10K but truncates to 9K; 999_999 rounds to 1M.
      assert {:ok, %{formatted: "10K", displayed_value: 10_000}} =
               Number.format_compact(9_999, locale: "en", rounding_mode: :half_even)

      assert {:ok, %{formatted: "1M", displayed_value: 1_000_000}} =
               Number.format_compact(999_999, locale: "en", rounding_mode: :half_even)
    end
  end

  describe "bucket boundaries (ja, 万-based)" do
    test "does not abbreviate below 10,000" do
      assert {:ok, %{formatted: "1,000", displayed_value: 1_000}} =
               Number.format_compact(1_000, locale: "ja", rounding_mode: :trunc)

      assert {:ok, %{formatted: "9,999", displayed_value: 9_999}} =
               Number.format_compact(9_999, locale: "ja", rounding_mode: :trunc)
    end

    test "abbreviates from the 万 boundary" do
      assert {:ok, %{formatted: "1万", displayed_value: 10_000}} =
               Number.format_compact(10_000, locale: "ja", rounding_mode: :trunc)

      assert {:ok, %{formatted: "99万", displayed_value: 990_000}} =
               Number.format_compact(999_999, locale: "ja", rounding_mode: :trunc)

      assert {:ok, %{formatted: "100万", displayed_value: 1_000_000}} =
               Number.format_compact(1_000_000, locale: "ja", rounding_mode: :trunc)
    end
  end

  describe "extreme magnitudes" do
    test "i64 max and negatives" do
      assert {:ok, %{formatted: "9,223,372T", displayed_value: 9_223_372_000_000_000_000}} =
               Number.format_compact(9_223_372_036_854_775_807,
                 locale: "en",
                 rounding_mode: :trunc
               )

      assert {:ok, %{formatted: "-13K", displayed_value: -13_000}} =
               Number.format_compact(-13_132, locale: "en", rounding_mode: :trunc)
    end

    test "integers beyond i64 (BigInt path)" do
      assert {:ok, %{formatted: "12,345,678T", displayed_value: 12_345_678_000_000_000_000}} =
               Number.format_compact(12_345_678_901_234_567_890,
                 locale: "en",
                 rounding_mode: :trunc
               )
    end
  end

  describe "input domain (integer-only)" do
    test "accepts integer-valued floats and decimals" do
      assert {:ok, %{formatted: "6K", displayed_value: 6_000}} =
               Number.format_compact(6_718.0, locale: "en", rounding_mode: :trunc)

      assert {:ok, %{formatted: "6K", displayed_value: 6_000}} =
               Number.format_compact(Decimal.new("6718"), locale: "en", rounding_mode: :trunc)

      assert {:ok, %{formatted: "6K", displayed_value: 6_000}} =
               Number.format_compact(Decimal.new("6718.00"), locale: "en", rounding_mode: :trunc)
    end

    test "rejects values with a fractional part (would make displayed_value non-integer)" do
      assert {:error, :invalid_number} = Number.format_compact(6_718.5, locale: "en")
      assert {:error, :invalid_number} = Number.format_compact(2.5, locale: "en")

      assert {:error, :invalid_number} =
               Number.format_compact(Decimal.new("6718.5"), locale: "en")
    end

    test "format/2 with compact notation still accepts fractional numbers (string only)" do
      assert {:ok, "1.2K"} = Number.format(1234.5, locale: "en", notation: :compact)
      assert {:ok, "5.5"} = Number.format(5.5, locale: "en", notation: :compact)
    end
  end

  describe "locale handling" do
    test "a malformed locale is rejected" do
      assert {:error, {:invalid_option_value, :locale}} =
               Number.format_compact(1_000, locale: "!!!")
    end

    test "an unknown but well-formed locale falls back without crashing" do
      assert {:ok, %{formatted: formatted}} = Number.format_compact(1_000, locale: "zz")
      assert is_binary(formatted) and formatted != ""
    end
  end
end
