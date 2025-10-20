defmodule Icu.HourCycle do
  @moduledoc false

  @valid_cycles [:h11, :h12, :h23, :h24]

  @doc """
  Normalizes hour cycle identifiers into atoms expected by the NIF layer.
  """
  @spec normalize(term()) :: atom() | nil
  def normalize(nil), do: nil
  def normalize(value) when value in @valid_cycles, do: value

  def normalize(value) when is_binary(value) do
    case String.downcase(value) do
      "h11" -> :h11
      "h12" -> :h12
      "h23" -> :h23
      "h24" -> :h24
      _ -> nil
    end
  end

  def normalize(_other), do: nil
end
