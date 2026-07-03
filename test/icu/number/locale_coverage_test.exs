defmodule Icu.Number.LocaleCoverageTest do
  use ExUnit.Case, async: true

  alias Icu.Number

  # Every locale Fresha ships (b2c gateway catalogs + en-US). The point of this
  # file is to guard the invariants programmatically across all of them rather
  # than pinning 38 hand-derived strings; a distinctive subset is pinned exactly.
  @locales ~w(
    ar bg-BG cs-CZ da-DK de-DE el-GR en-GB en-US es-ES es-MX fi-FI fr-CA fr-FR
    hr-HR hu-HU id-ID it-IT ja-JP ko-KR lt-LT ms-MY nb-NO nl-NL pl-PL pt-BR pt-PT
    ro-RO ru-RU sl-SI sq-AL sr-Latn sv-SE th-TH tr-TR uk-UA vi-VN zh-CN zh-HK
  )

  @values [780, 6_718, 194_438, 2_500_000]

  describe "compact invariants across all shipped locales" do
    test "every locale/value produces a sane, self-consistent compact result" do
      for locale <- @locales, n <- @values do
        assert {:ok, %{formatted: formatted, displayed_value: displayed}} =
                 Number.format_compact(n, locale: locale, rounding_mode: :trunc),
               "#{locale} #{n}: format_compact failed"

        # (a) non-empty string
        assert is_binary(formatted) and formatted != "",
               "#{locale} #{n}: empty formatted string"

        # (b) trunc never overstates the input
        assert displayed <= n, "#{locale} #{n}: displayed #{displayed} overstates input"
        assert displayed > 0, "#{locale} #{n}: displayed #{displayed} not positive"

        # (c) the displayed value is compact-round: re-formatting it is a fixpoint
        assert {:ok, %{formatted: ^formatted}} =
                 Number.format_compact(displayed, locale: locale, rounding_mode: :trunc),
               "#{locale} #{n}: displayed #{displayed} is not a formatting fixpoint (#{inspect(formatted)})"
      end
    end

    # Invariant (d) — "an un-abbreviated compact value equals the standard format" —
    # only holds for values no locale abbreviates. displayed_value == input is NOT
    # sufficient (ja/ko/zh render 2_500_000 as "250万"/"250만", displayed 2_500_000).
    # 780 is below every locale's compact threshold, so it is the honest case.
    test "un-abbreviated values match standard notation" do
      for locale <- @locales do
        assert {:ok, %{formatted: compact, displayed_value: 780}} =
                 Number.format_compact(780, locale: locale, rounding_mode: :trunc),
               "#{locale}: 780 was unexpectedly abbreviated"

        assert {:ok, standard} = Number.format(780, locale: locale, maximum_fraction_digits: 0)

        assert compact == standard,
               "#{locale}: compact 780 #{inspect(compact)} != standard #{inspect(standard)}"
      end
    end
  end

  describe "percent invariants across all shipped locales" do
    test "every locale formats a ratio without crashing" do
      for locale <- @locales do
        assert {:ok, formatted} = Number.format(0.5, locale: locale, style: :percent),
               "#{locale}: percent format failed"

        assert is_binary(formatted) and formatted != "",
               "#{locale}: empty percent string"
      end
    end
  end

  # Distinctive behaviour pinned exactly (verbatim ICU4X output). Notable:
  #   - ja/ko/zh-CN use CJK myriad (万 / 만) grouping — 194_438 -> "19万" (190_000).
  #   - zh-HK short compact uses Latin "K"/"M", NOT 萬: 194_438 -> "194K", 15_000 -> "15K".
  #   - ar/el/tr/uk use their own thousand affixes with a no-break space.
  describe "distinctive compact strings" do
    test "CJK myriad grouping (万 / 만)" do
      assert {:ok, %{formatted: "19万", displayed_value: 190_000}} =
               Number.format_compact(194_438, locale: "zh-CN", rounding_mode: :trunc)

      assert {:ok, %{formatted: "19万", displayed_value: 190_000}} =
               Number.format_compact(194_438, locale: "ja-JP", rounding_mode: :trunc)

      assert {:ok, %{formatted: "19만", displayed_value: 190_000}} =
               Number.format_compact(194_438, locale: "ko-KR", rounding_mode: :trunc)
    end

    test "myriad boundary at 10,000" do
      assert {:ok, %{formatted: "1만", displayed_value: 10_000}} =
               Number.format_compact(15_000, locale: "ko-KR", rounding_mode: :trunc)

      assert {:ok, %{formatted: "1万", displayed_value: 10_000}} =
               Number.format_compact(15_000, locale: "zh-CN", rounding_mode: :trunc)
    end

    test "zh-HK short compact uses Latin K/M, not 萬" do
      assert {:ok, %{formatted: "194K", displayed_value: 194_000}} =
               Number.format_compact(194_438, locale: "zh-HK", rounding_mode: :trunc)

      # 15_000 stays "15K" rather than collapsing to a myriad unit.
      assert {:ok, %{formatted: "15K", displayed_value: 15_000}} =
               Number.format_compact(15_000, locale: "zh-HK", rounding_mode: :trunc)
    end

    test "locale thousand affixes" do
      assert {:ok, %{formatted: "194 ألف", displayed_value: 194_000}} =
               Number.format_compact(194_438, locale: "ar", rounding_mode: :trunc)

      assert {:ok, %{formatted: "194 χιλ.", displayed_value: 194_000}} =
               Number.format_compact(194_438, locale: "el-GR", rounding_mode: :trunc)

      assert {:ok, %{formatted: "194 B", displayed_value: 194_000}} =
               Number.format_compact(194_438, locale: "tr-TR", rounding_mode: :trunc)

      assert {:ok, %{formatted: "194 тис.", displayed_value: 194_000}} =
               Number.format_compact(194_438, locale: "uk-UA", rounding_mode: :trunc)

      assert {:ok, %{formatted: "194K", displayed_value: 194_000}} =
               Number.format_compact(194_438, locale: "th-TH", rounding_mode: :trunc)
    end
  end
end
