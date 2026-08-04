# frozen_string_literal: true

# Canonical fake for Skills::GithubSkillTree — the second free path the catalog
# backfill tries, for repositories whose layout the flat guesses in
# Skills::GithubSkillMd cannot reach (`plugins/<plugin>/skills/<slug>/SKILL.md` and
# friends). Never stub api.github.com outside that service's own contract test
# (docs/testing.md R3/R4); inject this instead:
#
#   tree = FakeGithubSkillTree.new
#   tree.stub("wshobson/agents", "screen-reader-testing", skill_md: "---\nname: …")
#   Skills::CatalogSync.new(client: registry, github: github, tree: tree, delay: 0).call
#
# Empty by default, which models a repository we could not list — so the backfill
# falls through to the registry's download endpoint, the expensive path.
class FakeGithubSkillTree
  attr_reader :requests
  attr_accessor :exhausted

  def initialize
    @content = {}
    @requests = []
    @exhausted = false
  end

  def stub(source, slug, skill_md:)
    @content["#{source}/#{slug}"] = skill_md
    self
  end

  def fetch(source, slug)
    @requests << "#{source}/#{slug}"
    return nil if @exhausted

    @content["#{source}/#{slug}"]
  end

  def exhausted?
    @exhausted
  end
end
