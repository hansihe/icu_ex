defmodule Icu.Temporal.Formatter do
  @moduledoc false

  alias Icu.Calendar
  alias Icu.Formatter.Options
  alias Icu.Nif
  alias Icu.Temporal

  defstruct [:resource]

  @opaque t :: %__MODULE__{}

  @spec new(Temporal.options_input()) ::
          {:ok, t()} | {:error, Temporal.format_error()}
  def new(options \\ []) do
    with {:ok, opts} <- normalize_options(options) do
      case Nif.temporal_formatter_new(Map.fetch!(opts, :locale), Map.delete(opts, :locale)) do
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

  @spec new!(Temporal.options_input()) :: t()
  def new!(options \\ []) do
    case new(options) do
      {:ok, formatter} -> formatter
      {:error, reason} -> raise "temporal formatter creation failed: #{inspect(reason)}"
    end
  end

  @spec format(t(), Temporal.native_input()) ::
          {:ok, String.t()} | {:error, Temporal.format_error()}
  def format(%__MODULE__{resource: resource}, input) do
    with {:ok, temporal_map} <- normalize_input(input) do
      Nif.temporal_format(resource, temporal_map)
    end
  end

  @spec format!(t(), Temporal.native_input()) :: String.t()
  def format!(%__MODULE__{} = formatter, input) do
    case format(formatter, input) do
      {:ok, result} -> result
      {:error, reason} -> raise "temporal formatting failed: #{inspect(reason)}"
    end
  end

  @spec format_to_parts(t(), Temporal.native_input()) ::
          {:ok, [map()]} | {:error, Temporal.format_error()}
  def format_to_parts(%__MODULE__{resource: resource}, input) do
    with {:ok, temporal_map} <- normalize_input(input) do
      Nif.temporal_format_to_parts(resource, temporal_map)
    end
  end

  @spec format_to_parts!(t(), Temporal.native_input()) :: [map()]
  def format_to_parts!(%__MODULE__{} = formatter, input) do
    case format_to_parts(formatter, input) do
      {:ok, parts} -> parts
      {:error, reason} -> raise "temporal formatting failed: #{inspect(reason)}"
    end
  end

  defimpl Inspect do
    def inspect(_formatter, _opts) do
      "#Icu.Temporal.Formatter<>"
    end
  end

  @doc false
  @spec normalize_input(Temporal.native_input()) ::
          {:ok, map()} | {:error, Temporal.format_error()}
  def normalize_input(%Date{} = date) do
    %Elixir.Date{year: year, month: month, day: day, calendar: calendar} = date

    with {:ok, calendar_identifier} <- Calendar.normalize_identifier(calendar) do
      {:ok,
       %{
         year: year,
         month: month,
         day: day,
         calendar: calendar_identifier
       }}
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :unsupported_calendar}
  end

  def normalize_input(%Time{} = time) do
    {:ok, Map.delete(time, :__struct__)}
  end

  def normalize_input(%NaiveDateTime{} = datetime) do
    with {:ok, calendar_identifier} <- Calendar.normalize_identifier(datetime.calendar) do
      value =
        datetime
        |> Map.delete(:__struct__)
        |> Map.put(:calendar_identifier, calendar_identifier)

      {:ok, value}
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :unsupported_calendar}
  end

  def normalize_input(%DateTime{} = datetime) do
    with {:ok, calendar_identifier} <- Calendar.normalize_identifier(datetime.calendar) do
      value =
        datetime
        |> Map.delete(:__struct__)
        |> Map.put(:calendar_identifier, calendar_identifier)

      {:ok, value}
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    _ -> {:error, :unsupported_calendar}
  end

  def normalize_input(_), do: {:error, :invalid_temporal}

  @doc false
  @spec normalize_options(Temporal.options_input()) :: {:ok, map()} | Options.error()
  def normalize_options(options) do
    Options.normalize_options(
      :temporal,
      options,
      &(&1 in [
          :length,
          :date_fields,
          :time_precision,
          :zone_style,
          :alignment,
          :year_style,
          :locale
        ])
    )
  end
end
