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
  - `:locale` – override the locale for this invocation.
  """

  alias Icu.LanguageTag
  alias Icu.Number.Formatter

  @typedoc "Opaque reference to an ICU4X number formatter."
  @type formatter :: Formatter.t()

  @typedoc "Controls digit grouping behavior."
  @type grouping :: :auto | :always | :min2 | :never

  @typedoc "Controls how positive/negative signs are displayed."
  @type sign_display :: :auto | :always | :never | :except_zero | :negative

  @typedoc "Keyword form of the supported options."
  @type options_list ::
          [
            {:grouping, grouping()}
            | {:sign_display, sign_display()}
            | {:minimum_integer_digits, pos_integer()}
            | {:minimum_fraction_digits, non_neg_integer()}
            | {:maximum_fraction_digits, non_neg_integer() | nil}
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
