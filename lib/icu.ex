defmodule Icu do
  @moduledoc """
  High-level entry point for Icu, exposing ICU4X-powered internationalisation
  helpers to Elixir.

  Most functionality is provided by specialised formatter modules:

    * `Icu.LanguageTag` - locale parsing and inspection.
    * `Icu.Number` and  - locale-aware number and formatting.
    * `Icu.List` - conjunction-aware list formatting across locales.
    * `Icu.Temporal` for locale-aware formatting of instants in time.
      Supports `Time`, `DateTime`, `NaiveDateTime`, `Date`.
    * `Icu.RelativeTime` - for locale-aware relative time formatting.

  Use these modules directly to construct formatters and render values.

  ## Locale data
  Many functions in this library relies on data from unicode CLDR to work.

  This library ships with data for all locales with coverage levels
  `basic`, `moderate` or `modern` in
  https://github.com/unicode-org/cldr-json/blob/main/cldr-json/cldr-core/coverageLevels.json
  """

  @pd_key :icu_locale

  @has_gettext? Code.ensure_loaded?(Gettext)

  alias Icu.LanguageTag

  @spec put_locale(LanguageTag.parsable()) :: :ok | LanguageTag.parse_error()
  def put_locale(locale) do
    with {:ok, language_tag} <- LanguageTag.parse(locale) do
      Process.put(@pd_key, language_tag)
      :ok
    end
  end

  @spec with_locale(LanguageTag.parsable(), (-> result)) ::
          result | LanguageTag.parse_error()
        when result: var
  def with_locale(locale, fun) when is_function(fun, 0) do
    previous_locale = Process.get(@pd_key)

    try do
      case LanguageTag.parse(locale) do
        {:ok, tag} ->
          Process.put(@pd_key, tag)

        _ ->
          nil
      end

      fun.()
    after
      if previous_locale do
        Process.put(@pd_key, previous_locale)
      else
        Process.delete(@pd_key)
      end
    end
  end

  @doc """
  Gets the current locale.

  Will resolve to, in order:
  * Get the locale for the current process
  * Get the configured default locale
  """
  @spec get_locale() :: LanguageTag.t()
  def get_locale() do
    pd_locale = Process.get(@pd_key)

    if pd_locale == nil do
      default_locale = Application.get_env(:icu, :default_locale)

      if default_locale == nil do
        raise "No default locale configured for `:icu`. Specify `:icu` `:default_locale` in config."
      else
        Icu.LanguageTag.parse!(default_locale)
      end
    else
      pd_locale
    end
  end

  if @has_gettext do
    def put_gettext_locale(backend) do
      known_locales = Gettext.known_locales(backend)

      case Icu.LanguageTag.match_gettext(get_locale(), known_locales) do
        {:ok, gettext_locale} -> Gettext.put_locale(backend, gettext_locale)
      end
    end
  end
end
