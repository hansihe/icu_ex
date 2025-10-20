defmodule Icu.RelativeTime.FormatterTest do
  use ExUnit.Case, async: true

  alias Icu.RelativeTime.Formatter

  describe "normalize_options/1" do
    test "normalizes format and numeric options" do
      assert {:ok, %{format: :short, numeric: :auto}} =
               Formatter.normalize_options(%{format: :short, numeric: :auto, locale: nil})
    end

    test "rejects invalid format values" do
      assert {:error, {:invalid_option_value, :format}} =
               Formatter.normalize_options(%{format: :invalid})
    end

    test "rejects invalid numeric values" do
      assert {:error, {:invalid_option_value, :numeric}} =
               Formatter.normalize_options(%{numeric: :sometimes})
    end

    test "accepts keyword input" do
      assert {:ok, %{numeric: :always}} =
               Formatter.normalize_options(numeric: :always)
    end

    test "rejects unexpected inputs" do
      assert {:error, :invalid_options} = Formatter.normalize_options(:invalid)
    end

    test "rejects unknown option keys" do
      assert {:error, {:bad_option, :unknown}} =
               Formatter.normalize_options(%{unknown: :value})
    end
  end
end
