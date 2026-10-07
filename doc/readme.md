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

<!--expanded-->
## Resume ingestion the OTP way

Resume ingestion is a stream of independent jobs that can fail independently, which is exactly what the BEAM is good at. Each file is a unit of work. Some will parse in seconds, some will fail with an unreadable scan, and a few will time out. A supervised pipeline lets the good ones through and handles the bad ones without drama.

The library gives you pure functions that return `{:ok, map}` or `{:error, map}`. Wrap them in whatever process structure suits your system. Below are three patterns, from the simplest to the most structured.

## Pattern one: a task per file

For a folder of files, `Task.async_stream` with a small concurrency limit is enough:

```elixir
client = ResumeReaderApi.new(System.fetch_env!("RESUME_KEY"))

results =
  Path.wildcard("inbox/*.{pdf,docx}")
  |> Task.async_stream(
    fn path -> {path, ResumeReaderApi.parse_file(client, path)} end,
    max_concurrency: 3,
    timeout: 130_000,
    on_timeout: :kill_task
  )
  |> Enum.map(fn
    {:ok, {path, {:ok, out}}} -> {path, out["resume"]}
    {:ok, {path, {:error, e}}} -> {path, {:error, e.status}}
    {:exit, reason} -> {:crashed, reason}
  end)
```

Three at a time keeps you inside the limit of 30 requests per 60 seconds per IP for typical parse times. If your files parse faster, add a short sleep inside the function.

## Pattern two: a pacing process

When many callers share one IP, give the pacing job to a single process. A GenServer that hands out permits at a fixed interval makes the limit a property of your system instead of a hope:

```elixir
defmodule MyApp.Pace do
  use GenServer
  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  def wait, do: GenServer.call(__MODULE__, :wait, :infinity)

  @impl true
  def init(:ok), do: {:ok, 0}

  @impl true
  def handle_call(:wait, _from, last) do
    now = System.monotonic_time(:millisecond)
    delay = max(0, last + 2_100 - now)
    Process.sleep(delay)
    {:reply, :ok, System.monotonic_time(:millisecond)}
  end
end
```

Each worker calls `MyApp.Pace.wait()` before it parses. The process serializes the waits and the rest of the system stays simple.

## Pattern three: a queue with retries

For production, use a job queue such as Oban. Each job holds a file path and a candidate id. The worker parses, stores and returns. Map statuses to outcomes in one function: snooze on 429, cancel on 413 and 422, retry on transport errors, and alert on 401 and 402. With that mapping in place, the queue handles backoff, visibility and history for you.

## Storing and querying

Postgres with a `jsonb` column is a good home for parsed resumes. Store the whole `resume` map. Add generated columns or indexes for the fields you search most, such as the seniority level, the total experience, the country and the technical skills array. A GIN index on the skills lets you ask for candidates with a given skill in milliseconds.

Because every key is present in every response, queries can rely on the shape. An empty array means no evidence, not a missing key. That removes a whole class of defensive conditions from your SQL.

## Normalizing in bulk

Candidate tables always contain more spellings than meanings. Normalizers collapse them. A nightly job can select the distinct raw titles and skills added since the last run, send them in batches and store the canonical forms in lookup tables. The library chunks lists above 100 items for you and sums `credits_used`.

```elixir
{:ok, %{results: rows, credits_used: spent}} =
  ResumeReaderApi.normalize_skills(client, ["JS", "Javascript", "K8s", "Python 3.11", "MS Excel"])

Enum.each(rows, fn r -> IO.puts("#{r["input"]} -> #{r["normalized_skill"]} (#{r["skill_type"]})") end)
IO.puts("credits: #{spent}")
```

Skills come back with one of fourteen types, and titles come back with a seniority level and a job function. Locations come back as a city, region, country and ISO code, with a metro area and a remote flag where they apply.

## Privacy features as options

`anonymize: true` replaces names and contact values with placeholders. `exclude_sensitive: true` leaves out the nine sensitive fields. Use them together for a review copy and keep the full record only where it is needed. Remember that deleting a candidate means deleting every copy you hold, including parsed JSON in backups and analytics tables, so keep a list of where parsed data goes.

## Related reading

Audience and acquisition data live next to hiring data in many companies. The guide to [audience data for publishers](https://www.cookielessaudiences.com/industries/publishers.php) shows how a publisher describes its readers without tracking them. The page on [buy side long lists](https://www.acquisitionuniverse.com/use-cases/buy-side-long-lists.php) shows how an investor builds a ranked list of acquisition candidates with evidence for each claim.

## Troubleshooting

**`{:error, %{status: 429}}`.** Slow down. Use a pacing process or lower concurrency.

**`{:error, %{status: 422}}`.** The file had no readable text. Ask for another format.

**`{:error, %{status: 402}}`.** No credits. Nothing was billed. Top up.

**Slow responses.** Large scans take longer. Raise `timeout` in `Task.async_stream` and in the client options.

**Encoding errors in names.** Names with accents come back as UTF-8. Make sure your database and your terminal use UTF-8 too.

## Compatibility

The library works with Elixir 1.14 or later and OTP 25 or later. It uses `:httpc` for HTTP and Jason for JSON, and it starts no processes of its own.

<!--extra-->
## Fixtures worth keeping

Keep five recorded responses in your test suite: a full resume, a sparse one, a scanned one that went through character recognition, a 402 for credits and a 422 for an unreadable file. Replace the personal details with invented ones. These fixtures let you test your mapping code, your error handling and your storage layer without a network, and they document the shapes you rely on better than any comment.

Remember that normalized values are derived data. Save them next to the originals, with the date and the method field, so you can explain how a canonical value came about. When a fallback result looks wrong, correct it in your own mapping table and let that correction win on later runs. A small override table is the cheapest quality control you can build.

<!--further-->
## Further reading and practical notes

The [Elixir language site](https://elixir-lang.org/) links to the guides and the reference for processes, tasks and supervision. The occupation framework behind the `esco` block of each response is documented on the [ESCO portal](https://esco.ec.europa.eu/en).

Operating notes for an Elixir ingestion service. Give the parse stage its own supervisor, so that a burst of failures there cannot take down the web endpoint. Put a hard limit on the size of your queue, and reject uploads politely when it is full, because an unbounded queue only moves the failure later. Record the time each file spent waiting, parsing and storing. Those three numbers tell you which stage to scale.

For testing, replace the HTTP layer with a fake that returns recorded responses. Keep a handful of real responses, with personal details replaced, as fixtures, one per interesting case: a full resume, a sparse one, a scanned one, an error for credits and an error for an unreadable file. Tests built on real shapes catch more than tests built on imagined ones.

Finally, think about what happens when the schema grows. Because the service returns every key in every response, new keys appear in the same predictable way. Write your mapping code so that unknown keys are ignored and missing keys are impossible, and an upgrade becomes a non-event.

A last practical point concerns language. Resumes arrive in many languages, and names, cities and job titles keep their original spelling in the parsed record. Do not assume ASCII in your database, your logs or your search index. Make sure your collation sorts accented names sensibly, and use the normalizers when you need one canonical form for comparison.

## Questions

**Why not Req?** Fewer dependencies and one less thing to upgrade.

**Does it verify TLS?** Yes, with the OTP certificate store.

**License?** MIT. info@alpha-quantum.com
