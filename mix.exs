defmodule ResumeReaderApi.MixProject do
  use Mix.Project

  def project do
    [
      app: :resumereaderapi,
      version: "1.0.1",
      elixir: "~> 1.14",
      description: "Elixir client for the Resume Reader API: parse PDF, DOCX and scanned resumes into 114 structured JSON fields, and normalize job titles, skills and locations.",
      package: package(),
      deps: deps(),
      docs: [main: "readme", extras: ["README.md"]],
      source_url: "https://github.com/explainableaixai/resumereaderapi-elixir",
      homepage_url: "https://www.resumereaderapi.com"
    ]
  end

  def application, do: [extra_applications: [:logger, :inets, :ssl, :public_key]]

  defp deps do
    [{:jason, "~> 1.4"}, {:ex_doc, "~> 0.34", only: :dev, runtime: false}]
  end

  defp package do
    [
      licenses: ["MIT"],
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE),
      links: %{
        "Homepage" => "https://www.resumereaderapi.com",
        "API reference" => "https://www.resumereaderapi.com/api-v2.php",
        "GitHub" => "https://github.com/explainableaixai/resumereaderapi-elixir"
      }
    ]
  end
end
