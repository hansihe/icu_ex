defmodule Icu.Experimental.Currency do
  @moduledoc """
  Locale-aware currency formatting.

  `format/2` delegates to the ICU4X currency formatter using the application
  locale (`:icu, :default_locale`). Use the convenience API for one-off
  conversions or build a persistent formatter via `Icu.Currency.Formatter.new/1`
  when you need to reuse the same configuration.

  ## Examples

      iex> Icu.Experimental.Currency.format(1234.56, currency: "USD")
      {:ok, "$1,234.56"}

      iex> Icu.Experimental.Currency.format(1234.56, currency: "EUR", locale: "de-DE")
      {:ok, "1.234,56\u00A0€"}

  ## Options

  - `:currency` – **required** – ISO 4217 currency code (e.g. `"USD"`, `"EUR"`, `"JPY"`).
  - `:width` – display width (`:short`, `:narrow`, `:long`). Defaults to `:short`.
  - `:locale` – override the locale for this invocation.
  """

  alias Icu.LanguageTag
  alias Icu.Experimental.Currency.Formatter

  @typedoc "Opaque reference to an ICU4X currency formatter."
  @type formatter :: Formatter.t()

  @typedoc "ISO 4217 currency code."
  @type currency :: String.t()

  @typedoc "Controls the display width of the currency."
  @type width :: :short | :narrow | :long

  @type fractions :: %{
          digits: non_neg_integer(),
          rounding: non_neg_integer(),
          cash_digits: non_neg_integer(),
          cash_rounding: non_neg_integer()
        }

  @typedoc """
  Controls which fraction digits/rounding increment to use.

  - `:iso` (default) — standard `digits` / `rounding` from CLDR fractions data
  - `:cash` — `cash_digits` / `cash_rounding` from CLDR fractions data
  - non-negative integer — round to exactly N digits, no increment rounding
  """
  @type currency_digits :: :iso | :cash | non_neg_integer()

  @typedoc "Any `Decimal.Context` rounding mode."
  @type rounding_mode :: :down | :half_up | :half_even | :ceiling | :floor | :half_down | :up

  @typedoc "Keyword form of the supported options."
  @type options_list ::
          [
            {:currency, currency()}
            | {:width, width()}
            | {:locale, LanguageTag.t() | String.t() | nil}
            | {:currency_digits, currency_digits()}
            | {:rounding_mode, rounding_mode()}
          ]

  @typedoc "Map form of the supported options."
  @type options ::
          %{
            required(:currency) => currency(),
            optional(:width) => width(),
            optional(:locale) => LanguageTag.t() | String.t() | nil,
            optional(:currency_digits) => currency_digits(),
            optional(:rounding_mode) => rounding_mode()
          }

  @type options_input :: options() | options_list()

  @type format_error ::
          :invalid_formatter
          | :invalid_number
          | :invalid_locale
          | :invalid_options
          | :invalid_currency
          | {:missing_option, :currency}

  @doc """
  Formats a number as currency.

  Requires the `:currency` option with a valid ISO 4217 currency code.
  Returns `{:ok, String.t()}` or an error tuple when the input or options are
  invalid.

  ## Examples

      iex> Icu.Experimental.Currency.format(12345.67, currency: "USD")
      {:ok, "$12,345.67"}

      iex> Icu.Experimental.Currency.format(12345.67, currency: "USD", width: :long)
      {:ok, "12,345.67 US dollars"}
  """
  @spec format(number(), options_input()) ::
          {:ok, String.t()} | {:error, format_error()}
  def format(number, options) do
    with {:ok, formatter} <- Formatter.new(options) do
      Formatter.format(formatter, number)
    end
  end

  @doc """
  Formats a number as currency and raises on error.

  ## Examples

      iex> Icu.Experimental.Currency.format!(12345.67, currency: "USD")
      "$12,345.67"
  """
  @spec format!(number(), options_input()) :: String.t()
  def format!(number, options) do
    case format(number, options) do
      {:ok, formatted} -> formatted
      {:error, reason} -> raise "currency formatting failed: #{inspect(reason)}"
    end
  end

  @typedoc "Options for `round/2`."
  @type round_options :: %{
          required(:currency) => currency(),
          optional(:currency_digits) => currency_digits(),
          optional(:rounding_mode) => rounding_mode()
        }

  @type round_options_list :: [
          {:currency, currency()}
          | {:currency_digits, currency_digits()}
          | {:rounding_mode, rounding_mode()}
        ]

  @doc """
  Rounds a number according to CLDR currency fraction rules.

  > #### Experimental {: .warning}
  >
  > This function is experimental and implements limited CLDR currency
  > rounding functionality. The API and behaviour may change in future
  > releases.

  ## Options

  - `:currency` — **required** — ISO 4217 currency code.
  - `:currency_digits` — `:iso` (default), `:cash`, or a non-negative integer.
  - `:rounding_mode` — any `Decimal.Context` rounding mode, default `:half_even`.

  ## Examples

      iex> Icu.Experimental.Currency.round(123.456, currency: "USD")
      {:ok, Decimal.new("123.46")}

      iex> Icu.Experimental.Currency.round(123.456, currency: "JPY")
      {:ok, Decimal.new("123")}

      iex> Icu.Experimental.Currency.round(123.73, currency: "CHF", currency_digits: :cash)
      {:ok, Decimal.new("123.75")}
  """
  @spec round(number() | Decimal.t(), round_options() | round_options_list()) ::
          {:ok, Decimal.t()} | {:error, term()}
  def round(number, options), do: Formatter.round(number, options)

  @doc """
  Like `round/2`, but raises on error. See `round/2` for details.
  """
  @spec round!(number() | Decimal.t(), round_options() | round_options_list()) :: Decimal.t()
  def round!(number, options), do: Formatter.round!(number, options)

  @doc """
  Returns currency fraction data for a given ISO 4217 currency code.
  """
  @spec currency_fractions(currency()) :: {:ok, fractions()} | {:error, :invalid_currency}
  def currency_fractions(currency) do
    Icu.Nif.currency_fractions(currency)
  end
end
