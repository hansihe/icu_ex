defmodule Icu.MixProject do
  use Mix.Project

  @version "0.4.0"

  def project do
    [
      app: :icu,
      version: @version,
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:decimal, "~> 2.1"},
      {:rustler, "~> 0.37.1", runtime: false},
      {:rustler_precompiled, "~> 0.8"},
      {:gettext, "< 2.0.0", optional: true, runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      files: ["lib", "native", "checksum-*.exs", "mix.exs", "README.md"],
      description: "Elixir bindings to icu4x for i18n",
      links: %{
        "GitHub" => "https://github.com/hansihe/icu_ex"
      },
      licenses: ["Apache-2.0"],
    ]
  end
end
