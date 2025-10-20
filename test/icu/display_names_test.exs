defmodule Icu.DisplayNamesTest do
  use ExUnit.Case, async: true

  doctest Icu.DisplayNames

  alias Icu.DisplayNames
  alias Icu.LanguageTag

  describe "format/3" do
    test "formats locale display names using language tag resources" do
      locale = LanguageTag.parse!("en-GB")
      assert {:ok, "British English"} = DisplayNames.format(:locale, locale)
    end

    test "formats language names from atom identifiers" do
      assert {:ok, "German"} = DisplayNames.format(:language, :de)
    end

    test "returns nil when the language subtag is unknown" do
      assert {:ok, nil} = DisplayNames.format(:language, "zz")
    end

    test "errors when locale values are invalid" do
      assert {:error, :invalid_value} = DisplayNames.format(:locale, 123)
    end

    test "supports explicit options" do
      assert {:ok, "Mayan hieroglyphs"} =
               DisplayNames.format(:script, "Maya", style: :long, fallback: :code)
    end
  end
end
