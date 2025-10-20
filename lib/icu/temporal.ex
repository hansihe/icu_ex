defmodule Icu.Temporal do
  @moduledoc """
  Locale-aware formatting for dates, times, and datetimes.

  These helpers accept native Elixir temporal structs (`Date`, `Time`,
  `NaiveDateTime`, or `DateTime`) and delegate to the ICU4X temporal formatter.
  Reach for `format/2` (or `format!/2`) when you only need a single output, or
  build a reusable formatter via `Icu.Temporal.Formatter.new/1` when you want to
  share configuration across calls.

  ## Examples

      iex> {:ok, result} = Icu.Temporal.format(~D[2024-01-15], date_fields: :ymd)
      iex> result
      "Jan 15, 2024"

      iex> {:ok, output} =
      ...>   Icu.Temporal.format(~N[2024-02-29 17:30:00],
      ...>     date_fields: :ymd,
      ...>     time_precision: :minute
      ...>   )
      iex> String.contains?(output, "Feb 29, 2024")
      true

  ## Options

  - `:length` – preset skeleton length (`:short`, `:medium`, `:long`) that combines date and time styles.
  - `:date_fields` – explicit combination of date fields to render (for example `:ymd`, `:md`, or `:y`).
  - `:time_precision` – how much of the time component to include (`:minute`, `:second`, `{:subsecond, 3}`, etc.).
  - `:zone_style` – time-zone display style, applied when the input carries zone information.
  - `:alignment` – columnar vs automatic alignment useful for fixed-width layouts.
  - `:year_style` – whether to include era information or request fully spelled-out years.
  - `:locale` – override the lookup locale; otherwise the application `:icu` `:default_locale` is used.
  """

  alias Icu.LanguageTag
  alias Icu.Temporal.Formatter

  @typedoc "Opaque reference to an ICU4X temporal formatter."
  @type formatter :: Formatter.t()

  @typedoc "Preset length for composite temporal skeletons."
  @type length :: :long | :medium | :short

  @typedoc "Field combinations used when rendering the date component."
  @type date_fields ::
          :d | :md | :ymd | :de | :mde | :ymde | :e | :m | :ym | :y

  @typedoc "Precision control for the time component."
  @type time_precision :: :hour | :minute | :second | {:subsecond, 1..9} | :minute_optional

  @typedoc "Style used when displaying time zone information."
  @type zone_style ::
          :specific_long
          | :specific_short
          | :localized_offset_long
          | :localized_offset_short
          | :generic_long
          | :generic_short
          | :location
          | :exemplar_city

  @typedoc "Alignment behaviour for formatted output."
  @type alignment :: :auto | :column

  @typedoc "Controls which year form is preferred."
  @type year_style :: :auto | :full | :with_era

  @typedoc "Inputs that can be coerced into the temporal map accepted by the NIF."
  @type native_input ::
          Elixir.Date.t() | Elixir.Time.t() | NaiveDateTime.t() | DateTime.t() | map()

  @typedoc "Keyword form of the supported options."
  @type options_list ::
          [
            {:length, length()}
            | {:date_fields, date_fields()}
            | {:time_precision, time_precision()}
            | {:zone_style, zone_style()}
            | {:alignment, alignment()}
            | {:year_style, year_style()}
            | {:locale, LanguageTag.t() | String.t() | nil}
          ]

  @typedoc "Map form of the supported options."
  @type options ::
          %{
            optional(:length) => length(),
            optional(:date_fields) => date_fields(),
            optional(:time_precision) => time_precision(),
            optional(:zone_style) => zone_style(),
            optional(:alignment) => alignment(),
            optional(:year_style) => year_style(),
            optional(:locale) => LanguageTag.t() | String.t() | nil
          }

  @type options_input :: options() | options_list() | nil

  @type format_error ::
          :invalid_formatter
          | :invalid_locale
          | :invalid_options
          | :invalid_datetime
          | :invalid_time_zone
          | :unsupported_calendar

  @doc """
  Formats a temporal input.

  Accepts Elixir `Date`, `Time`, `NaiveDateTime`, `DateTime`, or a pre-normalized
  temporal map. Returns `{:ok, formatted}` on success or an error tuple when the
  input or options cannot be processed.

  ## Examples

      iex> Icu.Temporal.format(~D[2024-01-15], date_fields: :ymd)
      {:ok, "Jan 15, 2024"}

      iex> Icu.Temporal.format(:invalid, date_fields: :ymd)
      {:error, :invalid_temporal}
  """
  @spec format(native_input(), options_input()) ::
          {:ok, String.t()} | {:error, format_error()}
  def format(input, options \\ []) do
    with {:ok, formatter} <- Formatter.new(options) do
      Formatter.format(formatter, input)
    end
  end

  @doc """
  Formats a temporal input and raises on error.

  ## Examples

      iex> Icu.Temporal.format!(~D[2024-01-15], date_fields: :ymd)
      "Jan 15, 2024"
  """
  @spec format!(native_input(), options_input()) :: String.t()
  def format!(input, options \\ []) do
    case format(input, options) do
      {:ok, result} -> result
      {:error, reason} -> raise "temporal formatting failed: #{inspect(reason)}"
    end
  end

  @doc """
  Formats a temporal input to parts using a formatter.

  Returns the string pieces tagged with their semantic part types, making it
  easier to post-process the output when building custom markup.

  ## Examples

      iex> {:ok, parts} = Icu.Temporal.format_to_parts(~D[2024-01-15], date_fields: :ymd)
      iex> Enum.map(parts, & &1.part_type)
      [:month, :literal, :integer, :day, :literal, :integer, :year]
  """
  @spec format_to_parts(native_input(), options_input()) ::
          {:ok, [map()]} | {:error, format_error()}
  def format_to_parts(input, options \\ []) do
    with {:ok, formatter} <- Formatter.new(options) do
      Formatter.format_to_parts(formatter, input)
    end
  end

  @doc """
  Formats to parts and raises on error.

  ## Examples

      iex> parts = Icu.Temporal.format_to_parts!(~D[2024-01-15], date_fields: :ymd)
      iex> Enum.count(parts)
      7
  """
  @spec format_to_parts!(native_input(), options_input()) :: [map()]
  def format_to_parts!(input, options \\ []) do
    case format_to_parts(input, options) do
      {:ok, parts} -> parts
      {:error, reason} -> raise "temporal format to parts failed: #{inspect(reason)}"
    end
  end
end
