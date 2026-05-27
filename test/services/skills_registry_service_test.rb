# frozen_string_literal: true

require "test_helper"

class SkillsRegistryServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @api_key = "sk_live_test_key"
    Settings.skills_sh.api_key = @api_key
  end

  teardown do
    Settings.skills_sh.api_key = nil
  end

  test "search returns empty array when query is too short" do
    assert_equal [], SkillsRegistryService.search("a")
  end

  test "search falls back to public endpoint when api key is missing" do
    Settings.skills_sh.api_key = nil

    stub_request(:get, "https://www.skills.sh/api/search")
      .with(query: { q: "react", limit: "100" })
      .to_return(
        status: 200,
        body: [
          { id: "vercel-labs/agent-skills/react", slug: "react", name: "React", source: "vercel-labs/agent-skills", installs: 100 }
        ].to_json,
        headers: { "Content-Type" => "application/json" }
      )

    results = SkillsRegistryService.search("react")

    assert_equal 1, results.size
    assert_equal "vercel-labs/agent-skills/react", results.first[:id]
    assert_equal "React", results.first[:name]
  end

  test "search public fallback handles data-wrapped response" do
    Settings.skills_sh.api_key = nil

    stub_request(:get, "https://www.skills.sh/api/search")
      .with(query: { q: "rails", limit: "100" })
      .to_return(
        status: 200,
        body: {
          data: [
            { id: "org/skills/rails", slug: "rails", name: "Rails", source: "org/skills", installs: 42 }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    results = SkillsRegistryService.search("rails")

    assert_equal 1, results.size
    assert_equal "Rails", results.first[:name]
  end

  test "search public fallback returns empty array on HTTP error" do
    Settings.skills_sh.api_key = nil

    stub_request(:get, "https://www.skills.sh/api/search")
      .with(query: { q: "ruby", limit: "100" })
      .to_return(status: 503, body: "")

    assert_equal [], SkillsRegistryService.search("ruby")
  end

  test "search maps v1 response and filters duplicates" do
    stub_request(:get, %r{https://skills\.sh/api/v1/skills/search})
      .with(
        query: { q: "react", limit: "50" },
        headers: { "Authorization" => "Bearer #{@api_key}" }
      )
      .to_return(
        status: 200,
        body: {
          data: [
            {
              id: "expo/skills/react-native",
              slug: "react-native",
              name: "React Native",
              source: "expo/skills",
              installs: 3842,
              isDuplicate: false
            },
            {
              id: "fork/skills/react-native",
              slug: "react-native",
              name: "React Native Fork",
              source: "fork/skills",
              installs: 10,
              isDuplicate: true
            }
          ],
          query: "react",
          count: 2
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    results = SkillsRegistryService.search("react")

    assert_equal 1, results.size
    assert_equal "expo/skills/react-native", results.first[:id]
    assert_equal "react-native", results.first[:slug]
    assert_equal "React Native", results.first[:name]
    assert_equal "expo/skills", results.first[:source]
    assert_equal 3842, results.first[:installs]
  end

  test "install creates skill from v1 detail endpoint" do
    skill_id = "vercel-labs/agent-skills/next-js-development"
    stub_request(:get, "https://skills.sh/api/v1/skills/vercel-labs/agent-skills/next-js-development")
      .with(headers: { "Authorization" => "Bearer #{@api_key}" })
      .to_return(
        status: 200,
        body: {
          id: skill_id,
          source: "vercel-labs/agent-skills",
          slug: "next-js-development",
          installs: 24_531,
          files: [
            {
              path: "SKILL.md",
              contents: "---\nname: Next.js Development\ndescription: Build Next.js apps\n---\n\n# Next.js"
            }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    skill = SkillsRegistryService.install(skill_id, scope: @company)

    assert_equal "next-js-development", skill.name
    assert_equal "vercel-labs/agent-skills@next-js-development", skill.package
    assert_equal "vercel-labs/agent-skills", skill.source
    assert_equal "https://github.com/vercel-labs/agent-skills", skill.source_url
    assert_equal "Next.js Development", skill.title
    assert_equal "Build Next.js apps", skill.description
    assert_includes skill.content, "# Next.js"
    assert_equal 24_531, skill.install_count
  end

  test "install raises when api key is missing" do
    Settings.skills_sh.api_key = nil

    error = assert_raises(SkillsRegistryService::RegistryError) do
      SkillsRegistryService.install("vercel-labs/agent-skills/next-js-development", scope: @company)
    end

    assert_match(/API key/, error.message)
  end

  test "install raises when skill is not found" do
    stub_request(:get, %r{https://skills\.sh/api/v1/skills/missing/skill})
      .to_return(status: 404, body: { error: "not_found", message: "Skill not found" }.to_json)

    error = assert_raises(SkillsRegistryService::RegistryError) do
      SkillsRegistryService.install("missing/skill", scope: @company)
    end

    assert_match(/not found/, error.message)
  end

  test "install updates existing skill by package" do
    existing = create(
      :skill,
      :with_company_scope,
      scope: @company,
      name: "next-js-development",
      package: "vercel-labs/agent-skills@next-js-development",
      source: "vercel-labs/agent-skills",
      title: "Old Title",
      content: "old content"
    )

    stub_request(:get, "https://skills.sh/api/v1/skills/vercel-labs/agent-skills/next-js-development")
      .to_return(
        status: 200,
        body: {
          id: "vercel-labs/agent-skills/next-js-development",
          source: "vercel-labs/agent-skills",
          slug: "next-js-development",
          installs: 30_000,
          files: [ { path: "SKILL.md", contents: "---\nname: Updated Title\n---\n" } ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    skill = SkillsRegistryService.install("vercel-labs/agent-skills/next-js-development", scope: @company)

    assert_equal existing.id, skill.id
    assert_equal "Updated Title", skill.reload.title
  end
end
