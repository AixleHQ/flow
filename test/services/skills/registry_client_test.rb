# frozen_string_literal: true

require "test_helper"

# Adapter contract test: pins the wire shapes of the only two skills.sh endpoints
# reachable without a Vercel OIDC token, including their failure shapes. This is
# the one place `stub_request` belongs for skills.sh (docs/testing.md R3/R4);
# everything above it uses FakeSkillsRegistry.
class Skills::RegistryClientTest < ActiveSupport::TestCase
  test "search maps the documented response" do
    stub_request(:get, "https://www.skills.sh/api/search")
      .with(query: { q: "playwright", limit: "100" })
      .to_return(
        status: 200,
        body: {
          query: "playwright",
          searchType: "fuzzy",
          skills: [
            {
              id: "microsoft/playwright-cli/playwright-cli",
              skillId: "playwright-cli",
              name: "playwright-cli",
              source: "microsoft/playwright-cli",
              installs: 12_345
            }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    entries = Skills::RegistryClient.search("playwright")

    assert_equal 1, entries.size
    assert_equal "microsoft/playwright-cli/playwright-cli", entries.first.id
    assert_equal "playwright-cli", entries.first.slug
    assert_equal "microsoft/playwright-cli", entries.first.source
    assert_equal 12_345, entries.first.installs
  end

  # The endpoint answers 400 for a one-character query, so it is never called.
  test "search does not call the endpoint for a query under two characters" do
    assert_equal [], Skills::RegistryClient.search("a")
    assert_not_requested :get, "https://www.skills.sh/api/search"
  end

  test "search passes the owner filter through" do
    stub_request(:get, "https://www.skills.sh/api/search")
      .with(query: { q: "design", limit: "100", owner: "anthropics" })
      .to_return(status: 200, body: { skills: [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_equal [], Skills::RegistryClient.search("design", owner: "anthropics")
  end

  test "search clamps limit to the endpoint maximum" do
    stub_request(:get, "https://www.skills.sh/api/search")
      .with(query: { q: "react", limit: "200" })
      .to_return(status: 200, body: { skills: [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_equal [], Skills::RegistryClient.search("react", limit: 900)
  end

  test "search drops duplicate entries" do
    stub_request(:get, "https://www.skills.sh/api/search")
      .with(query: { q: "vitest", limit: "100" })
      .to_return(
        status: 200,
        body: {
          skills: [
            { id: "org/skills/vitest", slug: "vitest", name: "Vitest", source: "org/skills", installs: 10 },
            { id: "fork/skills/vitest", slug: "vitest", name: "Fork", source: "fork/skills", installs: 1, isDuplicate: true }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert_equal %w[org/skills/vitest], Skills::RegistryClient.search("vitest").map(&:id)
  end

  # A catalog page must render even when upstream is down.
  test "search returns empty on a server error" do
    stub_request(:get, "https://www.skills.sh/api/search")
      .with(query: { q: "ruby", limit: "100" })
      .to_return(status: 503, body: "")

    assert_equal [], Skills::RegistryClient.search("ruby")
  end

  test "download returns the whole bundle and its content hash" do
    stub_request(:get, "https://www.skills.sh/api/download/anthropics/skills/frontend-design")
      .to_return(
        status: 200,
        body: {
          hash: "sha256:abc",
          files: [
            { path: "LICENSE.txt", contents: "MIT" },
            { path: "SKILL.md", contents: "---\nname: frontend-design\n---\n\n# Frontend" }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    bundle = Skills::RegistryClient.download("anthropics/skills", "frontend-design")

    assert_equal 2, bundle.files.size
    assert_equal "sha256:abc", bundle.content_hash
    assert_includes bundle.skill_md, "# Frontend"
  end

  test "download returns nil for a skill the registry does not carry" do
    stub_request(:get, "https://www.skills.sh/api/download/nobody/nothing/nope")
      .to_return(status: 404, body: { error: "not_found" }.to_json, headers: { "Content-Type" => "application/json" })

    assert_nil Skills::RegistryClient.download("nobody/nothing", "nope")
  end

  test "download returns nil when the bundle carries no files" do
    stub_request(:get, "https://www.skills.sh/api/download/org/skills/empty")
      .to_return(status: 200, body: { hash: "h", files: [] }.to_json, headers: { "Content-Type" => "application/json" })

    assert_nil Skills::RegistryClient.download("org/skills", "empty")
  end

  test "download skips the request without a source or slug" do
    assert_nil Skills::RegistryClient.download("", "slug")
    assert_nil Skills::RegistryClient.download("org/skills", nil)
  end

  # The audit host the CLI itself queries. Public, unlike the documented
  # /api/v1/skills/audit endpoint, and batched per repository.
  test "audits returns every provider's verdict for each skill" do
    stub_request(:get, "https://add-skill.vercel.sh/audit")
      .with(query: { source: "anthropics/skills", skills: "pdf,frontend-design" })
      .to_return(
        status: 200,
        body: {
          pdf: {
            snyk: { risk: "high", analyzedAt: "2026-02-17T22:15:27Z" },
            socket: { risk: "safe", alerts: 0, score: 90, analyzedAt: "2026-03-18T16:47:53Z" }
          },
          "frontend-design": {
            socket: { risk: "safe", alerts: 0, score: 90, analyzedAt: "2026-03-18T16:47:53Z" }
          }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = Skills::RegistryClient.audits("anthropics/skills", %w[pdf frontend-design])

    assert_equal "high", result.dig("pdf", "snyk", "risk")
    assert_equal 90, result.dig("pdf", "socket", "score")
    assert_equal "safe", result.dig("frontend-design", "socket", "risk")
  end

  test "audits skips the request with no slugs" do
    assert_empty Skills::RegistryClient.audits("anthropics/skills", [])
    assert_not_requested :get, "https://add-skill.vercel.sh/audit"
  end

  # An audit lookup must never block a catalog page or an install.
  test "audits returns empty on failure" do
    stub_request(:get, "https://add-skill.vercel.sh/audit")
      .with(query: { source: "org/skills", skills: "one" })
      .to_return(status: 500, body: "")

    assert_empty Skills::RegistryClient.audits("org/skills", %w[one])
  end
end
