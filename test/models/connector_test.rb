# frozen_string_literal: true

require "test_helper"

class ConnectorTest < ActiveSupport::TestCase
  test "requires a unique registry name" do
    create(:connector, name: "io.github.acme/server")
    duplicate = build(:connector, name: "io.github.acme/server")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "defaults to an active, latest entry" do
    connector = Connector.create!(name: "io.github.acme/fresh")

    assert_predicate connector, :active?
    assert connector.is_latest
    assert_empty connector.manifest
  end

  # ------------------------------------------------------------------ discovery

  test "discoverable hides entries the registry pulled for moderation" do
    active = create(:connector)
    deprecated = create(:connector, :deprecated)
    deleted = create(:connector, :deleted)

    discoverable = Connector.discoverable

    assert_includes discoverable, active
    assert_includes discoverable, deprecated, "deprecated still installs; it is a warning, not a removal"
    assert_not_includes discoverable, deleted
  end

  test "deleted entries are retained so existing installs keep their provenance" do
    deleted = create(:connector, :deleted)

    assert_predicate deleted, :persisted?
    assert_equal deleted, Connector.find_by(name: deleted.name)
  end

  test "discoverable hides superseded versions" do
    superseded = create(:connector, is_latest: false)

    assert_not_includes Connector.discoverable, superseded
  end

  # --------------------------------------------------------------------- search

  test "finds a connector by words in its description, which the registry API cannot do" do
    connector = create(:connector, name: "io.github.acme/tracker", title: "Acme Tracker",
                                   description: "Manage issues and bug tracking workflows")

    assert_includes Connector.search("bug tracking"), connector
  end

  test "ranks a name or title match above a description-only match" do
    named = create(:connector, name: "app.linear/linear", title: "Linear", description: "Project management")
    mentioned = create(:connector, name: "io.github.acme/other", title: "Other",
                                   description: "Syncs tasks with linear and other trackers")

    results = Connector.search("linear")

    assert_equal [ named, mentioned ], results.to_a
  end

  test "returns nothing for a blank query rather than the whole catalog" do
    create(:connector)

    assert_empty Connector.search("")
    assert_empty Connector.search("   ")
  end

  test "survives punctuation a user might type" do
    create(:connector, title: "Linear")

    assert_nothing_raised { Connector.search("linear & !( ").to_a }
  end

  test "supports quoted phrases and exclusions" do
    tracker = create(:connector, title: "Issue Tracker", description: "issue tracking for teams")
    create(:connector, title: "Chat", description: "issue tracking bot for chat rooms")

    assert_equal [ tracker ], Connector.search('"issue tracking" -chat').to_a
  end

  # --------------------------------------------------------------- installability

  test "exposes only installable targets" do
    connector = create(:connector, manifest: {
      "targets" => [
        { "kind" => "package", "supported" => false, "unsupported_reason" => "no known runtime for mcpb packages" },
        { "kind" => "remote", "supported" => true, "transport" => "http" }
      ]
    })

    assert_predicate connector, :installable?
    assert_equal [ "remote" ], connector.installable_targets.map { |t| t["kind"] }
  end

  test "an entry with no installable target is still listed" do
    connector = create(:connector, :uninstallable)

    assert_not connector.installable?
    assert_includes Connector.discoverable, connector,
                    "the UI explains why it cannot be installed rather than hiding it"
  end

  # -------------------------------------------------------------------- ranking

  # The registry publishes no popularity signal, so the only honest one is this
  # platform's own install count.
  test "popular leads with the most-installed connectors" do
    quiet = create(:connector, install_count: 0)
    busy = create(:connector, install_count: 40)
    middling = create(:connector, install_count: 3)

    assert_equal [ busy, middling, quiet ], Connector.popular.to_a
  end

  test "curated entries lead a cold catalog where every count is zero" do
    plain = create(:connector, featured: false, registry_updated_at: 1.hour.ago)
    curated = create(:connector, featured: true, registry_updated_at: 3.days.ago)

    assert_equal [ curated, plain ], Connector.popular.to_a
  end

  test "real installs outrank curation" do
    curated = create(:connector, featured: true, install_count: 0)
    installed = create(:connector, featured: false, install_count: 1)

    assert_equal [ installed, curated ], Connector.popular.to_a
  end

  test "recency breaks the remaining ties" do
    older = create(:connector, registry_updated_at: 5.days.ago)
    newer = create(:connector, registry_updated_at: 1.day.ago)

    assert_equal [ newer, older ], Connector.popular.to_a
  end

  # The registry genuinely carries several servers per product, published by
  # different people. The namespace is how it records who proved what.
  # The open registry carries namespaces that have published hundreds of servers
  # alongside vendors shipping one. Volume separates them without a blocklist.
  test "a publisher shipping at scale sinks below one shipping a single product" do
    farm = create(:connector, name: "io.github.farm/thing-42", bulk_publisher: true)
    single = create(:connector, name: "io.github.someone/thing", bulk_publisher: false)

    assert_equal [ single, farm ], Connector.popular.to_a
  end

  test "bulk publishers stay searchable and installable" do
    farm = create(:connector, name: "io.github.farm/thing", title: "Findable", bulk_publisher: true)

    assert_includes Connector.discoverable, farm
    assert_includes Connector.search("Findable"), farm
  end

  test "a vendor-verified publisher outranks a personal GitHub namespace" do
    community = create(:connector, name: "io.github.someone/linear-mcp")
    vendor = create(:connector, name: "app.linear/linear")

    assert_equal [ vendor, community ], Connector.popular.to_a
  end

  test "real installs still outrank publisher tier" do
    vendor = create(:connector, name: "app.linear/linear", install_count: 0)
    community = create(:connector, name: "io.github.someone/linear-mcp", install_count: 5)

    assert_equal [ community, vendor ], Connector.popular.to_a
  end

  test "recognises which publishers proved domain ownership" do
    assert_predicate create(:connector, name: "com.notion/mcp"), :vendor_published?
    assert_not create(:connector, name: "io.github.someone/mcp").vendor_published?
  end

  # Derived, never curated: a lookup table of logos would rot the moment the
  # registry grew.
  test "derives a github avatar for a github namespace" do
    assert_equal "https://github.com/acme.png?size=80", Connector.new(name: "io.github.acme/server").icon_url
  end

  test "derives the vendor's own favicon by reversing the namespace" do
    assert_equal "https://linear.app/favicon.ico", Connector.new(name: "app.linear/linear").icon_url
    assert_equal "https://mcp.notion.com/favicon.ico", Connector.new(name: "com.notion.mcp/server").icon_url
  end

  test "yields no icon rather than a broken one when the namespace says nothing" do
    assert_nil Connector.new(name: "singleword/server").icon_url
    assert_nil Connector.new(name: "").icon_url
  end

  test "picker name prefers the human title" do
    assert_equal "Acme", create(:connector, title: "Acme").picker_name
    assert_equal "io.github.acme/x", create(:connector, name: "io.github.acme/x", title: nil).picker_name
  end
end
