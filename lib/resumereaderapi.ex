defmodule ResumeReaderApi do
  @moduledoc """
  Client for the Resume Reader API: resume parsing into 114 structured fields,
  plus job title, skill and location normalization.

      client = ResumeReaderApi.new(System.fetch_env!("RESUME_KEY"))
      {:ok, out} = ResumeReaderApi.parse_file(client, "cv.pdf")
      out["resume"]["contact"]["full_name"]
  """

  @base "https://www.resumereaderapi.com/api/"

  @status_text %{
    400 => "missing or invalid input",
    401 => "invalid API key",
    402 => "insufficient credits, nothing was billed",
    413 => "document beyond 20 pages, about 30,000 tokens or 10 MB, nothing was billed",
    422 => "file could not be read as a resume",
    429 => "rate limit exceeded, 30 requests per 60 seconds per IP"
  }

  defstruct [:api_key, timeout: 120_000]

  @doc "Builds a client."
  def new(api_key, opts \\ []) when is_binary(api_key) do
    %__MODULE__{api_key: api_key, timeout: Keyword.get(opts, :timeout, 120_000)}
  end

  @doc """
  Parse resume text. Options: `:field_names` ("en" or "fr"), `:exclude_sensitive`,
  `:anonymize`, `:max_pages`, `:sections`, `:language`.
  """
  def parse_text(%__MODULE__{} = c, text, opts \\ []), do: parse(c, %{"text" => text}, opts)

  @doc "Parse a local file (PDF, DOCX, TXT, RTF, HTML, ODT, XLSX, images)."
  def parse_file(%__MODULE__{} = c, path, opts \\ []) do
    with {:ok, bin} <- File.read(path) do
      parse(c, %{"file_base64" => Base.encode64(bin), "filename" => Path.basename(path)}, opts)
    end
  end

  @doc "Parse a resume the service downloads from an https URL."
  def parse_url(%__MODULE__{} = c, url, opts \\ []), do: parse(c, %{"file_url" => url}, opts)

  @doc false
  def build_payload(%__MODULE__{} = c, source, opts) do
    %{"api_key" => c.api_key, "schema_version" => 2}
    |> Map.merge(source)
    |> put_opt("field_names", opts[:field_names])
    |> put_flag("exclude_sensitive", opts[:exclude_sensitive])
    |> put_flag("anonymize", opts[:anonymize])
    |> put_opt("max_pages", opts[:max_pages])
    |> put_opt("sections", opts[:sections])
    |> put_opt("language", opts[:language])
  end

  defp parse(c, source, opts), do: post(c, "parse.php", build_payload(c, source, opts))

  def normalize_titles(c, titles), do: normalize(c, "normalize_title.php", "titles", titles)
  def normalize_skills(c, skills), do: normalize(c, "normalize_skills.php", "skills", skills)
  def normalize_locations(c, locations), do: normalize(c, "normalize_locations.php", "locations", locations)

  defp normalize(c, endpoint, key, items) do
    items
    |> List.wrap()
    |> Enum.chunk_every(100)
    |> Enum.reduce_while({:ok, %{results: [], credits_used: 0.0, remaining_credits: nil}}, fn chunk, {:ok, acc} ->
      case post(c, endpoint, %{"api_key" => c.api_key, key => chunk}) do
        {:ok, body} ->
          {:cont,
           {:ok,
            %{
              results: acc.results ++ Map.get(body, "results", []),
              credits_used: acc.credits_used + (Map.get(body, "credits_used") || 0),
              remaining_credits: Map.get(body, "remaining_credits", acc.remaining_credits)
            }}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp put_opt(map, _k, nil), do: map
  defp put_opt(map, k, v), do: Map.put(map, k, v)
  defp put_flag(map, k, true), do: Map.put(map, k, true)
  defp put_flag(map, _k, _), do: map

  defp post(c, endpoint, payload) do
    headers = [{~c"user-agent", ~c"resumereaderapi-elixir/1.0.0 (+https://www.resumereaderapi.com)"}]
    req = {String.to_charlist(@base <> endpoint), headers, ~c"application/json", Jason.encode!(payload)}

    http_opts = [timeout: c.timeout, ssl: [verify: :verify_peer, cacerts: :public_key.cacerts_get(), depth: 3,
                 customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]]]

    with {:ok, {{_, _, _}, _, raw}} <- :httpc.request(:post, req, http_opts, body_format: :binary),
         {:ok, json} <- Jason.decode(raw) do
      case Map.get(json, "status", 200) do
        200 -> {:ok, json}
        status -> {:error, %{status: status, message: Map.get(@status_text, status, "API error"), body: json}}
      end
    else
      {:error, reason} -> {:error, %{status: 0, message: inspect(reason)}}
    end
  end
end
