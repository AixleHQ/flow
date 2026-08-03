# frozen_string_literal: true

require "test_helper"

# Driven through FakeSkillsRegistry, never through HTTP: the client's own contract
# test pins the wire shapes, so this file is free to be about the sweep's behaviour
# (idempotency, ranking recomputation, partial failure).
class Skills::CatalogSyncTest < ActiveSupport::TestCase
  setup do
    @registry = FakeSkillsRegistry.new
  end

  def sync(client: @registry)
    Skills::CatalogSync.new(client: client, delay: 0).call
  end

  test "mirrors swept entries" do
    @registry.add("microsoft/playwright-cli/playwright-cli", installs: 12_000)

    result = sync

    row = CatalogSkill.find_by(registry_id: "microsoft/playwright-cli/playwright-cli")
    assert_not_nil row
    assert_equal "microsoft/playwright-cli", row.source
    assert_equal "playwright-cli", row.slug
    assert_equal 12_000, row.installs
    assert_not_nil row.registry_synced_at
    assert result.upserted.positive?
  end

  # The sweep only knows what search returns, so re-running it must be additive.
  # Otherwise every weekly run undoes the metadata backfill and the catalog slowly
  # decays back to bare slugs.
  test "a re-sweep never undoes backfilled metadata" do
    @registry.add("org/skills/testing-helper", installs: 500)
    @registry.bundle("org/skills", "testing-helper",
                     skill_md: "---\nname: Testing Helper\ndescription: Helps with tests\n---\n\nbody")
    sync

    row = CatalogSkill.find_by(registry_id: "org/skills/testing-helper")
    assert_equal "Testing Helper", row.title
    assert_equal "Helps with tests", row.description

    sync

    row.reload
    assert_equal "Testing Helper", row.title, "second sweep wiped the backfilled title"
    assert_equal "Helps with tests", row.description
  end

  # Search has been seen omitting installs for an entry it previously reported.
  test "a re-sweep never replaces a real install count with zero" do
    @registry.add("org/skills/popular", installs: 734_415)
    sync
    assert_equal 734_415, CatalogSkill.find_by(registry_id: "org/skills/popular").installs

    @registry = FakeSkillsRegistry.new
    @registry.add("org/skills/popular", installs: 0)
    sync

    assert_equal 734_415, CatalogSkill.find_by(registry_id: "org/skills/popular").installs
  end

  # A missed week, a doubled run and a first run all have to converge.
  test "is idempotent across runs" do
    @registry.add("org/skills/testing-helper", installs: 10)

    sync
    assert_equal 1, CatalogSkill.where(registry_id: "org/skills/testing-helper").count

    @registry.add("org/skills/testing-helper", installs: 99)
    sync

    assert_equal 1, CatalogSkill.where(registry_id: "org/skills/testing-helper").count
    assert_equal 99, CatalogSkill.find_by(registry_id: "org/skills/testing-helper").installs
  end

  # The default view must not be empty just because no seed query happened to reach a
  # curated entry — but a seed that turns out not to be installable is cleaned up
  # again rather than left as a card that fails on click (see the drop/keep tests
  # below).
  test "seeds a curated entry and marks it featured when it resolves" do
    seeded = CatalogSkill::FEATURED.first
    source, slug = seeded.split("/")[0..-2].join("/"), seeded.split("/").last
    @registry.bundle(source, slug, skill_md: "---\nname: #{slug}\ndescription: Curated pick\n---\n\nbody")

    sync

    row = CatalogSkill.find_by(registry_id: seeded)
    assert_not_nil row, "a resolvable curated seed must survive the sweep"
    assert row.featured?
    assert_equal "Curated pick", row.description
  end

  test "a swept entry keeps its install count when the featured seed covers it" do
    seeded = CatalogSkill::FEATURED.first
    @registry.add(seeded, installs: 734_415)

    sync

    assert_equal 734_415, CatalogSkill.find_by(registry_id: seeded).installs
  end

  test "clears the featured flag on rows no longer curated" do
    stale = create(:catalog_skill, :featured, registry_id: "org/skills/was-featured", source: "org/skills",
                   slug: "was-featured")

    sync

    assert_not stale.reload.featured?
  end

  test "counts installs on this platform" do
    company = create(:company)
    user = create(:user, company: company)
    project = create(:project, company: company, owner: user)
    create(:skill, scope: project, name: "playwright-cli", source: "microsoft/playwright-cli",
           package: "microsoft/playwright-cli@playwright-cli")
    @registry.add("microsoft/playwright-cli/playwright-cli", installs: 12_000)

    sync

    assert_equal 1, CatalogSkill.find_by(registry_id: "microsoft/playwright-cli/playwright-cli").install_count
  end

  test "flags sources publishing at scale" do
    (CatalogSkill::BULK_PUBLISHER_THRESHOLD + 1).times do |i|
      @registry.add("larksuite/cli/lark-#{i}", installs: 395_000)
    end
    @registry.add("obra/superpowers/test-driven-development", installs: 188_000)

    sync

    assert CatalogSkill.find_by(registry_id: "larksuite/cli/lark-0").bulk_publisher?
    assert_not CatalogSkill.find_by(registry_id: "obra/superpowers/test-driven-development").bulk_publisher?
  end

  # The search endpoint carries no description, and a description is what tells an
  # agent when to use a skill — so it is backfilled from the download endpoint.
  test "backfills descriptions from the download endpoint" do
    @registry.add("org/skills/described", installs: 5)
    @registry.bundle("org/skills", "described",
                     skill_md: "---\nname: described\ndescription: Does a specific thing\n---\n\nbody")

    result = sync

    row = CatalogSkill.find_by(registry_id: "org/skills/described")
    assert_equal "Does a specific thing", row.description
    assert_equal "sha256:fake", row.content_hash
    assert result.backfilled.positive?
  end

  test "a failing upsert is counted without abandoning the sweep" do
    @registry.add("org/skills/one", installs: 1)
    Skills::CatalogUpsert.stubs(:call).raises(ActiveRecord::StatementInvalid, "boom")

    result = sync

    assert result.failed.positive?
    assert_equal 0, result.upserted
    # The run still completes: seeding, ranking and the metadata pass all execute
    # after a failed batch rather than the sweep aborting.
    assert_not_nil result.backfilled
  end

  # One poisoned row must not cost the other 199 on the page — every run, forever.
  test "a bad row is retried individually so the rest of the page still lands" do
    @registry.add("org/skills/good-one", installs: 5)
    @registry.add("org/skills/poison", installs: 5)
    @registry.add("org/skills/good-two", installs: 5)

    # Fail any multi-row batch, and fail the poisoned row again on its individual
    # retry; single valid rows go through.
    Skills::CatalogUpsert.stubs(:call).with do |entries|
      entries = Array(entries)
      poisoned = entries.any? { |entry| entry.id.to_s.include?("poison") }
      raise ActiveRecord::StatementInvalid, "boom" if entries.size > 1 || poisoned

      true
    end.returns([ "written" ])

    result = sync

    assert result.upserted.positive?, "valid rows should still be written after a batch failure"
    assert result.failed.positive?, "the poisoned row should be counted as failed"
  end

  # A verdict that upstream withdrew must not keep showing as a red badge forever.
  test "clears a stale verdict when the endpoint no longer reports the skill" do
    row = create(:catalog_skill, registry_id: "org/skills/was-flagged", source: "org/skills", slug: "was-flagged",
                 audit: { "snyk" => { "risk" => "critical" } }, audit_risk: "critical", audited_at: 1.week.ago)
    # The source answers (another slug is present), but this skill is gone from it.
    @registry.add("org/skills/other", installs: 1)
    @registry.audit("org/skills", "other", risk: "safe")

    sync

    row.reload
    assert_nil row.audit_risk
    assert_empty row.audit
    assert_nil row.audited_at
  end

  # An unreachable endpoint is not evidence that a verdict was withdrawn.
  test "keeps existing verdicts when the audit lookup fails" do
    row = create(:catalog_skill, registry_id: "org/skills/flagged", source: "org/skills", slug: "flagged",
                 audit: { "snyk" => { "risk" => "high" } }, audit_risk: "high", audited_at: 1.week.ago)

    sync

    assert_equal "high", row.reload.audit_risk
  end

  # A curated pick the registry cannot resolve is a card that fails on click, at the
  # top of every project's default view.
  test "drops a featured seed the registry cannot resolve" do
    seeded = CatalogSkill::FEATURED.first

    sync

    assert_nil CatalogSkill.find_by(registry_id: seeded),
               "an unresolvable seed should not survive as a permanent broken card"
  end

  test "keeps a seed the sweep actually saw upstream even if its download failed" do
    seeded = CatalogSkill::FEATURED.first
    @registry.add(seeded, installs: 10)

    sync

    assert_not_nil CatalogSkill.find_by(registry_id: seeded)
  end

  # Without rotation, rows whose SKILL.md legitimately has no description hold the
  # whole backfill budget on every run and nothing else is ever reached.
  test "backfill rotates rather than re-fetching the same descriptionless rows" do
    @registry.add("org/skills/no-description", installs: 5)
    @registry.bundle("org/skills", "no-description", skill_md: "---\nname: no-description\n---\n\nbody")

    sync
    first_pass = @registry.downloads.count { |d| d == "org/skills/no-description" }
    row = CatalogSkill.find_by(registry_id: "org/skills/no-description")
    assert_nil row.description
    assert_not_nil row.registry_synced_at, "an attempt must be stamped so the queue moves on"
    assert_equal 1, first_pass

    # It stays eligible (still no description) but is no longer at the front of the
    # queue, and the counter did not claim success.
    result = sync
    assert_equal 0, result.backfilled
  end

  # The only external judgement available for a catalog with no ownership proof.
  test "stores third-party audits, keeping the worst verdict as the headline" do
    @registry.add("anthropics/skills/pdf", installs: 100)
    @registry.audit("anthropics/skills", "pdf", provider: "socket", risk: "safe", score: 90, alerts: 0)
    @registry.audit("anthropics/skills", "pdf", provider: "snyk", risk: "high")

    result = sync

    row = CatalogSkill.find_by(registry_id: "anthropics/skills/pdf")
    assert_equal "high", row.audit_risk
    assert row.audit_warning?
    assert_equal %w[snyk socket], row.audit_providers.map { |p| p[:provider] }.sort
    assert_not_nil row.audited_at
    assert result.audited.positive?
  end

  test "leaves audit_risk null when nobody audited a skill" do
    @registry.add("org/skills/unaudited", installs: 1)

    sync

    row = CatalogSkill.find_by(registry_id: "org/skills/unaudited")
    assert_nil row.audit_risk
    assert_not row.audited?
    assert_empty row.audit
  end

  test "asks for audits one repository at a time" do
    @registry.add("anthropics/skills/pdf")
    @registry.add("anthropics/skills/docx")
    @registry.add("obra/superpowers/tdd")

    sync

    # One request per repository, carrying that repository's slugs — including the
    # curated seed entries the sweep also mirrored for the same source.
    requested = @registry.audit_requests.to_h { |req| [ req[:source], req[:slugs].sort ] }
    assert_includes requested["anthropics/skills"], "pdf"
    assert_includes requested["anthropics/skills"], "docx"
    assert_includes requested["obra/superpowers"], "tdd"
    assert_equal 1, @registry.audit_requests.count { |req| req[:source] == "anthropics/skills" }
  end

  test "sweeps every seed query and owner" do
    result = sync

    queries = @registry.searches.reject { |s| s[:owner] }
    owners = @registry.searches.select { |s| s[:owner] }
    assert_equal Skills::CatalogSync::SEED_QUERIES.size, queries.size
    assert_equal Skills::CatalogSync::SEED_OWNERS.size, owners.size
    assert_equal 0, result.failed
  end
end
