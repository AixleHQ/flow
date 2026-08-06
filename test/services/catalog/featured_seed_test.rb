# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Catalog
  # Sociable service tests on the real DB (testing doctrine R5): real models, real
  # SQL, real files. There is no network boundary here — the point of this seed is
  # that it needs none.
  class FeaturedSeedTest < ActiveSupport::TestCase
    def write_seed(dir, connectors: [], skills: [])
      dir = Pathname.new(dir)
      dir.join("connectors.json").write({ entries: connectors }.to_json)
      dir.join("skills.json").write({ entries: skills }.to_json)
      dir
    end

    # The committed files, not a fixture. A FEATURED entry added without re-running
    # `rake catalog:featured:dump` would otherwise be missing from every fresh
    # deployment, which is exactly the failure this seed exists to prevent.
    test "the committed seed covers every curated entry" do
      result = FeaturedSeed.load!

      assert_equal Connector::FEATURED.size, result.connectors
      assert_equal CatalogSkill::FEATURED.size, result.skills
      assert_equal Connector::FEATURED.sort, Connector.pluck(:name).sort
      assert_equal CatalogSkill::FEATURED.sort, CatalogSkill.pluck(:registry_id).sort
      assert_equal [ true ], Connector.distinct.pluck(:featured)
      assert_equal [ true ], CatalogSkill.distinct.pluck(:featured)
    end

    test "seeded rows are browsable and describable without a sync" do
      FeaturedSeed.load!

      assert_equal Connector::FEATURED.size, Connector.discoverable.count
      assert_equal 0, Connector.where(description: nil).count, "a seeded connector card has nothing to render"
      # Not all of them: a connector whose every target is unsupported is listed anyway
      # and the UI explains why. Most of the grid has to be actionable, though.
      assert_operator Connector.select(&:installable?).size, :>, Connector::FEATURED.size * 0.8
      assert_includes Connector.search("linear"), Connector.find_by(name: "app.linear/linear")

      skill = CatalogSkill.popular.first
      assert skill.description.present?, "a seeded skill card has nothing to render"
      refute_predicate skill, :audited?, "a security verdict must not be frozen into the repo"
    end

    # The load-bearing NULL. ConnectorCatalogSync#watermark resumes from
    # MAX(registry_updated_at), so a seed carrying real registry timestamps would make
    # the first sync ask for "everything changed since then" and permanently freeze the
    # catalog at the seeded rows.
    test "seeded connectors claim no registry timestamp, so the first sync still walks in full" do
      FeaturedSeed.load!

      assert_nil Connector.maximum(:registry_updated_at)
    end

    # Skills invert this: Skills::CatalogSync reads a NULL registry_synced_at as "no
    # sweep has ever seen this row upstream" and destroys it.
    test "seeded skills keep the provenance that saves them from the phantom-dropper" do
      FeaturedSeed.load!

      assert_equal 0, CatalogSkill.where(registry_synced_at: nil).count
    end

    test "the platform's own demand signal starts at zero" do
      FeaturedSeed.load!

      assert_equal [ 0 ], Connector.distinct.pluck(:install_count)
      assert_equal [ 0 ], CatalogSkill.distinct.pluck(:install_count)
    end

    test "loading twice inserts nothing the second time" do
      FeaturedSeed.load!

      second = FeaturedSeed.load!

      assert_equal 0, second.connectors
      assert_equal 0, second.skills
      assert_equal Connector::FEATURED.size, Connector.count
      assert_equal CatalogSkill::FEATURED.size, CatalogSkill.count
    end

    test "a synced row is never downgraded to the committed copy" do
      name = Connector::FEATURED.first
      registry_id = CatalogSkill::FEATURED.first
      synced_at = 1.day.ago
      connector = create(:connector, name: name, description: "fresh from the registry",
                         install_count: 7, registry_updated_at: synced_at)
      skill = create(:catalog_skill, registry_id: registry_id, source: registry_id.rpartition("/").first,
                     slug: registry_id.rpartition("/").last, description: "fresh from the sweep", installs: 42)

      FeaturedSeed.load!

      assert_equal "fresh from the registry", connector.reload.description
      assert_equal 7, connector.install_count
      assert_equal synced_at.to_i, connector.registry_updated_at.to_i
      assert_equal "fresh from the sweep", skill.reload.description
      assert_equal 42, skill.installs
    end

    test "an entry dropped from a FEATURED list is ignored even while it sits in the file" do
      Dir.mktmpdir do |dir|
        write_seed(dir,
                   connectors: [ { name: "io.github.nobody/dropped", title: "Dropped", status: "active",
                                   is_latest: true, manifest: { "targets" => [] } } ],
                   skills: [ { registry_id: "nobody/skills/dropped", source: "nobody/skills", slug: "dropped" } ])

        result = FeaturedSeed.load!(dir: dir)

        assert_equal 0, result.connectors
        assert_equal 0, result.skills
        assert_equal 0, Connector.count
      end
    end

    test "a missing or unreadable seed file leaves the deployment bootable" do
      Dir.mktmpdir do |dir|
        assert_equal 0, FeaturedSeed.load!(dir: dir).connectors

        Pathname.new(dir).join("connectors.json").write("{ not json")
        assert_equal 0, FeaturedSeed.load!(dir: dir).connectors
      end
    end

    test "a dump round-trips what a card needs and drops what a deployment must earn" do
      name = Connector::FEATURED.first
      registry_id = CatalogSkill::FEATURED.first
      create(:connector, :package, name: name, title: "Linear", description: "issue tracking",
             install_count: 9, registry_updated_at: 2.days.ago)
      create(:catalog_skill, registry_id: registry_id, source: registry_id.rpartition("/").first,
             slug: registry_id.rpartition("/").last, description: "writes tests", installs: 500,
             install_count: 3, audit: { "snyk" => { "risk" => "safe" } }, audit_risk: "safe")

      Dir.mktmpdir do |dir|
        FeaturedSeed.dump!(dir: dir)
        Connector.delete_all
        CatalogSkill.delete_all

        FeaturedSeed.load!(dir: dir)

        connector = Connector.sole
        assert_equal "issue tracking", connector.description
        assert_equal "npx", connector.manifest.dig("targets", 0, "runtime")
        assert_equal 0, connector.install_count
        assert_nil connector.registry_updated_at

        skill = CatalogSkill.sole
        assert_equal "writes tests", skill.description
        assert_equal 500, skill.installs
        assert_equal 0, skill.install_count
        refute_predicate skill, :audited?
      end
    end
  end
end
