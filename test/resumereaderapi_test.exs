defmodule ResumeReaderApiTest do
  use ExUnit.Case

  test "payload carries options and always asks for schema 2" do
    c = ResumeReaderApi.new("k")
    p = ResumeReaderApi.build_payload(c, %{"text" => "cv"}, anonymize: true, field_names: "fr")
    assert p["schema_version"] == 2
    assert p["anonymize"] == true
    assert p["field_names"] == "fr"
    refute Map.has_key?(p, "exclude_sensitive")
  end
end
