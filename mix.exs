defmodule Icu.MixProject do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :icu,
      version: @version,
      elixir: "~> 1.18",
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
      {:rustler, "~> 0.37.1", runtime: false},
      {:rustler_precompiled, "~> 0.8"}
    ]
  end

  defp package do
    [
      links: %{
        "GitHub" => "https://github.com/hansihe/icu_ex"
      }
    ]
  end
end
