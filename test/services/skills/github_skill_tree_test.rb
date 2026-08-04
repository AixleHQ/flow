# frozen_string_literal: true

require "test_helper"

# Adapter contract test for resolving SKILL.md through a repository's real tree — the
# only path that reaches the nested layouts carrying most of the catalog, and the one
# that spends api.github.com's 60-per-hour allowance, so its budgeting is pinned here.
class Skills::GithubSkillTreeTest < ActiveSupport::TestCase
  TREE_URL = "https://api.github.com/repos/wshobson/agents/git/trees/HEAD?recursive=1"
  NESTED = "plugins/accessibility-compliance/skills/screen-reader-testing/SKILL.md"
  OTHER = "plugins/agent-teams/skills/parallel-debugging/SKILL.md"

  def stub_tree(paths, url: TREE_URL)
    body = { "tree" => paths.map { |path| { "path" => path, "type" => "blob" } } +
                        [ { "path" => "README.md", "type" => "blob" } ] }
    stub_request(:get, url).to_return(status: 200, body: body.to_json)
  end

  def stub_raw(path, name:, description: "d", source: "wshobson/agents")
    stub_request(:get, "https://raw.githubusercontent.com/#{source}/HEAD/#{path}")
      .to_return(status: 200, body: "---\nname: #{name}\ndescription: #{description}\n---\n\nbody")
  end

  test "finds a skill nested under a plugin directory" do
    stub_tree([ NESTED ])
    stub_raw(NESTED, name: "screen-reader-testing", description: "Audits with a screen reader")

    content = Skills::GithubSkillTree.new.fetch("wshobson/agents", "screen-reader-testing")

    assert_includes content, "Audits with a screen reader"
  end

  # The economics of the whole approach: one request covers a publisher with hundreds of
  # skills, which is what makes describing them possible at 60 requests an hour.
  test "lists a repository once however many of its skills are asked for" do
    stub_tree([ NESTED, OTHER ])
    stub_raw(NESTED, name: "screen-reader-testing")
    stub_raw(OTHER, name: "parallel-debugging")

    tree = Skills::GithubSkillTree.new
    assert_not_nil tree.fetch("wshobson/agents", "screen-reader-testing")
    assert_not_nil tree.fetch("wshobson/agents", "parallel-debugging")

    assert_requested :get, TREE_URL, times: 1
  end

  # A read is cached under whatever skill the file turned out to hold, not under the slug
  # we hoped for — so a repository whose directory names mislead still costs one read per
  # file rather than one per (file × slug).
  test "a file read for one slug answers the slug it actually holds" do
    stub_tree([ "skills/misleading/SKILL.md" ])
    stub_raw("skills/misleading/SKILL.md", name: "actual-name")

    tree = Skills::GithubSkillTree.new
    assert_nil tree.fetch("wshobson/agents", "misleading")
    assert_not_nil tree.fetch("wshobson/agents", "actual-name")

    assert_requested :get, "https://raw.githubusercontent.com/wshobson/agents/HEAD/skills/misleading/SKILL.md",
                     times: 1
  end

  # Publishers prefix the registry name while the directory carries only the skill part
  # (`encore-database` lives at `encore/database/SKILL.md`). The frontmatter is what
  # decides; the directory only decides what to read first.
  test "matches a prefixed slug against an unprefixed directory" do
    url = "https://api.github.com/repos/encoredev/skills/git/trees/HEAD?recursive=1"
    stub_tree([ "encore/database/SKILL.md" ], url: url)
    stub_raw("encore/database/SKILL.md", name: "encore-database", source: "encoredev/skills")

    assert_not_nil Skills::GithubSkillTree.new.fetch("encoredev/skills", "encore-database")
  end

  # Plugin-namespaced slugs: `stitch::react-components` is published from
  # `plugins/stitch-build/skills/react-components/`.
  test "matches a namespaced slug against the directory holding its tail" do
    url = "https://api.github.com/repos/google-labs-code/stitch-skills/git/trees/HEAD?recursive=1"
    path = "plugins/stitch-build/skills/react-components/SKILL.md"
    stub_tree([ path ], url: url)
    stub_raw(path, name: "stitch::react-components", source: "google-labs-code/stitch-skills")

    assert_not_nil Skills::GithubSkillTree.new.fetch("google-labs-code/stitch-skills", "stitch::react-components")
  end

  # A display name where the spec wants a slug is common enough that rejecting it cost
  # real descriptions; the parameterised forms still have to match exactly.
  test "accepts a display name that parameterises to the slug" do
    stub_tree([ "skills/database-sync/SKILL.md" ])
    stub_raw("skills/database-sync/SKILL.md", name: "'Database Sync'")

    assert_not_nil Skills::GithubSkillTree.new.fetch("wshobson/agents", "database-sync")
  end

  # `vercel-labs/json-render` publishes `skills/react/SKILL.md` with `name: react`, and
  # skills.sh lists it as `json-render-react`. Insisting on an exact frontmatter match
  # left a whole publisher undescribable.
  test "accepts a publisher-prefixed slug when nothing identifies itself exactly" do
    url = "https://api.github.com/repos/vercel-labs/json-render/git/trees/HEAD?recursive=1"
    stub_tree([ "skills/react/SKILL.md" ], url: url)
    stub_raw("skills/react/SKILL.md", name: "react", description: "Renders JSON as React",
             source: "vercel-labs/json-render")

    content = Skills::GithubSkillTree.new.fetch("vercel-labs/json-render", "json-render-react")

    assert_includes content, "Renders JSON as React"
  end

  # The prefixed form is ambiguous on its own — `react` would answer to any `*-react` —
  # so a file that names itself exactly has to win even when the loose one is read first.
  test "an exact match beats a publisher-prefixed one" do
    url = "https://api.github.com/repos/vercel-labs/json-render/git/trees/HEAD?recursive=1"
    stub_tree([ "skills/react/SKILL.md", "skills/json-render-react/SKILL.md" ], url: url)
    stub_raw("skills/react/SKILL.md", name: "react", description: "The loose one",
             source: "vercel-labs/json-render")
    stub_raw("skills/json-render-react/SKILL.md", name: "json-render-react", description: "The exact one",
             source: "vercel-labs/json-render")

    content = Skills::GithubSkillTree.new.fetch("vercel-labs/json-render", "json-render-react")

    assert_includes content, "The exact one"
  end

  test "refuses a file whose frontmatter names another skill" do
    stub_tree([ NESTED ])
    stub_raw(NESTED, name: "something-else")

    assert_nil Skills::GithubSkillTree.new.fetch("wshobson/agents", "screen-reader-testing")
  end

  # Reading every path in a 200-file repository to fail one slug would spend the run's
  # whole budget on a single row.
  test "does not read paths whose directory shares nothing with the slug" do
    unrelated = %w[
      plugins/a/skills/alpha/SKILL.md plugins/b/skills/beta/SKILL.md
      plugins/c/skills/gamma/SKILL.md plugins/d/skills/delta/SKILL.md
      plugins/e/skills/epsilon/SKILL.md plugins/f/skills/zeta/SKILL.md
    ]
    stub_tree(unrelated)

    assert_nil Skills::GithubSkillTree.new.fetch("wshobson/agents", "screen-reader-testing")
    assert_not_requested :get, %r{raw\.githubusercontent\.com}
  end

  # api.github.com allows 60 requests/hour for the whole deployment, shared with the
  # install path, so a sweep has to stop counting rather than wait for the refusal.
  test "stops listing repositories once its API budget is spent" do
    stub_tree([ NESTED ])
    stub_tree([ OTHER ], url: "https://api.github.com/repos/other/repo/git/trees/HEAD?recursive=1")
    stub_raw(NESTED, name: "screen-reader-testing")

    tree = Skills::GithubSkillTree.new(api_budget: 1)
    assert_not_nil tree.fetch("wshobson/agents", "screen-reader-testing")
    assert_nil tree.fetch("other/repo", "parallel-debugging")

    assert tree.exhausted?
    assert_not_requested :get, "https://api.github.com/repos/other/repo/git/trees/HEAD?recursive=1"
  end

  # Being throttled is not "this repository has no skills": the run stops asking rather
  # than recording a miss against every remaining row.
  test "stops asking after GitHub refuses" do
    stub_request(:get, TREE_URL)
      .to_return(status: 403, body: "", headers: { "x-ratelimit-remaining" => "0" })

    tree = Skills::GithubSkillTree.new
    assert_nil tree.fetch("wshobson/agents", "screen-reader-testing")
    assert tree.exhausted?
  end

  # A 403 with quota left is a blocked repository, not a rate limit — one of those must
  # not stop the rest of the sweep.
  test "a forbidden repository does not exhaust the budget" do
    stub_request(:get, TREE_URL)
      .to_return(status: 403, body: "", headers: { "x-ratelimit-remaining" => "58" })

    tree = Skills::GithubSkillTree.new
    assert_nil tree.fetch("wshobson/agents", "screen-reader-testing")
    assert_not tree.exhausted?
  end

  test "ignores sources that are not owner/repo" do
    [ "open.feishu.cn", "owner/repo/extra", "", nil ].each do |source|
      assert_nil Skills::GithubSkillTree.new.fetch(source, "lark-doc")
    end

    assert_not_requested :get, %r{api\.github\.com}
  end

  # 60 requests/hour unauthenticated versus 5,000 with a token is the difference between
  # a couple of dozen publishers per run and the whole catalog.
  test "lists far more repositories per run when a read token is configured" do
    assert_equal Skills::GithubSkillTree::ANONYMOUS_API_BUDGET, Skills::GithubSkillTree.default_api_budget

    Settings.github.stubs(:read_token).returns("ghp_example")

    assert_equal Skills::GithubSkillTree::AUTHENTICATED_API_BUDGET, Skills::GithubSkillTree.default_api_budget
  end

  test "authenticates when a read token is configured" do
    Settings.github.stubs(:read_token).returns("ghp_example")
    stub_request(:get, TREE_URL).with(headers: { "Authorization" => "Bearer ghp_example" })
      .to_return(status: 200, body: { "tree" => [ { "path" => NESTED, "type" => "blob" } ] }.to_json)
    stub_raw(NESTED, name: "screen-reader-testing")

    assert_not_nil Skills::GithubSkillTree.new.fetch("wshobson/agents", "screen-reader-testing")
  end
end
