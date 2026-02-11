defmodule Icu.Experimental.Currency.Formatter do
  @moduledoc false

  alias Icu.Nif
  alias Icu.Formatter.Options

  defstruct [:resource]

  @opaque t :: %__MODULE__{}

  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(options \\ []) do
    with {:ok, opts} <- normalize_options(options) do
      currency = Map.fetch!(opts, :currency)
      locale = Map.fetch!(opts, :locale)
      nif_opts = opts |> Map.delete(:currency) |> Map.delete(:locale)

      case Nif.currency_formatter_new(locale, currency, nif_opts) do
        {:ok, resource} -> {:ok, %__MODULE__{resource: resource}}
        {:error, _} = error -> error
      end
    end
  end

  @spec new!(keyword()) :: t()
  def new!(options \\ []) do
    case new(options) do
      {:ok, formatter} -> formatter
      {:error, reason} -> raise "currency formatter creation failed: #{inspect(reason)}"
    end
  end

  @spec format(t(), number() | struct()) :: {:ok, String.t()} | {:error, term()}
  def format(%__MODULE__{resource: resource}, number) when is_number(number) or is_struct(number) do
    Nif.currency_format(resource, number)
  end

  def format(%__MODULE__{}, _other), do: {:error, :invalid_number}

  @spec format!(t(), number()) :: String.t()
  def format!(%__MODULE__{} = formatter, number) do
    case format(formatter, number) do
      {:ok, result} -> result
      {:error, reason} -> raise "currency formatting failed: #{inspect(reason)}"
    end
  end

  defimpl Inspect do
    def inspect(_formatter, _opts) do
      "#Icu.Currency.Formatter<>"
    end
  end

  @rounding_keys [:currency_digits, :rounding_mode]

  @doc false
  @spec normalize_options(keyword() | map()) :: {:ok, map()} | {:error, term()}
  def normalize_options(options) do
    Options.normalize_options(
      :currency,
      options,
      &(&1 in [:locale, :currency, :width, :currency_digits, :rounding_mode])
    )
    |> validate_currency_required()
  end

  @doc false
  @spec split_rounding_opts(map()) :: {map(), map()}
  def split_rounding_opts(opts) do
    {rounding, rest} = Map.split(opts, @rounding_keys)
    {rest, rounding}
  end

  defp validate_currency_required({:ok, %{currency: _} = opts}), do: {:ok, opts}
  defp validate_currency_required({:ok, _}), do: {:error, {:missing_option, :currency}}
  defp validate_currency_required(error), do: error
end
