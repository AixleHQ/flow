# frozen_string_literal: true

require "test_helper"

# Adapter contract test for reading SKILL.md off GitHub raw — the free path that makes
# describing a catalog of thousands of entries possible, since the registry's own
# download endpoint allows only 60 requests per hour for the whole deployment.
class Skills::GithubSkillMdTest < ActiveSupport::TestCase
  SKILL_MD = "---\nname: brainstorming\ndescription: Refines an idea before code\n---\n\n# Steps\n"

  test "finds a skill under the conventional skills directory" do
    stub_request(:get, "https://raw.githubusercontent.com/obra/superpowers/HEAD/skills/brainstorming/SKILL.md")
      .to_return(status: 200, body: SKILL_MD)

    assert_equal SKILL_MD, Skills::GithubSkillMd.fetch("obra/superpowers", "brainstorming")
  end

  test "finds a skill stored at the repository root" do
    stub_request(:get, "https://raw.githubusercontent.com/obra/superpowers/HEAD/skills/brainstorming/SKILL.md")
      .to_return(status: 404, body: "404: Not Found")
    stub_request(:get, "https://raw.githubusercontent.com/obra/superpowers/HEAD/brainstorming/SKILL.md")
      .to_return(status: 200, body: SKILL_MD)

    assert_equal SKILL_MD, Skills::GithubSkillMd.fetch("obra/superpowers", "brainstorming")
  end

  # Publishers sometimes prefix the registry slug with their own name while the
  # directory is unprefixed.
  test "tries the slug without its publisher prefix" do
    body = "---\nname: vercel-react-best-practices\ndescription: d\n---\n\nbody"
    %w[
      skills/vercel-react-best-practices/SKILL.md
      vercel-react-best-practices/SKILL.md
    ].each do |path|
      stub_request(:get, "https://raw.githubusercontent.com/vercel-labs/agent-skills/HEAD/#{path}")
        .to_return(status: 404, body: "")
    end
    stub_request(:get, "https://raw.githubusercontent.com/vercel-labs/agent-skills/HEAD/skills/react-best-practices/SKILL.md")
      .to_return(status: 200, body: body)

    assert_equal body, Skills::GithubSkillMd.fetch("vercel-labs/agent-skills", "vercel-react-best-practices")
  end

  # A guessed path that holds a DIFFERENT skill must not be accepted — otherwise the
  # catalog would describe an entry with someone else's text.
  test "refuses content whose frontmatter names another skill" do
    stub_request(:get, %r{raw\.githubusercontent\.com/obra/superpowers/HEAD/.*SKILL\.md})
      .to_return(status: 200, body: "---\nname: something-else\ndescription: d\n---\n\nbody")

    assert_nil Skills::GithubSkillMd.fetch("obra/superpowers", "brainstorming")
  end

  test "treats an HTML body as a miss" do
    stub_request(:get, %r{raw\.githubusercontent\.com/obra/superpowers/HEAD/.*SKILL\.md})
      .to_return(status: 200, body: "<!DOCTYPE html><html></html>")

    assert_nil Skills::GithubSkillMd.fetch("obra/superpowers", "brainstorming")
  end

  # A publisher host is not a GitHub coordinate; those resolve through well-known
  # discovery instead, and must not produce a raw.githubusercontent request.
  test "ignores sources that are not owner/repo" do
    [ "open.feishu.cn", "owner/repo/extra", "", nil ].each do |source|
      assert_nil Skills::GithubSkillMd.fetch(source, "lark-doc")
    end

    assert_not_requested :get, %r{raw\.githubusercontent\.com}
  end
end
