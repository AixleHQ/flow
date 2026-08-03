# frozen_string_literal: true

require "test_helper"

# Adapter contract test: pins the shapes the two reachable skills.sh endpoints
# actually return, including the failure shapes. `/api/v1` is deliberately absent —
# it authenticates with a Vercel OIDC token and 401s for anyone else, so this
# service no longer has an authenticated path to test.
class SkillsRegistryServiceTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  test "search returns empty array when query is too short" do
    # The endpoint answers 400 for a one-character query, so no request is spent.
    assert_equal [], SkillsRegistryService.search("a")
  end

  test "search maps the documented response shape" do
    stub_request(:get, "https://www.skills.sh/api/search")
      .with(query: { q: "rails", limit: "100" })
      .to_return(
        status: 200,
        body: {
          query: "rails",
          searchType: "fuzzy",
          skills: [
            { id: "org/skills/rails", skillId: "rails", name: "rails", source: "org/skills", installs: 42 }
          ],
          count: 1
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    results = SkillsRegistryService.search("rails")

    assert_equal 1, results.size
    assert_equal "org/skills/rails", results.first[:id]
    assert_equal "rails", results.first[:slug]
    assert_equal "rails", results.first[:name]
    assert_equal "org/skills", results.first[:source]
    assert_equal 42, results.first[:installs]
  end

  test "search accepts a bare array body" do
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
    assert_equal "React", results.first[:name]
  end

  test "search accepts a data-wrapped body" do
    stub_request(:get, "https://www.skills.sh/api/search")
      .with(query: { q: "mantine", limit: "100" })
      .to_return(
        status: 200,
        body: {
          data: [
            { id: "org/skills/mantine", slug: "mantine", name: "Mantine", source: "org/skills", installs: 42 }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert_equal "Mantine", SkillsRegistryService.search("mantine").first[:name]
  end

  test "search filters duplicate entries" do
    stub_request(:get, "https://www.skills.sh/api/search")
      .with(query: { q: "vitest", limit: "100" })
      .to_return(
        status: 200,
        body: {
          skills: [
            { id: "org/skills/vitest", slug: "vitest", name: "Vitest", source: "org/skills", installs: 500 },
            { id: "fork/skills/vitest", slug: "vitest", name: "Fork", source: "fork/skills", installs: 3, isDuplicate: true }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert_equal %w[org/skills/vitest], SkillsRegistryService.search("vitest").map { |s| s[:id] }
  end

  test "search clamps the requested limit to the endpoint maximum" do
    stub_request(:get, "https://www.skills.sh/api/search")
      .with(query: { q: "ruby", limit: "200" })
      .to_return(status: 200, body: { skills: [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_equal [], SkillsRegistryService.search("ruby", limit: 5_000)
  end

  test "search returns empty array on HTTP error" do
    stub_request(:get, "https://www.skills.sh/api/search")
      .with(query: { q: "ruby", limit: "100" })
      .to_return(status: 503, body: "")

    assert_equal [], SkillsRegistryService.search("ruby")
  end

  test "install creates a skill from the download endpoint and stores its hash" do
    stub_request(:get, "https://www.skills.sh/api/download/vercel-labs/agent-skills/next-js-development")
      .to_return(
        status: 200,
        body: {
          hash: "sha256:deadbeef",
          files: [
            { path: "LICENSE.txt", contents: "MIT" },
            {
              path: "SKILL.md",
              contents: "---\nname: Next.js Development\ndescription: Build Next.js apps\n---\n\n# Next.js"
            }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    skill = SkillsRegistryService.install("vercel-labs/agent-skills/next-js-development", scope: @project)

    assert_equal "next-js-development", skill.name
    assert_equal "vercel-labs/agent-skills@next-js-development", skill.package
    assert_equal "vercel-labs/agent-skills", skill.source
    assert_equal "https://github.com/vercel-labs/agent-skills", skill.source_url
    assert_equal "Next.js Development", skill.title
    assert_equal "Build Next.js apps", skill.description
    assert_includes skill.content, "# Next.js"
    assert_equal "sha256:deadbeef", skill.content_hash
    assert_equal "registry", skill.origin
  end

  test "install records the install count the caller already knows" do
    stub_request(:get, "https://www.skills.sh/api/download/org/skills/rails")
      .to_return(
        status: 200,
        body: { hash: "h", files: [ { path: "SKILL.md", contents: "---\nname: rails\n---\n\n# Rails" } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    skill = SkillsRegistryService.install("org/skills/rails", scope: @project, installs: 4_242)

    assert_equal 4_242, skill.install_count
  end

  test "install falls back to GitHub raw when the registry does not carry the skill" do
    skill_md = <<~MD
      ---
      name: vercel-react-best-practices
      description: React best practices
      ---

      # React
    MD

    stub_request(:get, "https://www.skills.sh/api/download/vercel-labs/agent-skills/vercel-react-best-practices")
      .to_return(status: 404, body: { error: "not_found" }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:get, "https://raw.githubusercontent.com/vercel-labs/agent-skills/HEAD/skills/vercel-react-best-practices/SKILL.md")
      .to_return(status: 404, body: "")

    stub_request(:get, "https://api.github.com/repos/vercel-labs/agent-skills/contents/skills")
      .to_return(
        status: 200,
        body: [ { name: "react-best-practices", type: "dir" } ].to_json,
        headers: { "Content-Type" => "application/json" }
      )

    stub_request(:get, "https://raw.githubusercontent.com/vercel-labs/agent-skills/HEAD/skills/react-best-practices/SKILL.md")
      .to_return(status: 200, body: skill_md)

    skill = SkillsRegistryService.install("vercel-labs/agent-skills/vercel-react-best-practices", scope: @project)

    assert_equal "vercel-react-best-practices", skill.name
    assert_equal "React best practices", skill.description
    assert_includes skill.content, "# React"
    assert_nil skill.content_hash
    assert_equal 0, skill.install_count
  end

  # A publisher hosting its own skills has a two-segment id, which the download
  # endpoint cannot address at all — RFC 8615 discovery is the only route.
  test "install resolves a non-GitHub publisher through well-known discovery" do
    skill_md = "---\nname: lark-doc\ndescription: Read and edit docs\n---\n\n# Lark\n"

    stub_request(:get, "https://example.com/.well-known/agent-skills/index.json")
      .to_return(
        status: 200,
        body: { skills: [ { name: "lark-doc", description: "Read and edit docs", files: [ "SKILL.md" ] } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    stub_request(:get, "https://example.com/.well-known/agent-skills/lark-doc/SKILL.md")
      .to_return(status: 200, body: skill_md)

    skill = SkillsRegistryService.install("example.com/lark-doc", scope: @project, installs: 519_024)

    assert_equal "lark-doc", skill.name
    assert_equal "example.com", skill.source
    assert_equal "example.com@lark-doc", skill.package
    assert_equal "https://example.com", skill.source_url
    assert_equal 519_024, skill.install_count
  end

  # "Skill not found" would blame the user for a publisher that simply does not
  # publish a discovery index.
  test "install names the publisher when a self-hosted source cannot be resolved" do
    stub_request(:get, "https://example.com/.well-known/agent-skills/index.json").to_return(status: 404, body: "")
    stub_request(:get, "https://example.com/.well-known/skills/index.json").to_return(status: 404, body: "")

    error = assert_raises(SkillsRegistryService::RegistryError) do
      SkillsRegistryService.install("example.com/lark-doc", scope: @project)
    end

    assert_match(/example\.com does not publish/, error.message)
  end

  test "install raises when neither the registry nor GitHub has the skill" do
    stub_request(:get, "https://www.skills.sh/api/download/missing-org/skills/nope")
      .to_return(status: 404, body: { error: "not_found" }.to_json, headers: { "Content-Type" => "application/json" })

    stub_request(:get, "https://raw.githubusercontent.com/missing-org/skills/HEAD/skills/nope/SKILL.md")
      .to_return(status: 404, body: "")

    stub_request(:get, "https://api.github.com/repos/missing-org/skills/contents/skills")
      .to_return(status: 404, body: "")

    error = assert_raises(SkillsRegistryService::RegistryError) do
      SkillsRegistryService.install("missing-org/skills/nope", scope: @project)
    end

    assert_match(/not found/, error.message)
  end

  test "install updates an existing skill by package" do
    existing = create(
      :skill,
      scope: @project,
      name: "next-js-development",
      package: "vercel-labs/agent-skills@next-js-development",
      source: "vercel-labs/agent-skills",
      title: "Old Title",
      content: "old content"
    )

    stub_request(:get, "https://www.skills.sh/api/download/vercel-labs/agent-skills/next-js-development")
      .to_return(
        status: 200,
        body: {
          hash: "sha256:newer",
          files: [ { path: "SKILL.md", contents: "---\nname: Updated Title\n---\n" } ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert_no_difference -> { Skill.count } do
      skill = SkillsRegistryService.install("vercel-labs/agent-skills/next-js-development", scope: @project)
      assert_equal existing.id, skill.id
    end

    assert_equal "Updated Title", existing.reload.title
    assert_equal "sha256:newer", existing.content_hash
  end
end
