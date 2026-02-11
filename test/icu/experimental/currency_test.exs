defmodule Icu.Experimental.CurrencyTest do
  use ExUnit.Case, async: true

  doctest Icu.Experimental.Currency

  alias Icu.Experimental.Currency

  describe "format/2" do
    test "formats basic USD amount" do
      assert {:ok, "$12,345.67"} = Currency.format(12345.67, currency: "USD")
    end

    test "formats integer" do
      assert {:ok, formatted} = Currency.format(42, currency: "USD")
      assert formatted =~ "$"
      assert formatted =~ "42"
    end

    test "formats zero" do
      assert {:ok, formatted} = Currency.format(0, currency: "USD")
      assert formatted =~ "$"
    end

    test "formats negative amounts" do
      assert {:ok, formatted} = Currency.format(-100.50, currency: "USD")
      assert formatted =~ "$"
      assert formatted =~ "100"
    end

    test "formats EUR in de-DE" do
      assert {:ok, formatted} = Currency.format(1234.56, currency: "EUR", locale: "de-DE")
      assert formatted =~ "1.234,56"
      assert formatted =~ "€"
    end

    test "formats JPY in ja-JP" do
      assert {:ok, formatted} = Currency.format(1000, currency: "JPY", locale: "ja-JP")
      assert is_binary(formatted)
    end

    test "requires currency option" do
      assert {:error, {:missing_option, :currency}} = Currency.format(42, [])
    end

    test "rejects non-numeric values" do
      assert {:error, :invalid_number} = Currency.format(:invalid, currency: "USD")
    end

    test "rejects invalid currency code" do
      assert {:error, :invalid_currency} = Currency.format(42, currency: "INVALID")
    end
  end

  describe "format/2 with width option" do
    test "short width (default)" do
      assert {:ok, formatted} = Currency.format(42, currency: "USD")
      assert formatted =~ "$"
    end

    test "narrow width" do
      assert {:ok, formatted} = Currency.format(42, currency: "USD", width: :narrow)
      assert is_binary(formatted)
    end

    test "long width shows currency name" do
      assert {:ok, formatted} = Currency.format(42, currency: "USD", width: :long)
      assert formatted =~ "dollar"
    end
  end

  describe "format/2 with Decimal" do
    test "formats Decimal with correct precision" do
      assert {:ok, "$42.00"} = Currency.format(Decimal.new("42.00"), currency: "USD")
    end

    test "formats Decimal without trailing zeros when not in input" do
      assert {:ok, "$42"} = Currency.format(Decimal.new("42"), currency: "USD")
    end

    test "formats negative Decimal" do
      assert {:ok, formatted} = Currency.format(Decimal.new("-100.50"), currency: "USD")
      assert formatted =~ "$"
      assert formatted =~ "100"
    end

    test "formats Decimal with different locale" do
      assert {:ok, formatted} =
               Currency.format(Decimal.new("1234.56"), currency: "EUR", locale: "de-DE")

      assert formatted =~ "1.234,56"
      assert formatted =~ "€"
    end

    test "rejects Decimal NaN" do
      assert {:error, :invalid_number} = Currency.format(Decimal.new("NaN"), currency: "USD")
    end

    test "rejects Decimal Inf" do
      assert {:error, :invalid_number} = Currency.format(Decimal.new("Inf"), currency: "USD")
    end
  end

  describe "currency_fractions/1" do
    test "returns default fractions for USD" do
      assert {:ok, %{digits: 2, rounding: 0, cash_digits: 2, cash_rounding: 0}} =
               Currency.currency_fractions("USD")
    end

    test "returns zero digits for JPY" do
      assert {:ok, %{digits: 0, rounding: 0}} = Currency.currency_fractions("JPY")
    end

    test "returns 3 digits for BHD" do
      assert {:ok, %{digits: 3}} = Currency.currency_fractions("BHD")
    end

    test "returns error for invalid currency code" do
      assert {:error, :invalid_currency} = Currency.currency_fractions("XX")
    end

    test "returns error for wrong-length code" do
      assert {:error, :invalid_currency} = Currency.currency_fractions("ABCD")
      assert {:error, :invalid_currency} = Currency.currency_fractions("")
    end
  end

  describe "round/2 with :iso digits (default)" do
    test "USD rounds to 2 decimal places" do
      assert {:ok, result} = Currency.round(123.456, currency: "USD")
      assert Decimal.equal?(result, Decimal.new("123.46"))
    end

    test "JPY rounds to 0 decimal places" do
      assert {:ok, result} = Currency.round(123.456, currency: "JPY")
      assert Decimal.equal?(result, Decimal.new("123"))
    end

    test "BHD rounds to 3 decimal places" do
      assert {:ok, result} = Currency.round(123.4567, currency: "BHD")
      assert Decimal.equal?(result, Decimal.new("123.457"))
    end

    test "rounds exact values unchanged" do
      assert {:ok, result} = Currency.round(42.00, currency: "USD")
      assert Decimal.equal?(result, Decimal.new("42.00"))
    end

    test "rounds Decimal input" do
      assert {:ok, result} = Currency.round(Decimal.new("99.999"), currency: "USD")
      assert Decimal.equal?(result, Decimal.new("100.00"))
    end

    test "rounds integer input" do
      assert {:ok, result} = Currency.round(42, currency: "USD")
      assert Decimal.equal?(result, Decimal.new("42.00"))
    end

    test "rounds negative numbers" do
      assert {:ok, result} = Currency.round(-123.455, currency: "USD")
      assert Decimal.equal?(result, Decimal.new("-123.46"))
    end
  end

  describe "round/2 with :cash digits" do
    test "CHF cash rounds to nearest 0.05" do
      assert {:ok, result} = Currency.round(123.73, currency: "CHF", currency_digits: :cash)
      assert Decimal.equal?(result, Decimal.new("123.75"))
    end

    test "CHF cash rounds 123.72 down to 123.70" do
      assert {:ok, result} = Currency.round(123.72, currency: "CHF", currency_digits: :cash)
      assert Decimal.equal?(result, Decimal.new("123.70"))
    end

    test "CHF cash rounds 123.775 to 123.80" do
      assert {:ok, result} = Currency.round(123.775, currency: "CHF", currency_digits: :cash)
      assert Decimal.equal?(result, Decimal.new("123.80"))
    end

    test "USD cash same as iso (no cash rounding)" do
      assert {:ok, result} = Currency.round(123.456, currency: "USD", currency_digits: :cash)
      assert Decimal.equal?(result, Decimal.new("123.46"))
    end
  end

  describe "round/2 with integer digits" do
    test "0 digits rounds to whole number" do
      assert {:ok, result} = Currency.round(123.456, currency: "USD", currency_digits: 0)
      assert Decimal.equal?(result, Decimal.new("123"))
    end

    test "1 digit rounds to one decimal place" do
      assert {:ok, result} = Currency.round(123.456, currency: "USD", currency_digits: 1)
      assert Decimal.equal?(result, Decimal.new("123.5"))
    end

    test "4 digits preserves extra precision" do
      assert {:ok, result} = Currency.round(123.45678, currency: "USD", currency_digits: 4)
      assert Decimal.equal?(result, Decimal.new("123.4568"))
    end
  end

  describe "round/2 rounding modes" do
    test ":half_up rounds 0.5 up" do
      assert {:ok, result} = Currency.round(Decimal.new("123.455"), currency: "USD", rounding_mode: :half_up)
      assert Decimal.equal?(result, Decimal.new("123.46"))
    end

    test ":half_even rounds 0.5 to even (banker's rounding)" do
      assert {:ok, result} = Currency.round(Decimal.new("123.445"), currency: "USD", rounding_mode: :half_even)
      assert Decimal.equal?(result, Decimal.new("123.44"))

      assert {:ok, result} = Currency.round(Decimal.new("123.455"), currency: "USD", rounding_mode: :half_even)
      assert Decimal.equal?(result, Decimal.new("123.46"))
    end

    test ":floor always rounds toward negative infinity" do
      assert {:ok, result} = Currency.round(Decimal.new("123.459"), currency: "USD", rounding_mode: :floor)
      assert Decimal.equal?(result, Decimal.new("123.45"))
    end

    test ":ceiling always rounds toward positive infinity" do
      assert {:ok, result} = Currency.round(Decimal.new("123.451"), currency: "USD", rounding_mode: :ceiling)
      assert Decimal.equal?(result, Decimal.new("123.46"))
    end

    test ":down truncates toward zero" do
      assert {:ok, result} = Currency.round(Decimal.new("123.459"), currency: "USD", rounding_mode: :down)
      assert Decimal.equal?(result, Decimal.new("123.45"))
    end
  end

  describe "round/2 error cases" do
    test "returns error for invalid currency" do
      assert {:error, :invalid_currency} = Currency.round(42, currency: "XX")
    end

    test "returns error for non-numeric input" do
      assert {:error, :invalid_number} = Currency.round(:foo, currency: "USD")
    end

    test "returns error for Decimal NaN" do
      assert {:error, :invalid_number} = Currency.round(Decimal.new("NaN"), currency: "USD")
    end
  end

  describe "round!/2" do
    test "returns Decimal on success" do
      result = Currency.round!(42.123, currency: "USD")
      assert Decimal.equal?(result, Decimal.new("42.12"))
    end

    test "raises on error" do
      assert_raise RuntimeError, ~r/currency rounding failed/, fn ->
        Currency.round!(:bad, currency: "USD")
      end
    end
  end

  describe "format/2 with rounding options" do
    test "format with currency_digits rounds before formatting" do
      # JPY should show no decimals
      assert {:ok, formatted} = Currency.format(123.456, currency: "JPY", locale: "en-US", currency_digits: :iso)
      refute formatted =~ "."
    end

    test "format with cash rounding for CHF" do
      assert {:ok, formatted} = Currency.format(123.73, currency: "CHF", locale: "de-CH", currency_digits: :cash)
      assert formatted =~ "123.75"
    end

    test "format with integer digits overrides default precision" do
      assert {:ok, formatted} = Currency.format(123.456, currency: "USD", currency_digits: 0)
      assert formatted =~ "123"
      refute formatted =~ "."
    end

    test "format with rounding_mode applies before formatting" do
      assert {:ok, formatted} = Currency.format(Decimal.new("123.455"), currency: "USD", rounding_mode: :half_up)
      assert formatted =~ "123.46"
    end
  end

  describe "format!/2" do
    test "returns formatted string on success" do
      assert "$12,345.67" = Currency.format!(12345.67, currency: "USD")
    end

    test "raises on missing currency" do
      assert_raise RuntimeError, ~r/currency formatting failed/, fn ->
        Currency.format!(42, [])
      end
    end

    test "raises on invalid input" do
      assert_raise RuntimeError, ~r/currency formatting failed/, fn ->
        Currency.format!(:invalid, currency: "USD")
      end
    end
  end
end
