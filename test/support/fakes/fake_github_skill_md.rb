# frozen_string_literal: true

# Canonical fake for Skills::GithubSkillMd — the free path the catalog backfill tries
# before spending the registry's 60-per-hour download budget. Never stub
# raw.githubusercontent.com outside that service's own contract test
# (docs/testing.md R3/R4); inject this instead:
#
#   github = FakeGithubSkillMd.new
#   github.stub("obra/superpowers", "brainstorming", skill_md: "---\nname: …")
#   Skills::CatalogSync.new(client: registry, github: github, delay: 0).call
#
# Empty by default, which models the common case: most repositories do not lay their
# skills out at a path we can guess, so the backfill falls through to the registry.
class FakeGithubSkillMd
  attr_reader :requests

  def initialize
    @content = {}
    @requests = []
  end

  def stub(source, slug, skill_md:)
    @content["#{source}/#{slug}"] = skill_md
    self
  end

  def fetch(source, slug)
    @requests << "#{source}/#{slug}"
    @content["#{source}/#{slug}"]
  end
end
