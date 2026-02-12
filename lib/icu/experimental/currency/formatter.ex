defmodule Icu.Experimental.Currency.Formatter do
  @moduledoc false

  alias Icu.Nif
  alias Icu.Formatter.Options

  # Rounding options are stored in the struct because ICU4X doesn't currently
  # accept rounding config at formatter creation or format time. We apply
  # Elixir-side rounding before passing the value to the NIF. If ICU4X gains
  # rounding support, these fields can be forwarded to the NIF instead.
  defstruct [:resource, :currency, :currency_digits, :rounding_mode]

  @opaque t :: %__MODULE__{}

  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(options \\ []) do
    with {:ok, opts} <- normalize_options(options) do
      {nif_opts, rounding_opts} = split_rounding_opts(opts)
      currency = Map.fetch!(nif_opts, :currency)
      locale = Map.fetch!(nif_opts, :locale)
      rest = nif_opts |> Map.delete(:currency) |> Map.delete(:locale)

      case Nif.currency_formatter_new(locale, currency, rest) do
        {:ok, resource} ->
          {:ok,
           %__MODULE__{
             resource: resource,
             currency: currency,
             currency_digits: Map.get(rounding_opts, :currency_digits, :iso),
             rounding_mode: Map.get(rounding_opts, :rounding_mode, :half_even)
           }}

        {:error, _} = error ->
          error
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
  def format(%__MODULE__{} = formatter, number) when is_number(number) or is_struct(number) do
    with {:ok, rounded} <-
           round(number,
             currency: formatter.currency,
             currency_digits: formatter.currency_digits,
             rounding_mode: formatter.rounding_mode
           ) do
      Nif.currency_format(formatter.resource, rounded)
    end
  end

  def format(%__MODULE__{}, _other), do: {:error, :invalid_number}

  @spec format!(t(), number()) :: String.t()
  def format!(%__MODULE__{} = formatter, number) do
    case format(formatter, number) do
      {:ok, result} -> result
      {:error, reason} -> raise "currency formatting failed: #{inspect(reason)}"
    end
  end

  @spec round(number() | Decimal.t(), keyword() | map()) ::
          {:ok, Decimal.t()} | {:error, term()}
  def round(number, options) do
    opts = if is_list(options), do: Map.new(options), else: options
    currency = opts[:currency]
    digits_opt = Map.get(opts, :currency_digits, :iso)
    mode = Map.get(opts, :rounding_mode, :half_even)

    with {:ok, _} <- validate_number(number),
         {:ok, fractions} <- Nif.currency_fractions(currency),
         {:ok, {digits, increment}} <- resolve_digits(digits_opt, fractions) do
      decimal = to_decimal(number)
      {:ok, apply_rounding(decimal, digits, increment, mode)}
    end
  end

  @spec round!(number() | Decimal.t(), keyword() | map()) :: Decimal.t()
  def round!(number, options) do
    case __MODULE__.round(number, options) do
      {:ok, result} -> result
      {:error, reason} -> raise "currency rounding failed: #{inspect(reason)}"
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

  defp validate_number(%Decimal{coef: coef}) when coef in [:NaN, :inf],
    do: {:error, :invalid_number}

  defp validate_number(%Decimal{}), do: {:ok, :valid}
  defp validate_number(n) when is_number(n), do: {:ok, :valid}
  defp validate_number(_), do: {:error, :invalid_number}

  defp to_decimal(%Decimal{} = d), do: d
  # Since we strictly do formatting in this API, we allow floats
  # which are not normally fit for purpose for currencies.
  defp to_decimal(n) when is_float(n), do: Decimal.from_float(n)
  defp to_decimal(n), do: Decimal.new(n)

  defp resolve_digits(:iso, %{digits: digits, rounding: rounding}),
    do: {:ok, {digits, rounding}}

  defp resolve_digits(:cash, %{cash_digits: digits, cash_rounding: rounding}),
    do: {:ok, {digits, rounding}}

  defp resolve_digits(:cash, _fractions),
    do: {:error, :no_cash_rounding}

  defp resolve_digits(n, _fractions) when is_integer(n) and n >= 0,
    do: {:ok, {n, 0}}

  defp resolve_digits(_, _),
    do: {:error, :invalid_currency_digits}

  defp apply_rounding(decimal, digits, increment, mode) when increment > 0 do
    # e.g. CHF cash: digits=2, cash_rounding=5 → increment_d = 0.05
    increment_d = Decimal.div(Decimal.new(increment), pow10(digits))

    decimal
    |> Decimal.div(increment_d)
    |> Decimal.round(0, mode)
    |> Decimal.mult(increment_d)
    |> normalize_scale(digits)
  end

  defp apply_rounding(decimal, digits, _increment, mode) do
    Decimal.round(decimal, digits, mode)
  end

  defp pow10(0), do: Decimal.new(1)
  defp pow10(n), do: Decimal.new(Integer.pow(10, n))

  defp normalize_scale(decimal, digits) do
    Decimal.round(decimal, digits)
  end
end
