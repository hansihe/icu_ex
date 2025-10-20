defmodule Icu.RelativeTime.Formatter do
  @moduledoc false

  alias Icu.Formatter.Options
  alias Icu.LanguageTag
  alias Icu.Nif
  alias Icu.RelativeTime

  defstruct [:resource]

  @opaque t :: %__MODULE__{}

  @spec new(LanguageTag.t() | String.t(), RelativeTime.options_input()) ::
          {:ok, t()} | {:error, RelativeTime.format_error()}
  def new(locale, options \\ []) do
    with {:ok, locale_tag} <- LanguageTag.parse(locale),
         {:ok, opts} <- normalize_options(options) do
      case Nif.relative_time_formatter_new(locale_tag.resource, Map.delete(opts, :locale)) do
        {:ok, formatter} -> {:ok, %__MODULE__{resource: formatter}}
        {:error, _} = error -> error
      end
    else
      {:error, {:bad_option, _} = reason} ->
        {:error, {:invalid_options, reason}}

      {:error, {:invalid_option_value, _, _} = reason} ->
        {:error, {:invalid_options, reason}}

      {:error, :invalid_options} = error ->
        error

      {:error, _} = error ->
        error
    end
  end

  @spec new!(LanguageTag.t() | String.t(), RelativeTime.options_input()) :: t()
  def new!(locale, options \\ []) do
    case new(locale, options) do
      {:ok, formatter} -> formatter
      {:error, reason} -> raise "relative time formatter creation failed: #{inspect(reason)}"
    end
  end

  @spec format(t(), number(), RelativeTime.unit()) ::
          {:ok, String.t()} | {:error, RelativeTime.format_error()}
  def format(%__MODULE__{resource: resource}, value, unit) when is_number(value) do
    Nif.relative_time_format(resource, value, unit)
  end

  def format(%__MODULE__{}, _value, _unit), do: {:error, :invalid_unit}

  @spec format!(t(), number(), RelativeTime.unit()) :: String.t()
  def format!(%__MODULE__{} = formatter, value, unit) do
    case format(formatter, value, unit) do
      {:ok, result} -> result
      {:error, reason} -> raise "relative time formatting failed: #{inspect(reason)}"
    end
  end

  @spec format_to_parts(t(), number(), RelativeTime.unit()) ::
          {:ok, [map()]} | {:error, RelativeTime.format_error()}
  def format_to_parts(%__MODULE__{resource: resource}, value, unit) when is_number(value) do
    Nif.relative_time_format_to_parts(resource, value, unit)
  end

  def format_to_parts(%__MODULE__{}, _value, _unit), do: {:error, :invalid_unit}

  @spec format_to_parts!(t(), number(), RelativeTime.unit()) :: [map()]
  def format_to_parts!(%__MODULE__{} = formatter, value, unit) do
    case format_to_parts(formatter, value, unit) do
      {:ok, parts} -> parts
      {:error, reason} -> raise "relative time formatting failed: #{inspect(reason)}"
    end
  end

  defimpl Inspect do
    def inspect(_formatter, _opts) do
      "#Icu.RelativeTime.Formatter<>"
    end
  end

  @doc false
  @spec normalize_options(RelativeTime.options_input()) :: {:ok, map()} | Options.error()
  def normalize_options(options) do
    Options.normalize_options(
      :relative_time,
      options,
      &(&1 in [:locale, :format, :numeric])
    )
  end
end
