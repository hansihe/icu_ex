defmodule Icu.DisplayNames do
  @moduledoc """
  Retrieve locale-aware display names for common identity kinds.

  Display names can be fetched by passing a `kind` (such as `:language` or `:region`)
  together with the value you want to translate. By default the application locale is
  used, but it can be overridden per call via the `:locale` option.

  ## Examples

      iex> Icu.DisplayNames.format(:language, :de)
      {:ok, "German"}

      iex> Icu.DisplayNames.format(:language, "de")
      {:ok, "German"}

      iex> Icu.DisplayNames.format(:region, "GB")
      {:ok, "United Kingdom"}

  ## Options

  - `:style` – choose between `:narrow`, `:short`, `:long`, or `:menu`. Defaults to the ICU long form.
  - `:fallback` – specify `:code` to fall back to the original value or `:none` to return `nil` when missing.
  - `:language_display` – toggle between `:dialect` and `:standard` language names.
  - `:locale` – override the lookup locale (accepts `Icu.LanguageTag.t()` or a locale string).
  """

  alias Icu.DisplayNames.Formatter

  @type kind :: :locale | :language | :region | :script | :variant

  @typedoc """
  Keyword form of the supported options.
  """
  @type options_list ::
          [
            {:style, :narrow | :short | :long | :menu | nil}
            | {:fallback, :code | :none | nil}
            | {:language_display, :dialect | :standard | nil}
            | {:locale, Icu.LanguageTag.t() | String.t() | nil}
          ]

  @typedoc "Map form of the supported options."
  @type options ::
          %{
            optional(:style) => :narrow | :short | :long | :menu | nil,
            optional(:fallback) => :code | :none | nil,
            optional(:language_display) => :dialect | :standard | nil,
            optional(:locale) => Icu.LanguageTag.t() | String.t() | nil
          }

  @type options_input :: options() | options_list() | nil

  @type error ::
          {:invalid_kind, term()}
          | {:error, :invalid_options}
          | {:error, {:bad_option, atom()}}
          | {:error, {:invalid_option_value, atom()}}
          | {:error, :invalid_locale}
          | {:error, :invalid_formatter}
          | {:error, :invalid_options}

  @doc """
  Formats the provided `value` for the given `kind`.

  The `kind` must be one of `:locale`, `:language`, `:region`, `:script`, or `:variant`.
  Returns `{:ok, String.t()}` or `{:ok, nil}` when the display name cannot be resolved
  and the fallback strategy allows it.

  ## Examples

      iex> Icu.DisplayNames.format(:language, :de)
      {:ok, "German"}

      iex> Icu.DisplayNames.format(:language, "nb")
      {:ok, "Norwegian Bokmål"}

      iex> Icu.DisplayNames.format(:script, "Maya", style: :long, fallback: :code)
      {:ok, "Mayan hieroglyphs"}
  """
  @spec format(kind(), term(), options_input()) ::
          {:ok, String.t() | nil} | error()
  def format(kind, value, options \\ []) do
    with {:ok, formatter} <- Formatter.new(kind, options),
         {:ok, result} <- Formatter.display_name(formatter, value) do
      {:ok, result}
    end
  end

  @doc """
  Formats a locale display name.

  ## Examples

      iex> Icu.DisplayNames.format_locale("en-GB")
      {:ok, "British English"}
  """
  @spec format_locale(term(), options_input()) :: {:ok, String.t() | nil} | error()
  def format_locale(value, options \\ []) do
    format(:locale, value, options)
  end

  @doc """
  Formats a language display name.
  """
  @spec format_language(term(), options_input()) :: {:ok, String.t() | nil} | error()
  def format_language(value, options \\ []) do
    format(:language, value, options)
  end

  @doc """
  Formats a region display name.
  """
  @spec format_region(term(), options_input()) :: {:ok, String.t() | nil} | error()
  def format_region(value, options \\ []) do
    format(:region, value, options)
  end

  @doc """
  Formats a script display name.
  """
  @spec format_script(term(), options_input()) :: {:ok, String.t() | nil} | error()
  def format_script(value, options \\ []) do
    format(:script, value, options)
  end

  @doc """
  Formats a variant display name.
  """
  @spec format_variant(term(), options_input()) :: {:ok, String.t() | nil} | error()
  def format_variant(value, options \\ []) do
    format(:variant, value, options)
  end

  @doc """
  Formats a value and raises on error.
  """
  @spec format!(kind(), term(), options_input()) :: String.t() | nil
  def format!(kind, value, options \\ []) do
    case format(kind, value, options) do
      {:ok, result} ->
        result

      {:invalid_kind, reason} ->
        raise ArgumentError, "invalid display name kind: #{inspect(reason)}"

      {:error, reason} ->
        raise "display names formatting failed: #{inspect(reason)}"
    end
  end

  @doc """
  Formats a locale display name and raises on error.
  """
  @spec format_locale!(term(), options_input()) :: String.t() | nil
  def format_locale!(value, options \\ []) do
    format!(:locale, value, options)
  end

  @doc """
  Formats a language display name and raises on error.

  ## Examples

      iex> Icu.DisplayNames.format_language!(:de)
      "German"
  """
  @spec format_language!(term(), options_input()) :: String.t() | nil
  def format_language!(value, options \\ []) do
    format!(:language, value, options)
  end

  @doc """
  Formats a region display name and raises on error.
  """
  @spec format_region!(term(), options_input()) :: String.t() | nil
  def format_region!(value, options \\ []) do
    format!(:region, value, options)
  end

  @doc """
  Formats a script display name and raises on error.
  """
  @spec format_script!(term(), options_input()) :: String.t() | nil
  def format_script!(value, options \\ []) do
    format!(:script, value, options)
  end

  @doc """
  Formats a variant display name and raises on error.
  """
  @spec format_variant!(term(), options_input()) :: String.t() | nil
  def format_variant!(value, options \\ []) do
    format!(:variant, value, options)
  end
end
