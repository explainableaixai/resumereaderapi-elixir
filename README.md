# resumereaderapi for Elixir

Parse CVs and clean up candidate data from Elixir. The package talks to the Resume Reader API, returns plain maps and tuples, and relies on OTP's HTTP client plus Jason.

## Add it

```elixir
{:resumereaderapi, "~> 1.0"}
```

## Parse a file

```elixir
client = ResumeReaderApi.new(System.fetch_env!("RESUME_KEY"))

{:ok, out} = ResumeReaderApi.parse_file(client, "priv/cv.pdf")
get_in(out, ["resume", "contact", "full_name"])
get_in(out, ["resume", "career", "seniority_level"])
```

Results come back as `{:ok, map}` or `{:error, %{status: n, message: text, body: map}}`.

## Parse options

```elixir
ResumeReaderApi.parse_text(client, text,
  field_names: "fr",
  exclude_sensitive: true,
  anonymize: true,
  max_pages: 5,
  sections: ["contact", "skills"],
  language: "de"
)
```

`parse_url/3` and `parse_file/3` accept the same keyword list.

## Normalizers

```elixir
{:ok, %{results: rows, credits_used: spent}} =
  ResumeReaderApi.normalize_locations(client, ["NYC", "München", "Remote (Germany)"])

Enum.each(rows, &IO.puts("#{&1["input"]} -> #{&1["normalized"]}"))
```

Lists longer than 100 are chunked, and credits are summed.

## Broadway or Oban worker

```elixir
defmodule MyApp.ParseCv do
  use Oban.Worker, queue: :cv, max_attempts: 5

  @impl true
  def perform(%Oban.Job{args: %{"path" => path, "candidate_id" => id}}) do
    case ResumeReaderApi.parse_file(client(), path) do
      {:ok, out} -> MyApp.Candidates.store(id, out["resume"])
      {:error, %{status: 429}} -> {:snooze, 30}
      {:error, %{status: s}} when s in [413, 422] -> {:cancel, "unreadable document"}
      {:error, e} -> {:error, e}
    end
  end

  defp client, do: ResumeReaderApi.new(Application.fetch_env!(:my_app, :resume_key))
end
```

Snoozing on 429 respects the limit of 30 requests per minute per IP.

## What to do with the output

Write the interesting fields into columns, keep the whole JSON in a `jsonb` column, and index `career.seniority_level` and `skills.technical`. Staffing teams do exactly that to find temps by shift skill, as described for [staffing agencies](https://www.resumereaderapi.com/use-cases/staffing-agencies.php).

## Questions

**Why not Req?** Fewer dependencies and one less thing to upgrade.

**Does it verify TLS?** Yes, with the OTP certificate store.

**License?** MIT. info@alpha-quantum.com
