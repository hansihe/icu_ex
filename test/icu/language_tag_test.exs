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

  describe "hour_cycle" do
    test "get_hour_cycle returns nil when not set" do
      tag = LanguageTag.parse!("en-US")
      assert {:ok, nil} = LanguageTag.get_hour_cycle(tag)
    end

    test "get_hour_cycle returns hour cycle when parsed from string" do
      assert {:ok, :h12} = LanguageTag.get_hour_cycle(LanguageTag.parse!("en-US-u-hc-h12"))
      assert {:ok, :h23} = LanguageTag.get_hour_cycle(LanguageTag.parse!("de-DE-u-hc-h23"))
      assert {:ok, :h11} = LanguageTag.get_hour_cycle(LanguageTag.parse!("ja-JP-u-hc-h11"))
    end

    test "set_hour_cycle adds hour cycle extension" do
      tag = LanguageTag.parse!("en-US")
      {:ok, tag_with_hc} = LanguageTag.set_hour_cycle(tag, :h23)

      assert {:ok, "en-US-u-hc-h23"} = LanguageTag.to_string(tag_with_hc)
      assert {:ok, :h23} = LanguageTag.get_hour_cycle(tag_with_hc)
    end

    test "set_hour_cycle replaces existing hour cycle" do
      tag = LanguageTag.parse!("en-US-u-hc-h12")
      {:ok, updated} = LanguageTag.set_hour_cycle(tag, :h23)

      assert {:ok, :h23} = LanguageTag.get_hour_cycle(updated)
    end

    test "set_hour_cycle works with all valid hour cycles" do
      tag = LanguageTag.parse!("en")

      {:ok, h11} = LanguageTag.set_hour_cycle(tag, :h11)
      assert {:ok, :h11} = LanguageTag.get_hour_cycle(h11)

      {:ok, h12} = LanguageTag.set_hour_cycle(tag, :h12)
      assert {:ok, :h12} = LanguageTag.get_hour_cycle(h12)

      {:ok, h23} = LanguageTag.set_hour_cycle(tag, :h23)
      assert {:ok, :h23} = LanguageTag.get_hour_cycle(h23)
    end

    test "set_hour_cycle rejects invalid hour cycle" do
      tag = LanguageTag.parse!("en-US")
      assert {:error, :invalid_options} = LanguageTag.set_hour_cycle(tag, :h24)
      assert {:error, :invalid_options} = LanguageTag.set_hour_cycle(tag, :invalid)
    end

    test "set_hour_cycle! raises on invalid hour cycle" do
      tag = LanguageTag.parse!("en-US")

      assert_raise ArgumentError, fn ->
        LanguageTag.set_hour_cycle!(tag, :invalid)
      end
    end

    test "hour cycle is preserved with other unicode extensions" do
      tag = LanguageTag.parse!("en-US-u-ca-buddhist")
      {:ok, tag_with_hc} = LanguageTag.set_hour_cycle(tag, :h23)

      {:ok, str} = LanguageTag.to_string(tag_with_hc)
      assert str =~ "hc-h23"
      assert str =~ "ca-buddhist"
    end
  end
end
