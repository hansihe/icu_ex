defmodule Icu.DisplayNames.Formatter do
  @moduledoc false

  alias Icu.DisplayNames
  alias Icu.Formatter.Options
  alias Icu.LanguageTag
  alias Icu.Nif

  @valid_kinds [:locale, :language, :region, :script, :variant]

  defstruct [:resource, :kind]

  @opaque t :: %__MODULE__{
            resource: reference(),
            kind: DisplayNames.kind()
          }

  @doc """
  Creates a new formatter for the requested display name `kind`.
  """
  @spec new(DisplayNames.kind(), DisplayNames.options_input()) ::
          {:ok, t()}
          | {:invalid_kind, term()}
          | Options.error()
          | {:error, :invalid_locale}
          | {:error, :invalid_options}
  def new(kind, options \\ [])

  def new(kind, _options) when kind not in @valid_kinds do
    {:invalid_kind, kind}
  end

  def new(kind, options) do
    with {:ok, opts} <- normalize_options(options),
         {:ok, resource} <-
           Nif.display_names_formatter_new(
             Map.fetch!(opts, :locale),
             kind,
             Map.delete(opts, :locale)
           ) do
      {:ok, %__MODULE__{resource: resource, kind: kind}}
    end
  end

  @doc """
  Returns the display name of the provided `value`.
  """
  @spec display_name(t(), term()) ::
          {:ok, String.t() | nil}
          | {:error, :invalid_locale}
          | {:error, :invalid_options}
  def display_name(%__MODULE__{kind: kind, resource: resource}, value) do
    with {:ok, normalized} <- normalize_value(kind, value) do
      Nif.display_names_of(resource, normalized)
    end
  end

  @doc """
  Returns the display name, raising on error.
  """
  @spec display_name!(t(), term()) :: String.t() | nil
  def display_name!(%__MODULE__{} = formatter, value) do
    case display_name(formatter, value) do
      {:ok, result} ->
        result

      {:error, reason} ->
        raise "display names lookup failed: #{inspect(reason)}"
    end
  end

  defimpl Inspect do
    def inspect(%Icu.DisplayNames.Formatter{kind: kind}, _opts) do
      "#Icu.DisplayNames.Formatter<#{kind}>"
    end
  end

  @doc false
  @spec normalize_options(DisplayNames.options_input()) ::
          {:ok, map()} | Options.error()
  def normalize_options(nil), do: normalize_options(%{})

  def normalize_options(options) when is_list(options) or is_map(options) do
    Options.normalize_options(
      :display_names,
      options,
      &(&1 in [:style, :fallback, :language_display, :locale])
    )
  end

  def normalize_options(_other), do: {:error, :invalid_options}

  defp normalize_value(:locale, %LanguageTag{resource: resource}) do
    {:ok, resource}
  end

  defp normalize_value(_kind, value) when is_binary(value) do
    {:ok, value}
  end

  defp normalize_value(_kind, value) when is_atom(value) do
    {:ok, value}
  end

  defp normalize_value(:locale, _value), do: {:error, :invalid_value}
end
