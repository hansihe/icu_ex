defmodule Icu.List.Formatter do
  @moduledoc false

  alias Icu.List
  alias Icu.Nif
  alias Icu.Formatter.Options

  defstruct [:resource]

  @opaque t :: %__MODULE__{}

  @spec new(List.options_input()) ::
          {:ok, t()} | {:error, List.format_error()}
  def new(options \\ []) do
    with {:ok, opts} <- normalize_options(options),
         {:ok, resource} <-
           Nif.list_formatter_new(Map.fetch!(opts, :locale), Map.delete(opts, :locale)) do
      {:ok, %__MODULE__{resource: resource}}
    end
  end

  @spec new!(List.options_input()) :: t()
  def new!(options \\ []) do
    case new(options) do
      {:ok, formatter} -> formatter
      {:error, reason} -> raise "list formatter creation failed: #{inspect(reason)}"
    end
  end

  @spec format(t(), Enumerable.t()) :: {:ok, String.t()} | {:error, List.format_error()}
  def format(%__MODULE__{resource: resource}, values) do
    with {:ok, items} <- collect_items(values) do
      Nif.list_format(resource, items)
    end
  end

  def format(%__MODULE__{}, _other), do: {:error, :invalid_items}

  @spec format!(t(), Enumerable.t()) :: String.t()
  def format!(%__MODULE__{} = formatter, values) do
    case format(formatter, values) do
      {:ok, result} -> result
      {:error, reason} -> raise "list formatting failed: #{inspect(reason)}"
    end
  end

  @spec format_to_parts(t(), Enumerable.t()) ::
          {:ok, [map()]} | {:error, List.format_error()}
  def format_to_parts(%__MODULE__{resource: resource}, values) do
    with {:ok, items} <- collect_items(values) do
      Nif.list_format_to_parts(resource, items)
    end
  end

  def format_to_parts(%__MODULE__{}, _other), do: {:error, :invalid_items}

  @spec format_to_parts!(t(), Enumerable.t()) :: [map()]
  def format_to_parts!(%__MODULE__{} = formatter, values) do
    case format_to_parts(formatter, values) do
      {:ok, parts} -> parts
      {:error, reason} -> raise "list format to parts failed: #{inspect(reason)}"
    end
  end

  defimpl Inspect do
    def inspect(_formatter, _opts), do: "#Icu.List.Formatter<>"
  end

  @doc false
  @spec normalize_options(List.options_input()) :: map()
  def normalize_options(nil), do: %{type: :and, width: :wide}

  def normalize_options(options) when is_list(options) or is_map(options) do
    Options.normalize_options(
      :list,
      options,
      &(&1 in [
          :type,
          :width,
          :locale
        ])
    )
  end

  defp collect_items(values) when is_list(values), do: normalize_items(values)

  defp collect_items(values) do
    case Enumerable.impl_for(values) do
      nil -> {:error, :invalid_items}
      _impl -> values |> Enum.to_list() |> normalize_items()
    end
  rescue
    Protocol.UndefinedError -> {:error, :invalid_items}
  end

  defp normalize_items([]), do: {:error, :invalid_items}

  defp normalize_items(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case to_string_safe(value) do
        {:ok, string} -> {:cont, {:ok, [string | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, _} = error -> error
    end
  end

  defp to_string_safe(value) do
    {:ok, to_string(value)}
  rescue
    Protocol.UndefinedError -> {:error, :invalid_items}
  end
end
