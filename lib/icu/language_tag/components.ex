defmodule Icu.LanguageTag.Components do
  @moduledoc """
  Components of a BCP-47 language tag.

  Instances of this struct are returned by `Icu.LanguageTag.components/1`.
  """

  @enforce_keys [:variants]
  defstruct language: nil,
            script: nil,
            region: nil,
            variants: []

  @type t :: %__MODULE__{
          language: String.t() | nil,
          script: String.t() | nil,
          region: String.t() | nil,
          variants: [String.t()]
        }
end
