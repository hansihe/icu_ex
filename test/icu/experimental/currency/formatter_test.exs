defmodule Icu.Experimental.Currency.FormatterTest do
  use ExUnit.Case, async: true

  alias Icu.Experimental.Currency.Formatter

  describe "new/1" do
    test "creates a short (default) formatter" do
      assert {:ok, %Formatter{}} = Formatter.new(locale: "en-US", currency: "USD")
    end

    test "creates a narrow formatter" do
      assert {:ok, %Formatter{}} =
               Formatter.new(locale: "en-US", currency: "USD", width: :narrow)
    end

    test "creates a long formatter" do
      assert {:ok, %Formatter{}} =
               Formatter.new(locale: "en-US", currency: "USD", width: :long)
    end

    test "requires currency option" do
      assert {:error, {:missing_option, :currency}} = Formatter.new(locale: "en-US")
    end

    test "rejects invalid currency code" do
      assert {:error, :invalid_currency} = Formatter.new(locale: "en-US", currency: "INVALID")
    end

    test "rejects unknown options" do
      assert {:error, {:bad_option, :unknown}} =
               Formatter.new(locale: "en-US", currency: "USD", unknown: true)
    end
  end

  describe "new!/1" do
    test "returns formatter on success" do
      assert %Formatter{} = Formatter.new!(locale: "en-US", currency: "USD")
    end

    test "raises on missing currency" do
      assert_raise RuntimeError, ~r/currency formatter creation failed/, fn ->
        Formatter.new!(locale: "en-US")
      end
    end
  end

  describe "format/2 with short width" do
    setup do
      {:ok, fmt} = Formatter.new(locale: "en-US", currency: "USD")
      %{fmt: fmt}
    end

    test "formats a basic amount", %{fmt: fmt} do
      assert {:ok, "$12,345.67"} = Formatter.format(fmt, 12345.67)
    end

    test "formats an integer", %{fmt: fmt} do
      assert {:ok, formatted} = Formatter.format(fmt, 42)
      assert is_binary(formatted)
      assert formatted =~ "$"
      assert formatted =~ "42"
    end

    test "formats zero", %{fmt: fmt} do
      assert {:ok, formatted} = Formatter.format(fmt, 0)
      assert is_binary(formatted)
      assert formatted =~ "$"
    end

    test "formats negative amounts", %{fmt: fmt} do
      assert {:ok, formatted} = Formatter.format(fmt, -100.50)
      assert is_binary(formatted)
      assert formatted =~ "$"
      assert formatted =~ "100"
    end

    test "rejects non-numeric values", %{fmt: fmt} do
      assert {:error, :invalid_number} = Formatter.format(fmt, :invalid)
    end
  end

  describe "format/2 with long width" do
    test "formats with currency name in en-US" do
      {:ok, fmt} = Formatter.new(locale: "en-US", currency: "USD", width: :long)
      assert {:ok, formatted} = Formatter.format(fmt, 12345.67)
      assert is_binary(formatted)
      assert formatted =~ "12,345.67"
      assert formatted =~ "dollar"
    end

    test "formats with currency name in de-DE" do
      {:ok, fmt} = Formatter.new(locale: "de-DE", currency: "EUR", width: :long)
      assert {:ok, formatted} = Formatter.format(fmt, 12345.67)
      assert is_binary(formatted)
      assert formatted =~ "Euro"
    end
  end

  describe "format/2 with different locales" do
    test "formats EUR in de-DE" do
      {:ok, fmt} = Formatter.new(locale: "de-DE", currency: "EUR")
      assert {:ok, formatted} = Formatter.format(fmt, 1234.56)
      assert is_binary(formatted)
      # German uses period for grouping and comma for decimal
      assert formatted =~ "1.234,56"
    end

    test "formats JPY in ja-JP" do
      {:ok, fmt} = Formatter.new(locale: "ja-JP", currency: "JPY")
      assert {:ok, formatted} = Formatter.format(fmt, 1000)
      assert is_binary(formatted)
    end
  end

  describe "format!/2" do
    test "returns formatted string on success" do
      {:ok, fmt} = Formatter.new(locale: "en-US", currency: "USD")
      assert "$12,345.67" = Formatter.format!(fmt, 12345.67)
    end

    test "raises on invalid input" do
      {:ok, fmt} = Formatter.new(locale: "en-US", currency: "USD")

      assert_raise RuntimeError, ~r/currency formatting failed/, fn ->
        Formatter.format!(fmt, :invalid)
      end
    end
  end

  describe "formatter reuse" do
    test "same formatter can format multiple values" do
      {:ok, fmt} = Formatter.new(locale: "en-US", currency: "USD")

      assert {:ok, r1} = Formatter.format(fmt, 100)
      assert {:ok, r2} = Formatter.format(fmt, 200)
      assert {:ok, r3} = Formatter.format(fmt, 300)

      assert r1 != r2
      assert r2 != r3
    end
  end

  describe "normalize_options/1" do
    test "accepts valid options" do
      assert {:ok, %{currency: "USD"}} =
               Formatter.normalize_options(currency: "USD")
    end

    test "accepts width option" do
      assert {:ok, %{currency: "USD", width: :long}} =
               Formatter.normalize_options(currency: "USD", width: :long)
    end

    test "rejects invalid width" do
      assert {:error, {:invalid_option_value, :width}} =
               Formatter.normalize_options(currency: "USD", width: :invalid)
    end

    test "rejects invalid options format" do
      assert {:error, :invalid_options} = Formatter.normalize_options(:invalid)
    end
  end

  describe "inspect" do
    test "returns opaque representation" do
      {:ok, fmt} = Formatter.new(locale: "en-US", currency: "USD")
      assert inspect(fmt) == "#Icu.Currency.Formatter<>"
    end
  end
end
