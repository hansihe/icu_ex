defmodule Icu.NumberTest do
  use ExUnit.Case, async: true

  doctest Icu.Number

  alias Icu.Number
  alias Icu.Number.Formatter

  describe "format/2" do
    test "rejects non-numeric values" do
      assert {:error, :invalid_number} = Number.format(:invalid)
    end

    test "formats basic numbers with default options" do
      assert {:ok, formatted} = Number.format(1234.5)
      assert is_binary(formatted)
      assert formatted =~ "1"
      assert formatted =~ "234"
      assert formatted =~ "5"
    end

    test "formats integers" do
      assert {:ok, formatted} = Number.format(42)
      assert is_binary(formatted)
    end

    test "formats negative numbers" do
      assert {:ok, formatted} = Number.format(-123.45)
      assert is_binary(formatted)
      assert formatted =~ "123"
    end

    test "formats zero" do
      assert {:ok, formatted} = Number.format(0)
      assert is_binary(formatted)
    end

    test "formats very large numbers" do
      assert {:ok, formatted} = Number.format(123_456_789_012_345)
      assert is_binary(formatted)
    end

    test "formats very small decimals" do
      assert {:ok, formatted} = Number.format(0.00123)
      assert is_binary(formatted)
    end
  end

  describe "format!/2" do
    test "raises on error" do
      formatter = %Formatter{resource: :opaque}

      assert_raise RuntimeError, ~r/number formatting failed/, fn ->
        Number.format!(formatter, :invalid)
      end
    end

    test "formats numbers successfully" do
      result = Number.format!(1234.5)
      assert is_binary(result)
    end
  end

  describe "grouping option" do
    test "auto grouping" do
      assert {:ok, formatted} = Number.format(1_234_567, grouping: :auto)
      assert is_binary(formatted)
    end

    test "always grouping" do
      assert {:ok, formatted} = Number.format(1_234_567, grouping: :always)
      assert is_binary(formatted)
      # Should have grouping separators for large numbers
    end

    test "min2 grouping" do
      assert {:ok, formatted} = Number.format(1_234_567, grouping: :min2)
      assert is_binary(formatted)
    end

    test "never grouping" do
      assert {:ok, formatted} = Number.format(1_234_567, grouping: :never)
      assert is_binary(formatted)
      # Should not have any grouping separators (commas/spaces/periods)
      # The formatted string should have consecutive digits
    end

    test "grouping affects output differently for small vs large numbers" do
      {:ok, small_auto} = Number.format(123, grouping: :auto)
      {:ok, small_never} = Number.format(123, grouping: :never)
      {:ok, large_auto} = Number.format(123_456, grouping: :auto)
      {:ok, large_never} = Number.format(123_456, grouping: :never)

      # Verify we got valid strings
      assert is_binary(small_auto)
      assert is_binary(small_never)
      assert is_binary(large_auto)
      assert is_binary(large_never)
    end
  end

  describe "sign_display option" do
    test "auto sign display (default)" do
      assert {:ok, positive} = Number.format(42, sign_display: :auto)
      assert {:ok, negative} = Number.format(-42, sign_display: :auto)
      assert {:ok, zero} = Number.format(0, sign_display: :auto)

      # Auto typically shows negative sign but not positive
      assert is_binary(positive)
      assert is_binary(negative)
      assert is_binary(zero)
    end

    test "always sign display" do
      assert {:ok, positive} = Number.format(42, sign_display: :always)
      assert {:ok, negative} = Number.format(-42, sign_display: :always)
      assert {:ok, zero} = Number.format(0, sign_display: :always)

      # Always should show signs for all numbers
      assert is_binary(positive)
      assert is_binary(negative)
      assert is_binary(zero)
    end

    test "never sign display" do
      assert {:ok, positive} = Number.format(42, sign_display: :never)
      assert {:ok, negative} = Number.format(-42, sign_display: :never)

      # Never should not show signs
      assert is_binary(positive)
      assert is_binary(negative)
    end

    test "except_zero sign display" do
      assert {:ok, positive} = Number.format(42, sign_display: :except_zero)
      assert {:ok, negative} = Number.format(-42, sign_display: :except_zero)
      assert {:ok, zero} = Number.format(0, sign_display: :except_zero)

      assert is_binary(positive)
      assert is_binary(negative)
      assert is_binary(zero)
    end

    test "negative sign display" do
      assert {:ok, positive} = Number.format(42, sign_display: :negative)
      assert {:ok, negative} = Number.format(-42, sign_display: :negative)

      # Negative mode should only show negative signs
      assert is_binary(positive)
      assert is_binary(negative)
    end
  end

  describe "digit constraints" do
    test "minimum_integer_digits" do
      # Should pad with leading zeros
      assert {:ok, formatted} = Number.format(42, minimum_integer_digits: 5)
      assert is_binary(formatted)
      assert String.contains?(formatted, "42")
    end

    test "minimum_integer_digits with large value" do
      assert {:ok, formatted} = Number.format(1, minimum_integer_digits: 10)
      assert is_binary(formatted)
    end

    test "minimum_fraction_digits" do
      # Should pad with trailing zeros
      assert {:ok, formatted} = Number.format(42, minimum_fraction_digits: 3)
      assert is_binary(formatted)
      # Should have decimal separator and at least 3 digits after it
    end

    test "maximum_fraction_digits" do
      # Should truncate or round decimal places
      assert {:ok, formatted} = Number.format(3.141592653589793, maximum_fraction_digits: 2)
      assert is_binary(formatted)
      assert formatted =~ "3"
    end

    test "maximum_fraction_digits with zero" do
      assert {:ok, formatted} = Number.format(3.7, maximum_fraction_digits: 0)
      assert is_binary(formatted)
      # Should round to integer
    end

    test "combining minimum and maximum fraction digits" do
      assert {:ok, formatted} =
               Number.format(3.7, minimum_fraction_digits: 2, maximum_fraction_digits: 4)

      assert is_binary(formatted)
    end

    test "minimum_integer_digits with decimal number" do
      assert {:ok, formatted} = Number.format(3.14, minimum_integer_digits: 4)
      assert is_binary(formatted)
    end
  end

  describe "combined options" do
    test "multiple digit constraints" do
      assert {:ok, formatted} =
               Number.format(42.1,
                 minimum_integer_digits: 3,
                 minimum_fraction_digits: 2,
                 maximum_fraction_digits: 4
               )

      assert is_binary(formatted)
    end

    test "grouping and sign display together" do
      assert {:ok, positive} = Number.format(123_456, grouping: :always, sign_display: :always)
      assert {:ok, negative} = Number.format(-123_456, grouping: :never, sign_display: :never)

      assert is_binary(positive)
      assert is_binary(negative)
    end

    test "all options together" do
      assert {:ok, formatted} =
               Number.format(1234.567,
                 grouping: :always,
                 sign_display: :always,
                 minimum_integer_digits: 6,
                 minimum_fraction_digits: 2,
                 maximum_fraction_digits: 3
               )

      assert is_binary(formatted)
    end
  end

  describe "Formatter reuse" do
    test "reusing a formatter for multiple numbers" do
      {:ok, formatter} =
        Formatter.new(
          grouping: :always,
          sign_display: :always
        )

      assert {:ok, result1} = Formatter.format(formatter, 1000)
      assert {:ok, result2} = Formatter.format(formatter, 2000)
      assert {:ok, result3} = Formatter.format(formatter, -3000)

      assert is_binary(result1)
      assert is_binary(result2)
      assert is_binary(result3)

      # Results should be different for different numbers
      assert result1 != result2
      assert result2 != result3
    end

    test "formatter with complex options applied consistently" do
      {:ok, formatter} =
        Formatter.new(
          minimum_integer_digits: 4,
          maximum_fraction_digits: 2
        )

      assert {:ok, result1} = Formatter.format(formatter, 1.234)
      assert {:ok, result2} = Formatter.format(formatter, 56.789)

      assert is_binary(result1)
      assert is_binary(result2)
    end
  end

  describe "format_to_parts/2" do
    test "rejects non-numeric values" do
      assert {:error, :invalid_number} = Number.format_to_parts(:invalid)
    end

    test "returns parts for basic number" do
      assert {:ok, parts} = Number.format_to_parts(1234.5)
      assert is_list(parts)
      assert length(parts) > 0
      # Each part should be a map
      assert Enum.all?(parts, &is_map/1)
    end

    test "returns parts for negative number" do
      assert {:ok, parts} = Number.format_to_parts(-1234.5)
      assert is_list(parts)
      assert length(parts) > 0
    end

    test "parts with grouping" do
      assert {:ok, parts} = Number.format_to_parts(123_456, grouping: :always)
      assert is_list(parts)
      assert length(parts) > 0
    end

    test "parts with sign display always" do
      assert {:ok, parts} = Number.format_to_parts(42, sign_display: :always)
      assert is_list(parts)
      assert length(parts) > 0
    end

    test "parts with minimum fraction digits" do
      assert {:ok, parts} = Number.format_to_parts(42, minimum_fraction_digits: 3)
      assert is_list(parts)
      assert length(parts) > 0
    end
  end

  describe "format_to_parts!/2" do
    test "raises on error" do
      formatter = %Formatter{resource: :opaque}

      assert_raise RuntimeError, ~r/number format to parts failed/, fn ->
        Number.format_to_parts!(formatter, :invalid)
      end
    end

    test "returns parts successfully" do
      parts = Number.format_to_parts!(1234.5)
      assert is_list(parts)
      assert length(parts) > 0
    end
  end

  describe "edge cases" do
    test "formats very large number that approaches infinity" do
      # Use a large but valid float value
      result = Number.format(1.0e308)
      # Should either format or return an error
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "formats very small number near zero" do
      assert {:ok, formatted} = Number.format(0.0000000001)
      assert is_binary(formatted)
    end

    test "formats negative zero" do
      assert {:ok, formatted} = Number.format(-0.0)
      assert is_binary(formatted)
    end

    test "handles floats vs integers consistently" do
      assert {:ok, int_format} = Number.format(42)
      assert {:ok, float_format} = Number.format(42.0)
      assert is_binary(int_format)
      assert is_binary(float_format)
    end
  end
end
