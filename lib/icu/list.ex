defmodule Icu.List do
  @moduledoc """
  Locale-aware conjunctions for enumerables.

  `format/2` wraps the ICU4X list formatter so you can turn Elixir enumerables
  into natural-language lists using the application locale (configurable via
  `:icu, :default_locale`). Reach for `Icu.List.Formatter.new/1` whenever you
  need to reuse the same locale or style across multiple calls.

  ## Examples

      iex> Icu.List.format(["Foo", "Bar"])
      {:ok, "Foo and Bar"}

      iex> Icu.List.format(["Uno", "Dos", "Tres"], locale: "es")
      {:ok, "Uno, Dos y Tres"}

  ## Options

  - `:type` – conjunction style to use (`:and`, `:or`, or `:unit`).
  - `:width` – textual width (`:wide`, `:short`, or `:narrow`) that trades context for brevity.
  - `:locale` – override the locale used for formatting; defaults to the application locale.
  """

  alias Icu.LanguageTag
  alias Icu.List.Formatter

  @typedoc "Opaque reference to an ICU4X list formatter."
  @type formatter :: Formatter.t()

  @typedoc "Controls the conjunction type applied between list items."
  @type type :: :and | :or | :unit

  @typedoc "Controls the stylistic width of conjunctions."
  @type width :: :wide | :short | :narrow

  @typedoc "Keyword form of the supported options."
  @type options_list ::
          [
            {:type, type()}
            | {:width, width()}
            | {:locale, LanguageTag.t() | nil}
          ]

  @typedoc "Map form of the supported options."
  @type options ::
          %{
            optional(:type) => type(),
            optional(:width) => width(),
            optional(:locale) => LanguageTag.t() | nil
          }

  @type options_input :: options() | options_list() | nil

  @type format_error ::
          :invalid_formatter
          | :invalid_locale
          | :invalid_options
          | :invalid_items

  @doc """
  Formats an enumerable of values.

  Returns `{:ok, String.t()}` on success or an error tuple when the input cannot
  be coerced into a non-empty list.

  ## Examples

      iex> Icu.List.format(["Foo", "Bar"])
      {:ok, "Foo and Bar"}

      iex> Icu.List.format(1..3, type: :or)
      {:ok, "1, 2, or 3"}
  """
  @spec format(Enumerable.t(), options_input()) ::
          {:ok, String.t()} | {:error, format_error()}
  def format(values, options \\ []) do
    with {:ok, formatter} <- Formatter.new(options) do
      Formatter.format(formatter, values)
    end
  end

  @doc """
  Convenience helper that raises on error.

  ## Examples

      iex> Icu.List.format!(["Foo", "Bar", "Baz"])
      "Foo, Bar, and Baz"
  """
  @spec format!(Enumerable.t(), options_input()) :: String.t()
  def format!(values, options \\ []) do
    case format(values, options) do
      {:ok, result} -> result
      {:error, reason} -> raise "list formatting failed: #{inspect(reason)}"
    end
  end

  @doc """
  Formats values into discrete parts.

  Returns each literal and element as a tagged map so the caller can apply
  custom rendering (for example when interleaving HTML tags).

  ## Examples

      iex> {:ok, parts} = Icu.List.format_to_parts(["A", "B", "C"])
      iex> Enum.map(parts, & &1.part_type)
      [:element, :literal, :element, :literal, :element]
  """
  @spec format_to_parts(Enumerable.t(), options_input()) ::
          {:ok, [map()]} | {:error, format_error()}
  def format_to_parts(values, options \\ []) do
    with {:ok, formatter} <- Formatter.new(options) do
      Formatter.format_to_parts(formatter, values)
    end
  end

  @doc """
  Formats to parts and raises on error.

  ## Examples

      iex> Icu.List.format_to_parts!(["Foo"])
      [%{part_type: :element, value: "Foo"}]
  """
  @spec format_to_parts!(Enumerable.t(), options_input()) :: [
          map()
        ]
  def format_to_parts!(values, options \\ []) do
    case format_to_parts(values, options) do
      {:ok, parts} -> parts
      {:error, reason} -> raise "list format to parts failed: #{inspect(reason)}"
    end
  end
end
