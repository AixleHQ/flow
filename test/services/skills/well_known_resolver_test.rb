# frozen_string_literal: true

require "test_helper"

# Adapter contract test for RFC 8615 discovery — the only way a publisher hosting its
# own skills (two-segment id, e.g. `open.feishu.cn/lark-doc`, 519k installs) can be
# installed at all: the skills.sh download endpoint has no third path segment to
# address them with.
class Skills::WellKnownResolverTest < ActiveSupport::TestCase
  V1_INDEX = {
    skills: [
      { name: "lark-doc", description: "Read and edit docs", files: [ "SKILL.md", "references/api.md" ] }
    ]
  }.freeze

  SKILL_MD = "---\nname: lark-doc\ndescription: Read and edit docs\n---\n\n# Lark doc\n"

  test "resolves a v0.1.0 index from the preferred well-known path" do
    stub_request(:get, "https://example.com/.well-known/agent-skills/index.json")
      .to_return(status: 200, body: V1_INDEX.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.com/.well-known/agent-skills/lark-doc/SKILL.md")
      .to_return(status: 200, body: SKILL_MD)

    assert_equal SKILL_MD, Skills::WellKnownResolver.fetch_skill_md("example.com", "lark-doc")
  end

  test "falls back to the legacy well-known path" do
    stub_request(:get, "https://example.com/.well-known/agent-skills/index.json").to_return(status: 404, body: "")
    stub_request(:get, "https://example.com/.well-known/skills/index.json")
      .to_return(status: 200, body: V1_INDEX.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.com/.well-known/skills/lark-doc/SKILL.md")
      .to_return(status: 200, body: SKILL_MD)

    assert_equal SKILL_MD, Skills::WellKnownResolver.fetch_skill_md("example.com", "lark-doc")
  end

  test "resolves a v0.2.0 entry through its artifact url" do
    index = {
      skills: [
        { name: "lark-doc", type: "skill-md", description: "d",
          url: "https://example.com/artifacts/lark-doc.md", digest: "sha256:x" }
      ]
    }
    stub_request(:get, "https://example.com/.well-known/agent-skills/index.json")
      .to_return(status: 200, body: index.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.com/artifacts/lark-doc.md").to_return(status: 200, body: SKILL_MD)

    assert_equal SKILL_MD, Skills::WellKnownResolver.fetch_skill_md("example.com", "lark-doc")
  end

  # Unpacking a remote archive is a much larger trust decision than reading one
  # markdown file, and is deliberately not made here.
  test "refuses an archive artifact" do
    index = { skills: [ { name: "lark-doc", type: "archive", description: "d", url: "https://example.com/a.zip" } ] }
    stub_request(:get, "https://example.com/.well-known/agent-skills/index.json")
      .to_return(status: 200, body: index.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.com/.well-known/skills/index.json").to_return(status: 404, body: "")

    assert_nil Skills::WellKnownResolver.fetch_skill_md("example.com", "lark-doc")
    assert_not_requested :get, "https://example.com/a.zip"
  end

  # The index is published by the same untrusted party as the skill, so it must not be
  # able to point us at another host.
  test "refuses an artifact url on a different host" do
    index = { skills: [ { name: "lark-doc", type: "skill-md", description: "d", url: "https://evil.test/x.md" } ] }
    stub_request(:get, "https://example.com/.well-known/agent-skills/index.json")
      .to_return(status: 200, body: index.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.com/.well-known/skills/index.json").to_return(status: 404, body: "")

    assert_nil Skills::WellKnownResolver.fetch_skill_md("example.com", "lark-doc")
    assert_not_requested :get, "https://evil.test/x.md"
  end

  test "ignores an index that does not carry the requested skill" do
    stub_request(:get, "https://example.com/.well-known/agent-skills/index.json")
      .to_return(status: 200, body: V1_INDEX.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.com/.well-known/skills/index.json")
      .to_return(status: 200, body: V1_INDEX.to_json, headers: { "Content-Type" => "application/json" })

    assert_nil Skills::WellKnownResolver.fetch_skill_md("example.com", "something-else")
  end

  test "treats an HTML response as a miss rather than content" do
    stub_request(:get, "https://example.com/.well-known/agent-skills/index.json")
      .to_return(status: 200, body: "<!DOCTYPE html><html><body>SPA shell</body></html>")
    stub_request(:get, "https://example.com/.well-known/skills/index.json")
      .to_return(status: 200, body: "<!DOCTYPE html><html></html>")

    assert_nil Skills::WellKnownResolver.fetch_skill_md("example.com", "lark-doc")
  end

  test "survives a malformed index" do
    stub_request(:get, "https://example.com/.well-known/agent-skills/index.json")
      .to_return(status: 200, body: "{not json", headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://example.com/.well-known/skills/index.json")
      .to_return(status: 200, body: [ "not", "a", "hash" ].to_json)

    assert_nil Skills::WellKnownResolver.fetch_skill_md("example.com", "lark-doc")
  end

  # The host arrives from a registry id, i.e. from data we do not control. These are
  # requests we must never make.
  test "refuses hosts that are not plain public hostnames" do
    [
      "localhost", "metadata.internal", "printer.local", "127.0.0.1", "10.0.0.5",
      "example.com:8080", "user@example.com", "owner/repo", "", nil, "com"
    ].each do |host|
      assert_not Skills::WellKnownResolver.resolvable?(host), "#{host.inspect} must not be resolvable"
      assert_nil Skills::WellKnownResolver.fetch_skill_md(host, "lark-doc")
    end
  end

  test "recognises an owner/repo coordinate as not its business" do
    assert_not Skills::WellKnownResolver.resolvable?("anthropics/skills")
    assert Skills::WellKnownResolver.resolvable?("open.feishu.cn")
  end
end
