defmodule Icu.Calendar do
  @moduledoc false

  @known_atoms [:gregorian, :buddhist, :japanese]

  @doc """
  Normalizes calendar identifiers into a format understood by the NIF layer.
  """
  @spec normalize_identifier(term()) ::
          {:ok, atom() | String.t()} | {:error, :unsupported_calendar}
  def normalize_identifier(nil), do: {:ok, :gregorian}

  def normalize_identifier(value) when value in @known_atoms, do: {:ok, value}

  def normalize_identifier(Calendar.ISO), do: {:ok, :gregorian}

  def normalize_identifier(value) when is_atom(value) do
    if module?(value) do
      normalize_module(value)
    else
      {:ok, value}
    end
  end

  def normalize_identifier(value) when is_binary(value), do: {:ok, value}

  def normalize_identifier(_other), do: {:error, :unsupported_calendar}

  defp module?(module) when is_atom(module) do
    function_exported?(module, :__info__, 1)
  rescue
    _ -> false
  end

  defp normalize_module(module) do
    cond do
      module == Calendar.ISO ->
        {:ok, :gregorian}

      function_exported?(module, :calendar_type, 0) ->
        value = module.calendar_type()
        validate_calendar_identifier(value)

      function_exported?(module, :cldr_calendar_type, 0) ->
        value = module.cldr_calendar_type()
        validate_calendar_identifier(value)

      true ->
        {:ok, Module.split(module) |> Enum.join(".")}
    end
  rescue
    _ -> {:error, :unsupported_calendar}
  end

  defp validate_calendar_identifier(value) when is_atom(value) or is_binary(value),
    do: {:ok, value}

  defp validate_calendar_identifier(_), do: {:error, :unsupported_calendar}
end
