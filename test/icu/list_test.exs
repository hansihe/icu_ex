defmodule Icu.ListTest do
  use ExUnit.Case, async: true

  doctest Icu.List

  alias Icu.List

  describe "format/2" do
    test "rejects non-enumerable values" do
      assert {:error, :invalid_items} = List.format(123)
    end

    test "rejects empty lists" do
      assert {:error, :invalid_items} = List.format([])
    end

    test "simple format with default options (and, wide)" do
      assert {:ok, "Foo, Bar, and Baz"} = List.format(["Foo", "Bar", "Baz"])
    end

    test "formats with type: :or" do
      assert {:ok, result} = List.format(["Foo", "Bar", "Baz"], type: :or)
      assert result =~ "or"
      # Should contain "Foo, Bar, or Baz" for English locale
      assert result == "Foo, Bar, or Baz"
    end

    test "formats with type: :unit" do
      assert {:ok, result} = List.format(["5 feet", "2 inches"], type: :unit)
      # Units should be formatted without "and" or commas
      assert result == "5 feet, 2 inches"
    end

    test "formats with width: :short" do
      assert {:ok, result} = List.format(["Foo", "Bar", "Baz"], width: :short)
      # Short width typically uses "&" or similar abbreviation
      assert result =~ ~r/(Foo.*Bar.*Baz)|(&)/
    end

    test "formats with width: :narrow" do
      assert {:ok, result} = List.format(["Foo", "Bar", "Baz"], width: :narrow)
      # Narrow width is the most compact form
      assert result =~ "Foo"
      assert result =~ "Bar"
      assert result =~ "Baz"
    end

    test "formats with combined options: type and width" do
      # or + short
      assert {:ok, result1} = List.format(["Foo", "Bar"], type: :or, width: :short)
      assert result1 =~ "Foo"
      assert result1 =~ "Bar"

      # unit + narrow
      assert {:ok, result2} = List.format(["Foo", "Bar"], type: :unit, width: :narrow)
      assert result2 =~ "Foo"
      assert result2 =~ "Bar"
    end

    test "formats two items" do
      assert {:ok, result} = List.format(["Foo", "Bar"])
      assert result =~ "and"
      # Two items should be "Foo and Bar" (no comma before "and" in English)
      assert result == "Foo and Bar"
    end

    test "formats single item" do
      assert {:ok, "Foo"} = List.format(["Foo"])
    end

    test "formats with different locales" do
      # Spanish - should use "y" for "and"
      assert {:ok, result_es} = List.format(["Uno", "Dos", "Tres"], locale: "es")
      assert result_es =~ "y"
      assert result_es =~ "Uno"
      assert result_es =~ "Dos"
      assert result_es =~ "Tres"

      # German - should use "und" for "and"
      assert {:ok, result_de} = List.format(["Eins", "Zwei", "Drei"], locale: "de")
      assert result_de =~ "und"
      assert result_de =~ "Eins"
      assert result_de =~ "Zwei"
      assert result_de =~ "Drei"

      # French - should use "et" for "and"
      assert {:ok, result_fr} = List.format(["Un", "Deux", "Trois"], locale: "fr")
      assert result_fr =~ "et"
      assert result_fr =~ "Un"
      assert result_fr =~ "Deux"
      assert result_fr =~ "Trois"
    end

    test "formats with map options" do
      assert {:ok, result} = List.format(["Foo", "Bar"], %{type: :or, width: :wide})
      assert result == "Foo or Bar"
    end

    test "handles items that need String.Chars protocol" do
      assert {:ok, result} = List.format([1, 2, 3])
      assert result == "1, 2, and 3"
    end

    test "formats ranges and other enumerables" do
      assert {:ok, result} = List.format(1..3)
      assert result == "1, 2, and 3"
    end
  end

  describe "format!/2" do
    test "returns formatted string on success" do
      assert "Foo, Bar, and Baz" = List.format!(["Foo", "Bar", "Baz"])
    end

    test "raises on empty list" do
      assert_raise RuntimeError, ~r/list formatting failed/, fn ->
        List.format!([])
      end
    end

    test "raises on non-enumerable" do
      assert_raise RuntimeError, ~r/list formatting failed/, fn ->
        List.format!(123)
      end
    end

    test "works with options" do
      result = List.format!(["Foo", "Bar"], type: :or)
      assert result == "Foo or Bar"
    end
  end

  describe "format_to_parts/2" do
    test "returns parts for simple list" do
      assert {:ok, parts} = List.format_to_parts(["Foo", "Bar", "Baz"])
      assert is_list(parts)
      assert length(parts) > 0

      # Parts should contain the elements and literals (separators/conjunctions)
      parts_string = Enum.map_join(parts, fn part -> part[:value] || part.value end)
      assert parts_string =~ "Foo"
      assert parts_string =~ "Bar"
      assert parts_string =~ "Baz"
      assert parts_string =~ "and"
    end

    test "rejects empty lists" do
      assert {:error, :invalid_items} = List.format_to_parts([])
    end

    test "rejects non-enumerable values" do
      assert {:error, :invalid_items} = List.format_to_parts(123)
    end

    test "returns parts with different types" do
      # Test :or type
      assert {:ok, parts_or} = List.format_to_parts(["Foo", "Bar"], type: :or)
      parts_or_string = Enum.map_join(parts_or, fn part -> part[:value] || part.value end)
      assert parts_or_string == "Foo or Bar"

      # Test :unit type
      assert {:ok, parts_unit} = List.format_to_parts(["Foo", "Bar"], type: :unit)
      parts_unit_string = Enum.map_join(parts_unit, fn part -> part[:value] || part.value end)
      assert parts_unit_string =~ "Foo"
      assert parts_unit_string =~ "Bar"
    end

    test "returns parts with different widths" do
      assert {:ok, parts_short} = List.format_to_parts(["Foo", "Bar"], width: :short)
      assert is_list(parts_short)
      assert length(parts_short) > 0

      assert {:ok, parts_narrow} = List.format_to_parts(["Foo", "Bar"], width: :narrow)
      assert is_list(parts_narrow)
      assert length(parts_narrow) > 0
    end

    test "returns parts for single item" do
      assert {:ok, parts} = List.format_to_parts(["Foo"])
      assert is_list(parts)
      # Single item should just have the element itself
      parts_string = Enum.map_join(parts, fn part -> part[:value] || part.value end)
      assert parts_string == "Foo"
    end

    test "returns parts with locale" do
      assert {:ok, parts} = List.format_to_parts(["Uno", "Dos"], locale: "es")
      assert is_list(parts)
      parts_string = Enum.map_join(parts, fn part -> part[:value] || part.value end)
      # Spanish uses "y" for "and"
      assert parts_string =~ "y"
    end

    test "parts have expected structure with part_type and value" do
      assert {:ok, parts} = List.format_to_parts(["A", "B"])
      assert is_list(parts)

      # Each part should be a map with :part_type and :value atom keys
      Enum.each(parts, fn part ->
        assert is_map(part)
        assert Map.has_key?(part, :part_type)
        assert Map.has_key?(part, :value)
        assert is_atom(part[:part_type])
        assert is_binary(part[:value])
      end)
    end
  end

  describe "format_to_parts!/2" do
    test "returns parts on success" do
      parts = List.format_to_parts!(["Foo", "Bar", "Baz"])
      assert is_list(parts)
      assert length(parts) > 0

      # Verify parts contain expected content
      parts_string = Enum.map_join(parts, fn part -> part[:value] || part.value end)
      assert parts_string == "Foo, Bar, and Baz"
    end

    test "raises on empty list" do
      assert_raise RuntimeError, ~r/list format to parts failed/, fn ->
        List.format_to_parts!([])
      end
    end

    test "raises on non-enumerable" do
      assert_raise RuntimeError, ~r/list format to parts failed/, fn ->
        List.format_to_parts!(123)
      end
    end

    test "works with options" do
      parts = List.format_to_parts!(["Foo", "Bar"], type: :or, width: :short)
      assert is_list(parts)

      # Verify the :or type is applied
      parts_string = Enum.map_join(parts, fn part -> part[:value] || part.value end)
      assert parts_string =~ "Foo"
      assert parts_string =~ "Bar"
    end
  end
end
