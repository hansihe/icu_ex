defmodule Icu.Nif do
  @doc false

  mix_config = Mix.Project.config()
  version = mix_config[:version]
  github_url = mix_config[:package][:links]["GitHub"]

  # Since Rustler 0.27.0, we need to change manually the mode for each env.
  # We want "debug" in dev and test because it's faster to compile.
  mode = if Mix.env() in [:dev, :test], do: :debug, else: :release

  cwd = File.cwd!()
  System.put_env("ICU4X_DATA_DIR", cwd <> "/data")

  use RustlerPrecompiled,
    otp_app: :icu,
    crate: :icu_nif,
    version: version,
    base_url: "#{github_url}/releases/download/v#{version}",
    targets: ~w(
      aarch64-apple-darwin
      aarch64-unknown-linux-gnu
      aarch64-unknown-linux-musl
      x86_64-apple-darwin
      x86_64-pc-windows-msvc
      x86_64-pc-windows-gnu
      x86_64-unknown-linux-gnu
      x86_64-unknown-linux-musl
      x86_64-unknown-freebsd
    ),
    # We don't use any features of newer NIF versions, so 2.15 is enough.
    nif_versions: ["2.15"],
    mode: mode,
    force_build: System.get_env("ICU_BUILD") in ["1", "true"]

  # use Rustler,
  #   otp_app: :icu,
  #   crate: :icu_nif

  def locale_from_string(_locale_string), do: :erlang.nif_error(:nif_not_loaded)
  def locale_to_string(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def locale_get_components(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def locale_maximize(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def locale_minimize(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def locale_minimize_favor_script(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def locale_fallbacks(_resource), do: :erlang.nif_error(:nif_not_loaded)
  def locale_match_gettext(_resource, _available), do: :erlang.nif_error(:nif_not_loaded)
  def locale_set_hour_cycle(_resource, _hour_cycle), do: :erlang.nif_error(:nif_not_loaded)
  def locale_get_hour_cycle(_resource), do: :erlang.nif_error(:nif_not_loaded)

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

  # Currency
  def currency_fractions(_currency), do: :erlang.nif_error(:nif_not_loaded)

  def currency_formatter_new(_locale_resource, _currency_code, _options),
    do: :erlang.nif_error(:nif_not_loaded)

  def currency_format(_formatter_resource, _number),
    do: :erlang.nif_error(:nif_not_loaded)
end
