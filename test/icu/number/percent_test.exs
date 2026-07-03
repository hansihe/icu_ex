defmodule Icu.Number.PercentTest do
  use ExUnit.Case, async: true

  alias Icu.Number

  # Percent follows Intl.NumberFormat semantics: the input is a ratio that gets
  # multiplied by 100, and (unlike the decimal default of 3) it shows 0 fraction
  # digits unless the caller asks for more. Expected strings are verbatim ICU4X
  # output at the pinned rev; placement and separators are locale-specific
  # (fr/de use U+00A0 NO-BREAK SPACE, ar wraps digits in U+200E LTR marks).

  describe "ratio semantics" do
    test "multiplies the input by 100" do
      assert {:ok, "50%"} = Number.format(0.5, locale: "en-US", style: :percent)
      assert {:ok, "150%"} = Number.format(1.5, locale: "en-US", style: :percent)
      assert {:ok, "5%"} = Number.format(0.05, locale: "en-US", style: :percent)
    end

    test "defaults to 0 fraction digits" do
      assert {:ok, "50%"} = Number.format(0.505, locale: "en-US", style: :percent)
    end

    test "honours an explicit maximum_fraction_digits" do
      assert {:ok, "50.5%"} =
               Number.format(0.505, locale: "en-US", style: :percent, maximum_fraction_digits: 1)
    end

    test "negative ratios keep the sign" do
      assert {:ok, "-50%"} = Number.format(-0.5, locale: "en-US", style: :percent)
    end
  end

  describe "locale placement" do
    test "en-US suffixes the sign" do
      assert {:ok, "50%"} = Number.format(0.5, locale: "en-US", style: :percent)
    end

    test "tr-TR prefixes the sign" do
      assert {:ok, "%50"} = Number.format(0.5, locale: "tr-TR", style: :percent)
    end

    test "fr-FR uses a no-break space before the sign" do
      assert {:ok, "50 %"} = Number.format(0.5, locale: "fr-FR", style: :percent)
    end

    test "de-DE uses a no-break space before the sign" do
      assert {:ok, "50 %"} = Number.format(0.5, locale: "de-DE", style: :percent)
    end

    test "ar wraps the percent sign in directionality marks" do
      assert {:ok, "50‎%‎"} = Number.format(0.5, locale: "ar", style: :percent)
    end
  end

  describe "constraints" do
    test "percent cannot be combined with compact notation" do
      assert {:error, :invalid_options} =
               Number.format(0.5, locale: "en-US", style: :percent, notation: :compact)
    end

    test "rejects an invalid style" do
      assert {:error, _} = Number.format(0.5, locale: "en-US", style: :bogus)
    end

    test "format! raises on error" do
      assert_raise RuntimeError, fn ->
        Number.format!(0.5, locale: "en-US", style: :percent, notation: :compact)
      end
    end
  end
end
