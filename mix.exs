defmodule ExrmRpm.Mixfile do
  use Mix.Project

  def project do
    [app: :distillery_rpm,
     version: "0.1.0",
     elixir: "~> 1.0",
     description: description(),
     package: package(),
     deps: deps()]
  end

  def application do
    [applications: []]
  end

  defp description do
    """
    Adds simple Red Hat Package Manager (RPM) generation to the distillery package manager.
    The generated RPM file includes the Elixir release and an init.d script to
    manage the project's service.
    """
  end

  defp deps do
    [{:distillery, "~> 1.0"}]
  end

  defp package do
    [ files: ["lib", "priv", "mix.exs", "README.md", "LICENSE"],
      contributors: ["Rafal Slota"],
      maintainers: ["Rafal Slota"],
      licenses: ["MIT"],
      links: %{github: "https://github.com/rslota/distillery_rpm"}
    ]
  end
end
