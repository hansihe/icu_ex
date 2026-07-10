defmodule Icu.Number.FormatterTest do
  use ExUnit.Case, async: true

  alias Icu.Number.Formatter

  describe "normalize_options/1" do
    test "drops nil maximum fraction digits like any other unset option" do
      assert {:ok, options} = Formatter.normalize_options(maximum_fraction_digits: nil)
      refute Map.has_key?(options, :maximum_fraction_digits)
    end

    test "keeps :unbounded maximum fraction digits as an explicit no-maximum request" do
      assert {:ok, %{maximum_fraction_digits: :unbounded}} =
               Formatter.normalize_options(maximum_fraction_digits: :unbounded)
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
