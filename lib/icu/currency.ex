defmodule Icu.Currency do

  @type currency :: String.t()

  @type fractions :: %{
    :digits => non_neg_integer(),
    :rounding => non_neg_integer(),
    :cash_digits => non_neg_integer(),
    :cash_rounding => non_neg_integer(),
  }

  @spec currency_fractions(currency()) :: {:ok, fractions()} | {:error, :invalid_currency}
  def currency_fractions(currency) do
    Icu.Nif.currency_fractions(currency)
  end

end
