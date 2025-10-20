defmodule Icu.CalendarTest do
  use ExUnit.Case, async: true

  defmodule CalendarWithType do
    def calendar_type, do: :buddhist
  end

  defmodule CalendarWithCldrType do
    def cldr_calendar_type, do: "islamic"
  end

  defmodule CalendarFallback do
  end

  defmodule CalendarWithInvalidType do
    def calendar_type, do: %{unexpected: :value}
  end

  describe "normalize_identifier/1" do
    test "defaults to gregorian when nil" do
      assert {:ok, :gregorian} = Icu.Calendar.normalize_identifier(nil)
    end

    test "accepts known atoms" do
      assert {:ok, :japanese} = Icu.Calendar.normalize_identifier(:japanese)
    end

    test "converts Calendar.ISO to gregorian" do
      assert {:ok, :gregorian} = Icu.Calendar.normalize_identifier(Calendar.ISO)
    end

    test "uses calendar_type/0 when provided" do
      assert {:ok, :buddhist} = Icu.Calendar.normalize_identifier(CalendarWithType)
    end

    test "uses cldr_calendar_type/0 when provided" do
      assert {:ok, "islamic"} = Icu.Calendar.normalize_identifier(CalendarWithCldrType)
    end

    test "falls back to module name when no introspection function is available" do
      assert {:ok, "Icu.CalendarTest.CalendarFallback"} =
               Icu.Calendar.normalize_identifier(CalendarFallback)
    end

    test "rejects invalid calendar_type responses" do
      assert {:error, :unsupported_calendar} =
               Icu.Calendar.normalize_identifier(CalendarWithInvalidType)
    end

    test "rejects unsupported value types" do
      assert {:error, :unsupported_calendar} = Icu.Calendar.normalize_identifier(123)
    end
  end
end
