# frozen_string_literal: true

require "test_helper"

module Skills
  # The one place both catalog surfaces (skills page, personal-MCP search tool) get
  # their entries from, so the rules live here rather than in each caller: what
  # reaches upstream, what falls back to the mirror, and what must never be written.
  class CatalogSearchTest < ActiveSupport::TestCase
    test "a query too short for the upstream endpoint browses the mirror instead" do
      create(:catalog_skill, registry_id: "org/skills/fmt", source: "org/skills", slug: "fmt")
      RegistryClient.expects(:search).never

      entries = CatalogSearch.call("a")

      assert_equal [ "org/skills/fmt" ], entries.map(&:registry_id)
      assert_not CatalogSearch.new("a").reaches_upstream?
    end

    test "the default view shows one entry per publisher" do
      create(:catalog_skill, source: "org/collection", slug: "one", installs: 5)
      create(:catalog_skill, source: "org/collection", slug: "two", installs: 4)
      create(:catalog_skill, source: "other/repo", slug: "solo", installs: 1)

      sources = CatalogSearch.call("").map(&:source)

      assert_equal sources, sources.uniq
      assert_includes sources, "org/collection"
      assert_includes sources, "other/repo"
    end

    test "upstream hits keep upstream order and reuse mirrored rows without persisting" do
      create(:catalog_skill, registry_id: "org/skills/mirrored", source: "org/skills", slug: "mirrored",
                             description: "Already mirrored", audit_risk: "low")
      RegistryClient.stubs(:search).returns([
                                              entry("org/skills/exact", "exact", installs: 10),
                                              entry("org/skills/mirrored", "mirrored", installs: 900_000)
                                            ])

      entries = assert_no_difference -> { CatalogSkill.count } do
        CatalogSearch.call("exact")
      end

      assert_equal %w[org/skills/exact org/skills/mirrored], entries.map(&:registry_id)
      # The mirrored row carries what the search payload cannot: description and verdict.
      assert_equal "Already mirrored", entries.last.description
      assert_equal "low", entries.last.audit_risk
      # The unmirrored hit is returned unsaved — a read must not write to a table
      # shared by every tenant.
      assert entries.first.new_record?
    end

    test "an id with no slash falls back to the entry's own source and slug" do
      RegistryClient.stubs(:search).returns([
                                              RegistryClient::Entry.new(id: "flat", slug: "flat", name: "Flat",
                                                                        source: "org/skills", installs: 0)
                                            ])

      transient = CatalogSearch.call("flat").sole

      assert_equal "org/skills", transient.source
      assert_equal "flat", transient.slug
    end

    test "an empty upstream answer falls back to full-text over the mirror" do
      create(:catalog_skill, registry_id: "org/skills/playwright-helper", source: "org/skills",
                             slug: "playwright-helper", description: "Drives playwright")
      RegistryClient.stubs(:search).returns([])

      entries = CatalogSearch.call("playwright")

      assert_equal [ "org/skills/playwright-helper" ], entries.map(&:registry_id)
    end

    test "a term that reached upstream is recorded, and a too-short one is not" do
      RegistryClient.stubs(:search).returns([])

      assert_difference -> { CatalogSearchQuery.count }, 1 do
        CatalogSearch.call("playwright")
      end
      assert_equal "playwright", CatalogSearchQuery.sole.term

      assert_no_difference -> { CatalogSearchQuery.count } do
        CatalogSearch.call("a")
        CatalogSearch.call("")
      end
    end

    private

    def entry(id, slug, installs:)
      RegistryClient::Entry.new(id: id, slug: slug, name: slug, source: id.split("/")[0..-2].join("/"),
                                installs: installs)
    end
  end
end
