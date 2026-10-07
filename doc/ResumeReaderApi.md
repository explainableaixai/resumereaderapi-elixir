# `ResumeReaderApi`
[🔗](https://github.com/explainableaixai/resumereaderapi-elixir/blob/main/lib/resumereaderapi.ex#L1)

Client for the Resume Reader API: resume parsing into 114 structured fields,
plus job title, skill and location normalization.

    client = ResumeReaderApi.new(System.fetch_env!("RESUME_KEY"))
    {:ok, out} = ResumeReaderApi.parse_file(client, "cv.pdf")
    out["resume"]["contact"]["full_name"]

# `new`

Builds a client.

# `normalize_locations`

# `normalize_skills`

# `normalize_titles`

# `parse_file`

Parse a local file (PDF, DOCX, TXT, RTF, HTML, ODT, XLSX, images).

# `parse_text`

Parse resume text. Options: `:field_names` ("en" or "fr"), `:exclude_sensitive`,
`:anonymize`, `:max_pages`, `:sections`, `:language`.

# `parse_url`

Parse a resume the service downloads from an https URL.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
