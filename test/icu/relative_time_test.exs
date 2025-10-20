defmodule Icu.RelativeTimeTest do
  use ExUnit.Case, async: true

  alias Icu.RelativeTime
  alias Icu.RelativeTime.Formatter

  describe "format/3" do
    @tag :skip
    test "rejects non-numeric values" do
      formatter = %Formatter{resource: :opaque}

      assert {:error, :invalid_unit} = RelativeTime.format(formatter, "5", :day)
    end
  end

  describe "format/4" do
    @tag :skip
    test "formats relative durations" do
      assert {:ok, "in 5 days"} = RelativeTime.format(5, :day, "en")
    end

    @tag :skip
    test "propagates option validation errors" do
      assert {:error, {:invalid_options, {:invalid_option_value, :numeric, :invalid_numeric}}} =
               RelativeTime.format(5, :day, "en", numeric: :sometimes)
    end
  end

  describe "format!/3" do
    @tag :skip
    test "raises on error" do
      formatter = %Formatter{resource: :opaque}

      assert_raise RuntimeError, ~r/relative time formatting failed/, fn ->
        RelativeTime.format!(formatter, "5", :day)
      end
    end
  end

  describe "format_to_parts/3" do
    @tag :skip
    test "rejects non-numeric values" do
      formatter = %Formatter{resource: :opaque}

      assert {:error, :invalid_unit} = RelativeTime.format_to_parts(formatter, "5", :day)
    end
  end

  describe "format_to_parts!/3" do
    @tag :skip
    test "raises on error" do
      formatter = %Formatter{resource: :opaque}

      assert_raise RuntimeError, ~r/relative time formatting failed/, fn ->
        RelativeTime.format_to_parts!(formatter, "5", :day)
      end
    end
  end
end
