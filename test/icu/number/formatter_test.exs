defmodule Icu.Number.FormatterTest do
  use ExUnit.Case, async: true

  alias Icu.Number.Formatter

  describe "normalize_options/1" do
    test "removes nil maximum fraction digits" do
      assert {:ok, %{}} =
               Formatter.normalize_options(maximum_fraction_digits: nil)
    end

    test "drops nil locale entries" do
      assert {:ok, %{}} = Formatter.normalize_options(%{locale: nil})
    end

    test "accepts map inputs" do
      assert {:ok, %{maximum_fraction_digits: 3}} =
               Formatter.normalize_options(%{maximum_fraction_digits: 3})
    end

    test "handles unexpected inputs" do
      assert {:error, :invalid_options} = Formatter.normalize_options(:invalid)
    end
  end
end
