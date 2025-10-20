defmodule Icu.LanguageTagTest do
  use ExUnit.Case, async: true

  alias Icu.LanguageTag

  test "simple locale parsing" do
    LanguageTag.parse!("en-US")
    LanguageTag.parse!("en")
    LanguageTag.parse!("nb")
  end

  describe "match_gettext/2" do
    test "simple matches work" do
      assert {:ok, "en"} == LanguageTag.match_gettext(LanguageTag.parse!("en-US"), ["en", "fr"])

      assert {:ok, "en_US"} ==
               LanguageTag.match_gettext(LanguageTag.parse!("en-US"), ["en_US", "fr"])

      assert {:ok, "en-US"} ==
               LanguageTag.match_gettext(LanguageTag.parse!("en-US"), ["en-US", "fr"])

      assert {:error, :no_match} ==
               LanguageTag.match_gettext(LanguageTag.parse!("no-NB"), ["en-US", "fr"])
    end
  end
end
