defmodule Icu.Number do
  @moduledoc """
  Locale-aware decimal formatting.

  `format/2` delegates to the ICU4X number formatter using the application
  locale (`:icu, :default_locale`). Use the convenience API for one-off
  conversions or build a persistent formatter via `Icu.Number.Formatter.new/1`
  when you need to reuse the same configuration.

  ## Examples

      iex> Icu.Number.format(1234.5)
      {:ok, "1,234.500"}

      iex> Icu.Number.format(1234.5, maximum_fraction_digits: 1)
      {:ok, "1,234.5"}

  ## Options

  - `:grouping` – toggle locale-driven grouping rules (`:auto`, `:always`, `:min2`, `:never`).
  - `:sign_display` – control sign rendering (`:auto`, `:always`, `:never`, `:except_zero`, `:negative`).
  - `:minimum_integer_digits` – left-pad with zeros to hit a minimum integer width.
  - `:minimum_fraction_digits` – right-pad with zeros to ensure fractional precision.
  - `:maximum_fraction_digits` – clamp or round fractional precision.
  - `:style` – `:decimal` (default) or `:percent`. Percent follows `Intl.NumberFormat`
    semantics: the input is a **ratio** and is multiplied by 100 (`0.5` → `"50%"`), with
    locale-correct placement (`tr` → `"%50"`, `fr` → `"50 %"`). Cannot be combined with
    `notation: :compact`.
  - `:notation` – `:standard` (default) or `:compact` for locale-aware abbreviations
    (`194438` → `"194K"`, Japanese/Chinese group by 万). See `format_compact/2`.
  - `:compact_display` – `:short` (default, e.g. `"194K"`) or `:long` (e.g. `"194 thousand"`),
    only meaningful with `notation: :compact`.
  - `:rounding_mode` – `:half_even` (default) or `:trunc`. With `:trunc`, compact output
    never overstates the value (`6_718` → `"6K"`, never `"7K"`).
  - `:locale` – override the locale for this invocation.

  `:minimum_integer_digits`, `:minimum_fraction_digits` and `:maximum_fraction_digits`
  only apply to `:standard` notation; compact precision is locale-driven.
  """

  alias Icu.LanguageTag
  alias Icu.Number.Formatter

  @typedoc "Opaque reference to an ICU4X number formatter."
  @type formatter :: Formatter.t()

  @typedoc "Controls digit grouping behavior."
  @type grouping :: :auto | :always | :min2 | :never

  @typedoc "Controls how positive/negative signs are displayed."
  @type sign_display :: :auto | :always | :never | :except_zero | :negative

  @typedoc "Selects plain decimal or percent formatting."
  @type style :: :decimal | :percent

  @typedoc "Selects standard or compact (abbreviated) notation."
  @type notation :: :standard | :compact

  @typedoc "Controls the width of compact affixes."
  @type compact_display :: :short | :long

  @typedoc "Controls how values are rounded to the displayed precision."
  @type rounding_mode :: :half_even | :trunc

  @typedoc """
  The formatted compact string alongside the exact integer it represents.

  `:displayed_value` is what the abbreviation stands for (e.g. `194_000` for
  `"194K"`), so callers can append a localised "+" when it understates the input.
  """
  @type compact_result :: %{formatted: String.t(), displayed_value: integer()}

  @typedoc "Keyword form of the supported options."
  @type options_list ::
          [
            {:grouping, grouping()}
            | {:sign_display, sign_display()}
            | {:minimum_integer_digits, pos_integer()}
            | {:minimum_fraction_digits, non_neg_integer()}
            | {:maximum_fraction_digits, non_neg_integer() | nil}
            | {:style, style()}
            | {:notation, notation()}
            | {:compact_display, compact_display()}
            | {:rounding_mode, rounding_mode()}
            | {:locale, LanguageTag.t() | String.t() | nil}
          ]

  @typedoc "Map form of the supported options."
  @type options ::
          %{
            optional(:grouping) => grouping(),
            optional(:sign_display) => sign_display(),
            optional(:minimum_integer_digits) => pos_integer(),
            optional(:minimum_fraction_digits) => non_neg_integer(),
            optional(:maximum_fraction_digits) => non_neg_integer() | nil,
            optional(:style) => style(),
            optional(:notation) => notation(),
            optional(:compact_display) => compact_display(),
            optional(:rounding_mode) => rounding_mode(),
            optional(:locale) => LanguageTag.t() | String.t() | nil
          }

  @type options_input :: options() | options_list() | nil

  @type format_error ::
          :invalid_formatter | :invalid_number | :invalid_locale | :invalid_options

  @doc """
  Formats a number.

  Accepts any numeric type (`integer`, `float`, or decimal-like struct that
  implements the required protocol). Returns `{:ok, String.t()}` or an error tuple
  when the input or options are invalid.

  ## Examples

      iex> Icu.Number.format(-123.45)
      {:ok, "-123.450"}

      iex> Icu.Number.format(42, sign_display: :always)
      {:ok, "+42.000"}

      iex> Icu.Number.format(0.5, style: :percent)
      {:ok, "50%"}
  """
  @spec format(number(), options_input()) ::
          {:ok, String.t()} | {:error, format_error()}
  def format(number, options \\ []) do
    with {:ok, formatter} <- Formatter.new(options),
         {:ok, formatted} <- Formatter.format(formatter, number) do
      {:ok, formatted}
    end
  end

  @doc """
  Formats a number and raises on error.

  ## Examples

      iex> Icu.Number.format!(42, sign_display: :always)
      "+42.000"
  """
  @spec format!(number(), options_input()) :: String.t()
  def format!(number, options \\ []) do
    case format(number, options) do
      {:ok, formatted} -> formatted
      {:error, reason} -> raise "number formatting failed: #{inspect(reason)}"
    end
  end

  @doc """
  Formats a number in compact notation, returning both the string and the exact
  numeric value it represents.

  Always uses `notation: :compact` (any `:notation` in `options` is ignored). The
  returned `:displayed_value` is the integer the abbreviation stands for, letting
  callers detect when the display understates the input (e.g. to append a "+").

  Accepts the same options as `format/2`; `:compact_display` and `:rounding_mode`
  are the relevant knobs.

  ## Examples

      iex> Icu.Number.format_compact(194_438, locale: "en", rounding_mode: :trunc)
      {:ok, %{formatted: "194K", displayed_value: 194_000}}

      iex> Icu.Number.format_compact(6_718, locale: "en", rounding_mode: :trunc)
      {:ok, %{formatted: "6K", displayed_value: 6_000}}
  """
  @spec format_compact(number(), options_input()) ::
          {:ok, compact_result()} | {:error, format_error()}
  def format_compact(number, options \\ []) do
    with {:ok, formatter} <- Formatter.new(put_compact_notation(options)),
         {:ok, result} <- Formatter.format_compact(formatter, number) do
      {:ok, result}
    end
  end

  @doc """
  Formats a number in compact notation and raises on error.

  ## Examples

      iex> Icu.Number.format_compact!(194_438, locale: "en", rounding_mode: :trunc)
      %{formatted: "194K", displayed_value: 194_000}
  """
  @spec format_compact!(number(), options_input()) :: compact_result()
  def format_compact!(number, options \\ []) do
    case format_compact(number, options) do
      {:ok, result} -> result
      {:error, reason} -> raise "compact number formatting failed: #{inspect(reason)}"
    end
  end

  defp put_compact_notation(options) when is_map(options),
    do: Map.put(options, :notation, :compact)

  defp put_compact_notation(options) when is_list(options),
    do: Keyword.put(options, :notation, :compact)

  defp put_compact_notation(nil), do: [notation: :compact]

  @doc """
  Formats a number to parts using an existing formatter.

  Returns tagged pieces (integer, decimal separator, fraction, etc.) so callers
  can add markup around specific components.

  ## Examples

      iex> {:ok, parts} = Icu.Number.format_to_parts(123.5)
      iex> Enum.map(parts, & &1.part_type)
      [:integer, :decimal, :fraction]
  """
  @spec format_to_parts(number(), options_input()) ::
          {:ok, [map()]} | {:error, format_error()}
  def format_to_parts(number, options \\ []) do
    with {:ok, formatter} <- Formatter.new(options),
         {:ok, parts} <- Formatter.format_to_parts(formatter, number) do
      {:ok, parts}
    end
  end

  @doc """
  Formats a number to parts and raises on error.

  ## Examples

      iex> parts = Icu.Number.format_to_parts!(123.5)
      iex> Enum.count(parts)
      3
  """
  @spec format_to_parts!(number(), options_input()) :: [map()]
  def format_to_parts!(number, options \\ []) do
    case format_to_parts(number, options) do
      {:ok, parts} -> parts
      {:error, reason} -> raise "number format to parts failed: #{inspect(reason)}"
    end
  end
end
