defmodule Icu.Temporal do
  @moduledoc """
  Locale-aware formatting for dates, times, and datetimes.

  These helpers accept native Elixir temporal structs (`Date`, `Time`,
  `NaiveDateTime`, or `DateTime`) and delegate to the ICU4X temporal formatter.
  Reach for `format/2` (or `format!/2`) when you only need a single output, or
  build a reusable formatter via `Icu.Temporal.Formatter.new/1` when you want to
  share configuration across calls.

  ## Input Types

  The formatter adapts to the type of temporal data you provide:

  - `Date` – Contains only date components (year, month, day). Only date fields will be rendered.
  - `Time` – Contains only time components (hour, minute, second, microsecond). Only time fields will be rendered.
  - `NaiveDateTime` – Contains date and time components without timezone information.
  - `DateTime` – Contains date, time, and timezone components.

  Timezone information is only formatted when a `:zone_style` option is explicitly provided.

  If you need to format only part of a `DateTime` (e.g., just the date), use Elixir's
  conversion functions like `DateTime.to_date/1` or `DateTime.to_time/1` before formatting.

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

  ### `:length`

  Preset skeleton length that combines date and time styles.

  - `:long` – A long date; typically spelled-out, as in "January 1, 2000".
  - `:medium` – A medium-sized date; typically abbreviated, as in "Jan. 1, 2000". **Default.**
  - `:short` – A short date; typically numeric, as in "1/1/2000".

  ### `:date_fields`

  Explicit combination of date fields to render. These control which date components appear in the output:

  - `:d` – The day of the month, as in "on the 1st".
  - `:md` – The month and day of the month, as in "January 1st".
  - `:ymd` – The year, month, and day of the month, as in "January 1st, 2000". **Default.**
  - `:de` – The day of the month and day of the week, as in "Saturday 1st".
  - `:mde` – The month, day of the month, and day of the week, as in "Saturday, January 1st".
  - `:ymde` – The year, month, day of the month, and day of the week, as in "Saturday, January 1st, 2000".
  - `:e` – The day of the week alone, as in "Saturday".
  - `:m` – A standalone month, as in "January".
  - `:ym` – A month and year, as in "January 2000".
  - `:y` – A year, as in "2000".

  ### `:time_precision`

  How much of the time component to include:

  - `:hour` – Display the hour. Hide all other time fields. Examples: "11 am", "16h", "07h".
  - `:minute` – Display the hour and minute. Hide the second. Examples: "11:00 am", "16:20", "07:15".
  - `:second` – Display the hour, minute, and second. Hide fractional seconds. Examples: "11:00:00 am", "16:20:00", "07:15:01". **Default.**
  - `{:subsecond, n}` – Display the hour, minute, and second with the given number of fractional second digits (1-9). Examples with `{:subsecond, 1}`: "11:00:00.0 am", "16:20:00.0", "07:15:01.8".
  - `:minute_optional` – Display the hour; display the minute if nonzero. Hide the second. Examples: "11 am", "16:20", "07:15".

  ### `:zone_style`

  Time-zone display style, applied when the input carries zone information:

  - `:specific_long` – The long specific non-location format, as in "Pacific Daylight Time".
  - `:specific_short` – The short specific non-location format, as in "PDT".
  - `:localized_offset_long` – The long offset format, as in "GMT−8:00".
  - `:localized_offset_short` – The short offset format, as in "GMT−8".
  - `:generic_long` – The long generic non-location format, as in "Pacific Time".
  - `:generic_short` – The short generic non-location format, as in "PT".
  - `:location` – The location format, as in "Los Angeles time".
  - `:exemplar_city` – The exemplar city format, as in "Los Angeles".

  ### `:alignment`

  Alignment behavior for formatted output:

  - `:auto` – Align fields as the locale specifies them to be aligned. This is the default option.
  - `:column` – Align fields as appropriate for a column layout. This option causes numeric fields to be padded when necessary. It does not impact whether a numeric or spelled-out field is chosen.

  ### `:year_style`

  Controls which year form is preferred:

  - `:auto` – Display the century and/or era when needed to disambiguate the year, based on locale preferences. This is the default option. Examples: "1000 BC", "77 AD", "1900", "24".
  - `:full` – Always display the century, and display the era when needed to disambiguate the year, based on locale preferences. Examples: "1000 BC", "77 AD", "1900", "2024".
  - `:with_era` – Always display the century and era. Examples: "1000 BC", "77 AD", "1900 AD", "2024 AD".

  ### `:locale`

  Override the lookup locale; otherwise defaults to `Icu.get_locale()` which sources from the environment.
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

  This function automatically applies sensible defaults based on the input type:
  - For `Date`: defaults to `date_fields: :ymd, length: :medium`
  - For `Time`: defaults to `time_precision: :second`
  - For `NaiveDateTime` or `DateTime`: defaults to both date and time defaults

  You can override any defaults by passing explicit options.

  ## Examples

      iex> Icu.Temporal.format(~D[2024-01-15], date_fields: :ymd)
      {:ok, "Jan 15, 2024"}

      iex> Icu.Temporal.format(:invalid, date_fields: :ymd)
      {:error, :invalid_temporal}
  """
  @spec format(native_input(), options_input()) ::
          {:ok, String.t()} | {:error, format_error()}
  def format(input, options \\ []) do
    options_with_defaults = apply_defaults(input, options)

    with {:ok, formatter} <- Formatter.new(options_with_defaults) do
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

  Like `format/2`, this function automatically applies sensible defaults based
  on the input type.

  ## Examples

      iex> {:ok, parts} = Icu.Temporal.format_to_parts(~D[2024-01-15], date_fields: :ymd)
      iex> Enum.map(parts, & &1.part_type)
      [:month, :literal, :integer, :day, :literal, :integer, :year]
  """
  @spec format_to_parts(native_input(), options_input()) ::
          {:ok, [map()]} | {:error, format_error()}
  def format_to_parts(input, options \\ []) do
    options_with_defaults = apply_defaults(input, options)

    with {:ok, formatter} <- Formatter.new(options_with_defaults) do
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

  # Private functions

  defp apply_defaults(input, options) do
    options = normalize_options(options)

    has_date = has_date_component?(input)
    has_time = has_time_component?(input)

    options
    |> maybe_add_date_defaults(has_date)
    |> maybe_add_time_defaults(has_time)
  end

  defp normalize_options(options) when is_list(options), do: Map.new(options)
  defp normalize_options(options) when is_map(options), do: options
  defp normalize_options(nil), do: %{}

  defp has_date_component?(%{year: _, month: _, day: _}), do: true
  defp has_date_component?(_), do: false

  defp has_time_component?(%{hour: _, minute: _, second: _}), do: true
  defp has_time_component?(_), do: false

  defp maybe_add_date_defaults(options, true) do
    options
    |> Map.put_new(:date_fields, :ymd)
    |> Map.put_new(:length, :medium)
  end

  defp maybe_add_date_defaults(options, false), do: options

  defp maybe_add_time_defaults(options, true) do
    Map.put_new(options, :time_precision, :second)
  end

  defp maybe_add_time_defaults(options, false), do: options
end
