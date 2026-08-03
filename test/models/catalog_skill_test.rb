# frozen_string_literal: true

require "test_helper"

class CatalogSkillTest < ActiveSupport::TestCase
  # ====== Ranking ======

  # The measured failure this ordering exists to prevent: raw `installs DESC` puts
  # fifteen `larksuite/cli/lark-*` entries in the top twenty-five, because a
  # repo-level install appears to credit every skill in the repo.
  test "a bulk publisher with huge install counts ranks below a single-product repo" do
    bulk = create(:catalog_skill, :bulk, source: "larksuite/cli", slug: "lark-doc",
                  registry_id: "larksuite/cli/lark-doc", installs: 518_503)
    single = create(:catalog_skill, source: "obra/superpowers", slug: "test-driven-development",
                    registry_id: "obra/superpowers/test-driven-development", installs: 188_213)

    assert_equal [ single.id, bulk.id ], CatalogSkill.popular.pluck(:id)
  end

  test "curated entries lead the default view" do
    popular_but_unfeatured = create(:catalog_skill, source: "org/a", slug: "a", registry_id: "org/a/a",
                                    installs: 900_000)
    featured = create(:catalog_skill, :featured, source: "org/b", slug: "b", registry_id: "org/b/b", installs: 10)

    assert_equal [ featured.id, popular_but_unfeatured.id ], CatalogSkill.popular.pluck(:id)
  end

  test "our own install count breaks ties upstream cannot" do
    quiet = create(:catalog_skill, source: "org/a", slug: "a", registry_id: "org/a/a", installs: 100,
                   install_count: 0)
    used_here = create(:catalog_skill, source: "org/b", slug: "b", registry_id: "org/b/b", installs: 100,
                       install_count: 4)

    assert_equal [ used_here.id, quiet.id ], CatalogSkill.popular.pluck(:id)
  end

  # Ordering alone still lets one publisher fill the grid — the penalty ranks
  # publishers, it does not thin them out.
  test "one_per_source keeps a single best entry per publisher" do
    create(:catalog_skill, source: "acme/skills", slug: "one", registry_id: "acme/skills/one", installs: 10)
    best = create(:catalog_skill, source: "acme/skills", slug: "two", registry_id: "acme/skills/two", installs: 500)
    other = create(:catalog_skill, source: "other/skills", slug: "three", registry_id: "other/skills/three",
                   installs: 50)

    ids = CatalogSkill.one_per_source.popular.pluck(:id)

    assert_equal 2, ids.size
    assert_equal [ best.id, other.id ], ids
  end

  # ====== Search ======

  test "search matches slug, title and description" do
    slug_match = create(:catalog_skill, slug: "playwright-cli", registry_id: "microsoft/playwright-cli/playwright-cli",
                        source: "microsoft/playwright-cli", description: "Drive a browser")
    description_match = create(:catalog_skill, slug: "e2e-runner", registry_id: "org/skills/e2e-runner",
                               source: "org/skills", description: "Runs playwright suites")
    create(:catalog_skill, slug: "unrelated", registry_id: "org/skills/unrelated", source: "org/skills",
           description: "Nothing to do with browsers")

    ids = CatalogSkill.search("playwright").pluck(:id)

    assert_includes ids, slug_match.id
    assert_includes ids, description_match.id
    assert_equal 2, ids.size
  end

  test "search returns nothing for a blank query" do
    create(:catalog_skill)

    assert_empty CatalogSkill.search("")
    assert_empty CatalogSkill.search(nil)
  end

  # `websearch_to_tsquery` accepts what people type instead of raising the way
  # `to_tsquery` does.
  test "search survives punctuation a user might type" do
    create(:catalog_skill, slug: "pdf", registry_id: "anthropics/skills/pdf", source: "anthropics/skills",
           description: "Fill PDF forms")

    assert_nothing_raised { CatalogSkill.search("pdf & !").to_a }
    assert_nothing_raised { CatalogSkill.search('"pdf forms"').to_a }
  end

  # ====== Derived attributes ======

  test "icon_url is derived from the GitHub owner" do
    skill = build(:catalog_skill, source: "anthropics/skills", slug: "pdf", registry_id: "anthropics/skills/pdf")

    assert_equal "https://github.com/anthropics.png?size=80", skill.icon_url
  end

  test "package matches the identifier an installed skill carries" do
    skill = build(:catalog_skill, source: "anthropics/skills", slug: "pdf", registry_id: "anthropics/skills/pdf")

    assert_equal "anthropics/skills@pdf", skill.package
  end

  test "picker_name prefers the human title" do
    assert_equal "PDF Processing", build(:catalog_skill, slug: "pdf", title: "PDF Processing").picker_name
    assert_equal "pdf", build(:catalog_skill, slug: "pdf", title: nil).picker_name
  end

  # ====== Audits ======

  test "worst_risk picks the most severe provider verdict" do
    audit = {
      "socket" => { "risk" => "safe" },
      "snyk" => { "risk" => "high" },
      "ath" => { "risk" => "low" }
    }

    assert_equal "high", CatalogSkill.worst_risk(audit)
  end

  # "unknown" is a provider saying it could not tell; it must not outrank a real
  # verdict, but "we looked and cannot say" is still a different state from nobody
  # having looked at all.
  test "worst_risk ignores unknown when a real verdict exists" do
    assert_equal "low", CatalogSkill.worst_risk({ "a" => { "risk" => "unknown" }, "b" => { "risk" => "low" } })
  end

  test "worst_risk keeps unknown when every provider shrugged" do
    assert_equal "unknown", CatalogSkill.worst_risk({ "a" => { "risk" => "unknown" }, "b" => { "risk" => "unknown" } })
  end

  # A provider inventing a label must not silently become "nobody audited this":
  # under-reporting a flag is the more dangerous failure.
  test "worst_risk treats an unrecognised label as the worst known verdict" do
    assert_equal "moderate", CatalogSkill.worst_risk({ "a" => { "risk" => "moderate" }, "b" => { "risk" => "low" } })
    assert build(:catalog_skill, audit_risk: "moderate").audit_warning?
  end

  # The payload is third-party JSON. A provider value that is not an object, or a
  # bare string where an object belongs, must not raise inside a sweep or a render.
  test "audit helpers survive malformed payloads" do
    [
      { "snyk" => [ "high" ] },
      { "snyk" => "safe" },
      { "snyk" => 3 },
      { "snyk" => nil },
      "safe",
      [],
      nil
    ].each do |payload|
      assert_nothing_raised { CatalogSkill.worst_risk(payload) }
      assert_nothing_raised { build(:catalog_skill, audit: payload).audit_providers }
    end
  end

  test "audit_providers skips malformed provider entries but keeps valid ones" do
    skill = build(:catalog_skill, audit: { "broken" => "safe", "socket" => { "risk" => "low" } })

    assert_equal %w[socket], skill.audit_providers.map { |p| p[:provider] }
  end

  test "an inconclusive audit does not warn" do
    skill = build(:catalog_skill, audit_risk: "unknown", audit: { "a" => { "risk" => "unknown" } })

    assert skill.audited?
    assert_not skill.audit_warning?
  end

  test "worst_risk is nil when nothing was audited" do
    assert_nil CatalogSkill.worst_risk({})
    assert_nil CatalogSkill.worst_risk(nil)
  end

  # Nobody looking is not the same as nothing found.
  test "an unaudited skill is not treated as audited" do
    skill = build(:catalog_skill, audit: {}, audit_risk: nil)

    assert_not skill.audited?
    assert_not skill.audit_warning?
  end

  test "audit_providers lists every provider worst first" do
    skill = build(:catalog_skill, audit: {
      "socket" => { "risk" => "safe", "score" => 90, "alerts" => 0, "analyzedAt" => "2026-03-18T16:47:53Z" },
      "snyk" => { "risk" => "critical", "analyzedAt" => "2026-02-17T22:15:27Z" }
    })

    providers = skill.audit_providers

    assert_equal %w[snyk socket], providers.map { |p| p[:provider] }
    assert_equal 90, providers.last[:score]
    assert_equal "2026-02-17T22:15:27Z", providers.first[:analyzed_at]
  end

  test "registry_id must be unique" do
    create(:catalog_skill, registry_id: "org/skills/dup", source: "org/skills", slug: "dup")
    duplicate = build(:catalog_skill, registry_id: "org/skills/dup", source: "org/skills", slug: "dup")

    assert_not duplicate.valid?
  end
end
