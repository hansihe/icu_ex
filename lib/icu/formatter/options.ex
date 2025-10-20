defmodule Icu.Formatter.Options do
  @moduledoc false

  alias Icu.Calendar
  alias Icu.HourCycle
  alias Icu.LanguageTag

  @type area :: :temporal | :number | :list | :display_names
  @type accept_fun :: (atom() -> boolean())
  @type options_input :: map() | keyword()
  @type error ::
          {:error, :invalid_options}
          | {:error, {:bad_option, atom()}}
          | {:error, {:invalid_option_value, atom(), term()}}

  @spec normalize_options(atom(), options_input(), accept_fun()) ::
          {:ok, map()} | error()
  def normalize_options(area, options, accepts_key) when is_map(options) or is_list(options) do
    options
    |> Enum.reduce_while({:ok, %{}}, fn
      {key, nil}, {:ok, acc} ->
        {:cont, {:ok, Map.delete(acc, key)}}

      {key, value}, {:ok, acc} ->
        if accepts_key.(key) do
          case normalize_option(area, key, value) do
            {:ok, normalized} ->
              {:cont, {:ok, Map.put(acc, key, normalized)}}

            {:error, _} ->
              {:halt, {:error, {:invalid_option_value, key}}}

            :error ->
              {:halt, {:error, {:invalid_option_value, key}}}
          end
        else
          {:halt, {:error, {:bad_option, key}}}
        end
    end)
    |> ensure_locale_option()
  end

  def normalize_options(_area, _other, _accepts_key), do: {:error, :invalid_options}

  def ensure_locale_option({:ok, %{locale: locale} = options}) do
    {:ok, Map.put(options, :locale, locale.resource)}
  end

  def ensure_locale_option({:ok, options}) do
    {:ok, Map.put(options, :locale, Icu.get_locale().resource)}
  end

  def ensure_locale_option({:error, _} = error) do
    error
  end

  def normalize_option(_area, :locale, %LanguageTag{} = tag), do: {:ok, tag}

  def normalize_option(_area, :locale, value) when is_binary(value) do
    LanguageTag.parse(value)
  end

  def normalize_option(_area, :locale, nil) do
    Icu.get_locale()
  end

  def normalize_option(_areal, :calendar, value) do
    case Calendar.normalize_identifier(value) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> :error
    end
  end

  def normalize_option(_area, :hour_cycle, value) do
    case HourCycle.normalize(value) do
      nil -> :error
      normalized -> {:ok, normalized}
    end
  end

  def normalize_option(_area, :date_length, value) when value in [:short, :medium, :long, :full],
    do: {:ok, value}

  def normalize_option(_area, :time_length, value) when value in [:short, :medium, :long, :full],
    do: {:ok, value}

  def normalize_option(_area, :time_zone_format, value)
      when value in [:generic, :specific, :iso8601],
      do: {:ok, value}

  def normalize_option(_area, :unit, value)
      when value in [:second, :minute, :hour, :day, :week, :month, :quarter, :year],
      do: {:ok, value}

  def normalize_option(_area, :format, value) when value in [:wide, :short, :narrow],
    do: {:ok, value}

  def normalize_option(_area, :numeric, value) when value in [:always, :auto], do: {:ok, value}

  def normalize_option(_area, :length, value) when value in [:long, :medium, :short],
    do: {:ok, value}

  def normalize_option(_area, :date_fields, value)
      when value in [:d, :md, :ymd, :de, :mde, :ymde, :e, :m, :ym, :y],
      do: {:ok, value}

  def normalize_option(_area, :time_precision, {:subsecond, digits})
      when is_integer(digits) and digits >= 1 and digits <= 9,
      do: {:ok, {:subsecond, digits}}

  def normalize_option(:temporal, :time_precision, value)
      when value in [:hour, :minute, :second, :minute_optional],
      do: {:ok, value}

  def normalize_option(:temporal, :zone_style, value)
      when value in [
             :specific_long,
             :specific_short,
             :localized_offset_long,
             :localized_offset_short,
             :generic_long,
             :generic_short,
             :location,
             :exemplar_city
           ],
      do: {:ok, value}

  def normalize_option(:temporal, :alignment, value) when value in [:auto, :column],
    do: {:ok, value}

  def normalize_option(:temporal, :year_style, value) when value in [:auto, :full, :with_era],
    do: {:ok, value}

  # Number
  def normalize_option(:number, :grouping, value)
      when value in [:auto, :always, :min2, :never] do
    {:ok, value}
  end

  def normalize_option(:number, :sign_display, value)
      when value in [:auto, :always, :never, :except_zero, :negative] do
    {:ok, value}
  end

  def normalize_option(:number, :minimum_integer_digits, value)
      when is_integer(value) and value > 0 do
    {:ok, value}
  end

  def normalize_option(:number, :minimum_fraction_digits, value)
      when is_integer(value) and value >= 0 do
    {:ok, value}
  end

  def normalize_option(:number, :maximum_integer_digits, value)
      when is_integer(value) and value > 0 do
    {:ok, value}
  end

  def normalize_option(:number, :maximum_fraction_digits, value)
      when is_integer(value) and value >= 0 do
    {:ok, value}
  end

  # List
  def normalize_option(:list, :type, value) when value in [:and, :or, :unit], do: {:ok, value}

  def normalize_option(:list, :width, value) when value in [:wide, :short, :narrow],
    do: {:ok, value}

  # Display names
  def normalize_option(:display_names, :style, value)
      when value in [:narrow, :short, :long, :menu],
      do: {:ok, value}

  def normalize_option(:display_names, :fallback, value) when value in [:code, :none],
    do: {:ok, value}

  def normalize_option(:display_names, :language_display, value)
      when value in [:dialect, :standard],
      do: {:ok, value}

  def normalize_option(_area, _key, _value), do: :error
end
