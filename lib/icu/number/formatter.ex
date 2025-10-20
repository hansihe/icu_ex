defmodule Icu.Number.Formatter do
  @moduledoc false

  alias Icu.Nif
  alias Icu.Number
  alias Icu.Formatter.Options

  defstruct [:resource]

  @opaque t :: %__MODULE__{}

  @spec new(Number.options_input()) ::
          {:ok, t()} | {:error, Number.format_error()}
  def new(options \\ []) do
    with {:ok, opts} <- normalize_options(options),
         {:ok, resource} <-
           Nif.number_formatter_new(Map.fetch!(opts, :locale), Map.delete(opts, :locale)) do
      {:ok, %__MODULE__{resource: resource}}
    end
  end

  @spec new!(Number.options_input()) :: t()
  def new!(options \\ []) do
    case new(options) do
      {:ok, formatter} -> formatter
      {:error, reason} -> raise "number formatter creation failed: #{inspect(reason)}"
    end
  end

  @spec format(t(), number()) :: {:ok, String.t()} | {:error, Number.format_error()}
  def format(%__MODULE__{resource: resource}, number) when is_number(number) do
    Nif.number_format(resource, number)
  end

  def format(%__MODULE__{}, _other), do: {:error, :invalid_number}

  @spec format!(t(), number()) :: String.t()
  def format!(%__MODULE__{} = formatter, number) do
    case format(formatter, number) do
      {:ok, result} -> result
      {:error, reason} -> raise "number formatting failed: #{inspect(reason)}"
    end
  end

  @spec format_to_parts(t(), number()) ::
          {:ok, [map()]} | {:error, Number.format_error()}
  def format_to_parts(%__MODULE__{resource: resource}, number) when is_number(number) do
    Nif.number_format_to_parts(resource, number)
  end

  def format_to_parts(%__MODULE__{}, _other), do: {:error, :invalid_number}

  @spec format_to_parts!(t(), number()) :: [map()]
  def format_to_parts!(%__MODULE__{} = formatter, number) do
    case format_to_parts(formatter, number) do
      {:ok, parts} -> parts
      {:error, reason} -> raise "number format to parts failed: #{inspect(reason)}"
    end
  end

  defimpl Inspect do
    def inspect(_formatter, _opts) do
      "#Icu.Number.Formatter<>"
    end
  end

  @doc false
  @spec normalize_options(Number.options_input()) :: {:ok, map()} | {:error, term()}
  def normalize_options(options) do
    Options.normalize_options(
      :number,
      options,
      &(&1 in [
          :grouping,
          :sign_display,
          :minimum_integer_digits,
          :minimum_fraction_digits,
          :maximum_integer_digits,
          :maximum_fraction_digits,
          :locale
        ])
    )
  end
end
