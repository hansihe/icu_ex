defmodule Icu.LanguageTag do
  @moduledoc """
  Represents a locale parsed via ICU4X.

  Language tags wrap a NIF resource. Use the provided parsing functions to
  construct values and avoid manipulating the resource directly.
  """

  alias Icu.LanguageTag.Components
  alias Icu.Nif
  import Kernel, except: [to_string: 1]

  defstruct [:resource]

  @opaque t :: %__MODULE__{}

  @type parsable :: t() | String.t()

  @type parse_error :: {:error, :invalid_locale}

  @doc """
  Parses a locale string and returns a language tag resource.
  """
  @spec parse(String.t() | t()) :: {:ok, t()} | parse_error()
  def parse(locale_string) when is_binary(locale_string) do
    case Nif.locale_from_string(locale_string) do
      {:ok, resource} -> {:ok, %__MODULE__{resource: resource}}
      {:error, _} = error -> error
    end
  end

  def parse(language_tag = %__MODULE__{}) do
    {:ok, language_tag}
  end

  def parse(_language_tag) do
    {:error, :invalid_locale}
  end

  @doc """
  Parses a locale string and raises on error.
  """
  @spec parse!(String.t() | t()) :: t()
  def parse!(locale_string) do
    case parse(locale_string) do
      {:ok, tag} ->
        tag

      {:error, reason} ->
        raise ArgumentError, "invalid locale #{inspect(locale_string)}: #{inspect(reason)}"
    end
  end

  @doc """
  Converts a language tag resource back to its canonical string representation.
  """
  @spec to_string(t()) :: {:ok, String.t()} | {:error, :invalid_resource}
  def to_string(%__MODULE__{resource: resource}) do
    Nif.locale_to_string(resource)
  end

  @doc """
  Converts a language tag resource to string and raises on error.
  """
  @spec to_string!(t()) :: String.t()
  def to_string!(%__MODULE__{} = locale) do
    case to_string(locale) do
      {:ok, value} -> value
      {:error, reason} -> raise "failed to convert locale to string: #{inspect(reason)}"
    end
  end

  @doc """
  Returns the parsed components of a language tag.
  """
  @spec components(t()) :: {:ok, Components.t()} | {:error, :invalid_resource}
  def components(%__MODULE__{resource: resource}) do
    Nif.locale_get_components(resource)
  end

  @doc """
  Returns the parsed components and raises on error.
  """
  @spec components!(t()) :: Components.t()
  def components!(%__MODULE__{} = locale) do
    case components(locale) do
      {:ok, components} -> components
      {:error, reason} -> raise "failed to fetch language tag components: #{inspect(reason)}"
    end
  end

  @doc """
  The maximize method potentially updates a passed in locale in place
  depending up the results of running the ‘Add Likely Subtags’ algorithm
  from https://www.unicode.org/reports/tr35/#Likely_Subtags.

  This function does not guarantee that any particular set of subtags will
  be present in the resulting locale.
  """
  @spec maximize(t()) :: {:modified, t()} | {:unmodified, t()}
  def maximize(%__MODULE__{resource: resource}) do
    {marker, res} = Nif.locale_maximize(resource)
    {marker, %__MODULE__{
      resource: res
    }}
  end

  @doc """
  This returns a new Locale that is the result of running the
  ‘Remove Likely Subtags’ algorithm from
  https://www.unicode.org/reports/tr35/#Likely_Subtags.
  """
  @spec minimize(t()) :: {:modified, t()} | {:unmodified, t()}
  def minimize(%__MODULE__{resource: resource}) do
    {marker, res} = Nif.locale_minimize(resource)
    {marker, %__MODULE__{
      resource: res
    }}
  end

  @doc """
  This returns a new Locale that is the result of running the
  'Remove Likely Subtags, favoring script' algorithm from
  https://www.unicode.org/reports/tr35/#Likely_Subtags.
  """
  @spec minimize_favor_script(t()) :: {:modified, t()} | {:unmodified, t()}
  def minimize_favor_script(%__MODULE__{resource: resource}) do
    {marker, res} = Nif.locale_minimize_favor_script(resource)
    {marker, %__MODULE__{
      resource: res
    }}
  end

  @typedoc "Hour cycle preference for time formatting."
  @type hour_cycle :: :h11 | :h12 | :h23

  @doc """
  Sets the hour cycle preference on a language tag.

  Returns a new language tag with the hour cycle Unicode extension (`-u-hc-`) set.

  ## Hour Cycles

  - `:h11` – Hour system using 0-11 (noon = 0, midnight = 0)
  - `:h12` – Hour system using 1-12 (noon = 12, midnight = 12)
  - `:h23` – Hour system using 0-23 (noon = 12, midnight = 0)

  ## Examples

      iex> {:ok, tag} = Icu.LanguageTag.parse("en-US")
      iex> {:ok, tag_with_hc} = Icu.LanguageTag.set_hour_cycle(tag, :h23)
      iex> Icu.LanguageTag.to_string!(tag_with_hc)
      "en-US-u-hc-h23"

  """
  @spec set_hour_cycle(t(), hour_cycle()) :: {:ok, t()} | {:error, :invalid_options}
  def set_hour_cycle(%__MODULE__{resource: resource}, hour_cycle)
      when hour_cycle in [:h11, :h12, :h23] do
    case Nif.locale_set_hour_cycle(resource, hour_cycle) do
      {:ok, new_resource} -> {:ok, %__MODULE__{resource: new_resource}}
      {:error, _} = error -> error
    end
  end

  def set_hour_cycle(%__MODULE__{}, _hour_cycle) do
    {:error, :invalid_options}
  end

  @doc """
  Sets the hour cycle preference and raises on error.

  ## Examples

      iex> tag = Icu.LanguageTag.parse!("en-US")
      iex> tag_with_hc = Icu.LanguageTag.set_hour_cycle!(tag, :h23)
      iex> Icu.LanguageTag.to_string!(tag_with_hc)
      "en-US-u-hc-h23"

  """
  @spec set_hour_cycle!(t(), hour_cycle()) :: t()
  def set_hour_cycle!(%__MODULE__{} = tag, hour_cycle) do
    case set_hour_cycle(tag, hour_cycle) do
      {:ok, new_tag} -> new_tag
      {:error, reason} -> raise ArgumentError, "failed to set hour cycle: #{inspect(reason)}"
    end
  end

  @doc """
  Gets the hour cycle preference from a language tag.

  Returns `{:ok, hour_cycle}` if the tag has an hour cycle extension set,
  or `{:ok, nil}` if no hour cycle is specified.

  ## Examples

      iex> {:ok, tag} = Icu.LanguageTag.parse("en-US-u-hc-h23")
      iex> Icu.LanguageTag.get_hour_cycle(tag)
      {:ok, :h23}

      iex> {:ok, tag} = Icu.LanguageTag.parse("en-US")
      iex> Icu.LanguageTag.get_hour_cycle(tag)
      {:ok, nil}

  """
  @spec get_hour_cycle(t()) :: {:ok, hour_cycle() | nil} | {:error, :invalid_resource}
  def get_hour_cycle(%__MODULE__{resource: resource}) do
    Nif.locale_get_hour_cycle(resource)
  end

  @doc """
  Gets the hour cycle preference and raises on error.

  ## Examples

      iex> tag = Icu.LanguageTag.parse!("en-US-u-hc-h12")
      iex> Icu.LanguageTag.get_hour_cycle!(tag)
      :h12

  """
  @spec get_hour_cycle!(t()) :: hour_cycle() | nil
  def get_hour_cycle!(%__MODULE__{} = tag) do
    case get_hour_cycle(tag) do
      {:ok, hour_cycle} -> hour_cycle
      {:error, reason} -> raise "failed to get hour cycle: #{inspect(reason)}"
    end
  end

  @doc """
  Returns the full list of fallback locales for the given locale.
  "lookup" according to RFC4647.
  """
  @spec fallbacks(t()) :: {:ok, [t()]}
  def fallbacks(%__MODULE__{resource: resource}) do
    {:ok, fallbacks} = Nif.locale_fallbacks(resource)
    {:ok, Enum.map(fallbacks, &%__MODULE__{resource: &1})}
  end

  @doc """
  Attempts to match the given `LanguageTag.t()` against a list of
  gettext locales.

  Uses "lookup" according to RFC4647.

  Accepts both `_` and `-` as separators in `gettext_locales`.
  """
  @spec match_gettext(t(), [String.t()]) :: {:ok, String.t()} | {:error, :no_match}
  def match_gettext(%__MODULE__{resource: resource}, gettext_locales) do
    Nif.locale_match_gettext(resource, gettext_locales)
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%Icu.LanguageTag{} = locale, _opts) do
      case Icu.LanguageTag.to_string(locale) do
        {:ok, string} -> concat(["#Icu.LanguageTag<", string, ">"])
        {:error, _reason} -> "#Icu.LanguageTag<invalid>"
      end
    end
  end
end
