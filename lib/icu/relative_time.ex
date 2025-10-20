defmodule Icu.RelativeTime do
  @moduledoc """
  High-level API for ICU4X-powered relative time formatting.

  Use `format/4` to generate localized relative phrases like “in 3 days”, or
  build reusable formatter structs with `formatter/2` for repeated usage.
  """

  alias Icu.LanguageTag
  alias Icu.RelativeTime.Formatter

  @typedoc "Opaque reference to an ICU4X relative time formatter."
  @type formatter :: Formatter.t()

  @typedoc "Supported relative time units."
  @type unit :: :second | :minute | :hour | :day | :week | :month | :quarter | :year

  @typedoc "Controls the overall style of the relative time output."
  @type format :: :wide | :short | :narrow

  @typedoc "Controls whether relative phrases can be non-numeric."
  @type numeric :: :always | :auto

  @typedoc "Keyword form of the supported options."
  @type options_list ::
          [
            {:format, format()}
            | {:numeric, numeric()}
            | {:locale, LanguageTag.t() | nil}
          ]

  @typedoc "Map form of the supported options."
  @type options ::
          %{
            optional(:format) => format(),
            optional(:numeric) => numeric(),
            optional(:locale) => LanguageTag.t() | nil
          }

  @type options_input :: options() | options_list() | nil

  @type format_error ::
          :invalid_formatter
          | :invalid_locale
          | :invalid_options
          | :invalid_unit
          | :unsupported_fraction

  @doc """
  Builds a reusable formatter for the given locale and options.
  """
  @spec formatter(LanguageTag.t() | String.t(), options_input()) ::
          {:ok, formatter()} | {:error, format_error()}
  def formatter(locale, options \\ []), do: Formatter.new(locale, options)

  @doc """
  Builds a reusable formatter and raises on error.
  """
  @spec formatter!(LanguageTag.t() | String.t(), options_input()) :: formatter()
  def formatter!(locale, options \\ []), do: Formatter.new!(locale, options)

  @doc """
  Formats a relative value using an existing formatter.
  """
  @spec format(formatter(), number(), unit()) ::
          {:ok, String.t()} | {:error, format_error()}
  def format(%Formatter{} = formatter, value, unit),
    do: Formatter.format(formatter, value, unit)

  @doc """
  Convenience helper that creates a formatter and formats in one step.
  """
  @spec format(number(), unit(), LanguageTag.t() | String.t(), options_input()) ::
          {:ok, String.t()} | {:error, format_error()}
  def format(value, unit, locale, options \\ []) do
    with {:ok, formatter} <- Formatter.new(locale, options) do
      Formatter.format(formatter, value, unit)
    end
  end

  @doc """
  Formats and raises on error.
  """
  @spec format!(formatter(), number(), unit()) :: String.t()
  def format!(%Formatter{} = formatter, value, unit),
    do: Formatter.format!(formatter, value, unit)

  @doc """
  Convenience helper that raises on error.
  """
  @spec format!(number(), unit(), LanguageTag.t() | String.t(), options_input()) :: String.t()
  def format!(value, unit, locale, options \\ []) do
    case format(value, unit, locale, options) do
      {:ok, result} -> result
      {:error, reason} -> raise "relative time formatting failed: #{inspect(reason)}"
    end
  end

  @doc """
  Formats to parts using an existing formatter.
  """
  @spec format_to_parts(formatter(), number(), unit()) ::
          {:ok, [map()]} | {:error, format_error()}
  def format_to_parts(%Formatter{} = formatter, value, unit),
    do: Formatter.format_to_parts(formatter, value, unit)

  @doc """
  Convenience helper that formats to parts in one step.
  """
  @spec format_to_parts(number(), unit(), LanguageTag.t() | String.t(), options_input()) ::
          {:ok, [map()]} | {:error, format_error()}
  def format_to_parts(value, unit, locale, options \\ []) do
    with {:ok, formatter} <- Formatter.new(locale, options) do
      Formatter.format_to_parts(formatter, value, unit)
    end
  end

  @doc """
  Formats to parts and raises on error.
  """
  @spec format_to_parts!(formatter(), number(), unit()) :: [map()]
  def format_to_parts!(%Formatter{} = formatter, value, unit),
    do: Formatter.format_to_parts!(formatter, value, unit)

  @doc """
  Convenience helper that formats to parts and raises on error.
  """
  @spec format_to_parts!(number(), unit(), LanguageTag.t() | String.t(), options_input()) :: [
          map()
        ]
  def format_to_parts!(value, unit, locale, options \\ []) do
    case format_to_parts(value, unit, locale, options) do
      {:ok, parts} -> parts
      {:error, reason} -> raise "relative time formatting failed: #{inspect(reason)}"
    end
  end
end
