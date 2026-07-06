# frozen_string_literal: true

require "test_helper"

class InternalTools::MetaSearchSkillsTest < ActiveSupport::TestCase
  setup do
    @api_key = "sk_live_test_key"
    Settings.skills_sh.api_key = @api_key
  end

  teardown do
    Settings.skills_sh.api_key = nil
  end

  def stub_search_endpoint(query:, data:)
    stub_request(:get, "https://skills.sh/api/v1/skills/search")
      .with(
        query: { "q" => query, "limit" => "50" },
        headers: { "Authorization" => "Bearer #{@api_key}" }
      )
      .to_return(
        status: 200,
        body: { data: data }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  test "returns matching skills from the registry with the mapped payload" do
    stub_search_endpoint(
      query: "mantine",
      data: [
        {
          id: "mantinedev/skills/mantine-form",
          slug: "mantine-form",
          name: "Mantine Form",
          source: "mantinedev/skills",
          installs: 1234
        },
        {
          id: "mantinedev/skills/mantine-core",
          slug: "mantine-core",
          name: "Mantine Core",
          source: "mantinedev/skills",
          installs: 42
        }
      ]
    )

    result = InternalTools::MetaSearchSkills.new(
      params: { query: "mantine" },
      session: nil
    ).execute

    assert_equal 0, result[:exit_code]
    assert_equal "", result[:stderr]

    data = JSON.parse(result[:stdout])
    assert_equal "mantine", data["query"]
    assert_equal 2, data["results_count"]
    assert_equal 2, data["skills"].size

    first = data["skills"].first
    assert_equal "mantinedev/skills/mantine-form", first["id"]
    assert_equal "mantine-form", first["slug"]
    assert_equal "Mantine Form", first["name"]
    assert_equal "mantinedev/skills", first["source"]
    assert_equal 1234, first["installs"]
  end

  test "strips surrounding whitespace from the query before searching" do
    stub_search_endpoint(
      query: "react",
      data: [
        { id: "vercel/skills/react", slug: "react", name: "React", source: "vercel/skills", installs: 7 }
      ]
    )

    result = InternalTools::MetaSearchSkills.new(
      params: { query: "  react  " },
      session: nil
    ).execute

    assert_equal 0, result[:exit_code]

    data = JSON.parse(result[:stdout])
    assert_equal "react", data["query"]
    assert_equal 1, data["results_count"]
    assert_equal "react", data["skills"].first["slug"]
  end

  test "excludes duplicate entries from the results count and list" do
    stub_search_endpoint(
      query: "testing",
      data: [
        { id: "org/skills/vitest", slug: "vitest", name: "Vitest", source: "org/skills", installs: 500 },
        { id: "org/skills/vitest-dup", slug: "vitest-dup", name: "Vitest Dup", source: "org/skills", installs: 3, isDuplicate: true }
      ]
    )

    result = InternalTools::MetaSearchSkills.new(
      params: { query: "testing" },
      session: nil
    ).execute

    assert_equal 0, result[:exit_code]

    data = JSON.parse(result[:stdout])
    assert_equal 1, data["results_count"]
    assert_equal %w[vitest], data["skills"].map { |s| s["slug"] }
  end

  test "falls back to the skill slug when the registry omits a name" do
    stub_search_endpoint(
      query: "unnamed",
      data: [
        { id: "org/skills/anon", slug: "anon", source: "org/skills", installs: 0 }
      ]
    )

    result = InternalTools::MetaSearchSkills.new(
      params: { query: "unnamed" },
      session: nil
    ).execute

    assert_equal 0, result[:exit_code]

    data = JSON.parse(result[:stdout])
    skill = data["skills"].first
    assert_equal "anon", skill["name"]
    assert_equal 0, skill["installs"]
  end

  test "returns a success payload with zero results when the registry has no matches" do
    stub_search_endpoint(query: "nomatchhere", data: [])

    result = InternalTools::MetaSearchSkills.new(
      params: { query: "nomatchhere" },
      session: nil
    ).execute

    assert_equal 0, result[:exit_code]
    assert_equal "", result[:stderr]

    data = JSON.parse(result[:stdout])
    assert_equal "nomatchhere", data["query"]
    assert_equal 0, data["results_count"]
    assert_equal [], data["skills"]
  end
end
