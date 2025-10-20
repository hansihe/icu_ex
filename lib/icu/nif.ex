defmodule Icu.Nif do
  use Rustler,
    otp_app: :icu,
    crate: :icu_nif

  def locale_from_string(_locale_string), do: :erlang.nif_error(:nif_not_loaded)
  def locale_to_string(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def locale_get_components(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def locale_maximize(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def locale_minimize(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def locale_minimize_favor_script(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def locale_fallbacks(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def locale_match_gettext(_resource, _available), do: :erlang.nif_error(:nif_not_loaded)

  # Numbers
  def number_formatter_new(_locale_resource, _options),
    do: :erlang.nif_error(:nif_not_loaded)

  def number_format(_formatter_resource, _number), do: :erlang.nif_error(:nif_not_loaded)

  def number_format_to_parts(_formatter_resource, _number),
    do: :erlang.nif_error(:nif_not_loaded)

  # Lists
  def list_formatter_new(_locale_resource, _options), do: :erlang.nif_error(:nif_not_loaded)
  def list_format(_formatter_resource, _items), do: :erlang.nif_error(:nif_not_loaded)

  def list_format_to_parts(_formatter_resource, _items),
    do: :erlang.nif_error(:nif_not_loaded)

  # Display names
  def display_names_formatter_new(_locale_resource, _kind, _options),
    do: :erlang.nif_error(:nif_not_loaded)

  def display_names_of(_formatter_resource, _value),
    do: :erlang.nif_error(:nif_not_loaded)

  # Temporals
  def temporal_formatter_new(_locale_resource, _options),
    do: :erlang.nif_error(:nif_not_loaded)

  def temporal_format(_formatter_resource, _datetime_map),
    do: :erlang.nif_error(:nif_not_loaded)

  def temporal_format_to_parts(_formatter_resource, _datetime_map),
    do: :erlang.nif_error(:nif_not_loaded)

  def time_zone_from_string(_identifier), do: :erlang.nif_error(:nif_not_loaded)
  def time_zone_from_offset(_offset_minutes), do: :erlang.nif_error(:nif_not_loaded)

  def relative_time_formatter_new(_locale_resource, _options),
    do: :erlang.nif_error(:nif_not_loaded)

  def relative_time_format(_formatter_resource, _value, _unit),
    do: :erlang.nif_error(:nif_not_loaded)

  def relative_time_format_to_parts(_formatter_resource, _value, _unit),
    do: :erlang.nif_error(:nif_not_loaded)
end
