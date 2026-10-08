# frozen_string_literal: true

require "test_helper"

class ChangelogTest < ActiveSupport::TestCase
  BEFORE_FIRST_RELEASE = <<~MD
    # Changelog

    Preamble.

    ## [Unreleased]

    ### Added
    - **Workflows**: version history.

    ### Fixed
    - A fix.

    [Unreleased]: https://github.com/AixleHQ/flow/commits/develop
  MD

  test "the first release takes everything unreleased and links to its tag" do
    released = Changelog.new(BEFORE_FIRST_RELEASE).release("1.0.0", date: "2026-10-08")

    assert_equal <<~MD, released
      # Changelog

      Preamble.

      ## [Unreleased]

      ## [1.0.0] - 2026-10-08

      ### Added
      - **Workflows**: version history.

      ### Fixed
      - A fix.

      [Unreleased]: https://github.com/AixleHQ/flow/compare/v1.0.0...develop
      [1.0.0]: https://github.com/AixleHQ/flow/releases/tag/v1.0.0
    MD
  end

  test "a later release compares with the previous one and keeps the older links" do
    first = Changelog.new(BEFORE_FIRST_RELEASE).release("1.0.0", date: "2026-10-08")
    with_unreleased = first.sub("## [Unreleased]\n", "## [Unreleased]\n\n### Fixed\n- Another fix.\n")

    second = Changelog.new(with_unreleased).release("1.0.1", date: "2026-10-09")

    assert_equal "### Fixed\n- Another fix.", Changelog.new(second).notes("1.0.1")
    assert_equal %w[1.0.1 1.0.0], Changelog.new(second).released_versions
    assert second.end_with?(<<~MD)
      [Unreleased]: https://github.com/AixleHQ/flow/compare/v1.0.1...develop
      [1.0.1]: https://github.com/AixleHQ/flow/compare/v1.0.0...v1.0.1
      [1.0.0]: https://github.com/AixleHQ/flow/releases/tag/v1.0.0
    MD
  end

  test "notes are a release's section without its heading or the link references" do
    released = Changelog.new(BEFORE_FIRST_RELEASE).release("1.0.0", date: "2026-10-08")

    assert_equal "### Added\n- **Workflows**: version history.\n\n### Fixed\n- A fix.",
                 Changelog.new(released).notes("1.0.0")
  end

  test "refuses a release that is not SemVer, already exists, or has nothing in it" do
    changelog = Changelog.new(BEFORE_FIRST_RELEASE)
    released = Changelog.new(changelog.release("1.0.0", date: "2026-10-08"))

    assert_match(/not a SemVer/, assert_raises(Changelog::Error) { changelog.release("v1.0", date: "2026-10-08") }.message)
    assert_match(/already has/, assert_raises(Changelog::Error) { released.release("1.0.0", date: "2026-10-09") }.message)
    assert_match(/empty/, assert_raises(Changelog::Error) { released.release("1.0.1", date: "2026-10-09") }.message)
    assert_match(/no ## \[2.0.0\]/, assert_raises(Changelog::Error) { released.notes("2.0.0") }.message)
  end

  test "releases are the non-empty sections, with each entry split from its product area" do
    released = Changelog.new(<<~MD).releases
      # Changelog

      ## [Unreleased]

      ## [1.0.0] - 2026-10-08

      The first tagged release.

      ### Added
      - **Workflows**: version history, kept
        for every save.
      - Apache License 2.0.

      ### Removed
      For deployments that ran a build from before this release:
      - `RAILS_PORT`.

      [Unreleased]: https://github.com/AixleHQ/flow/compare/v1.0.0...develop
      [1.0.0]: https://github.com/AixleHQ/flow/releases/tag/v1.0.0
    MD

    assert_equal [ {
      version: "1.0.0",
      date: "2026-10-08",
      url: "https://github.com/AixleHQ/flow/releases/tag/v1.0.0",
      summary: "The first tagged release.",
      changes: [
        { kind: "Added", note: nil, entries: [
          { area: "Workflows", text: "version history, kept for every save." },
          { area: nil, text: "Apache License 2.0." }
        ] },
        { kind: "Removed", note: "For deployments that ran a build from before this release:",
          entries: [ { area: nil, text: "`RAILS_PORT`." } ] }
      ]
    } ], released
  end

  test "unreleased changes are listed first, without a date" do
    unreleased = Changelog.new(BEFORE_FIRST_RELEASE).releases.first

    assert_equal "Unreleased", unreleased[:version]
    assert_nil unreleased[:date]
    assert_equal %w[Added Fixed], unreleased[:changes].pluck(:kind)
  end

  test "every product area an entry names is one the changelog taxonomy defines" do
    areas = Rails.root.join("docs/product/changelog-product-areas.md").read.scan(/^\| \*\*([^*]+)\*\* \|/).flatten
    named = Rails.root.join("CHANGELOG.md").read.scan(/^- \*\*([^*]+)\*\*:/).flatten.uniq

    assert_empty named - areas, "add the area to docs/product/changelog-product-areas.md, or use one it defines"
  end

  test "the repository's changelog parses" do
    changelog = Changelog.new(Rails.root.join("CHANGELOG.md").read)

    assert_kind_of String, changelog.notes("Unreleased")
    changelog.released_versions.each { |version| assert_match Changelog::VERSION, version }
    assert_includes changelog.releases.pluck(:version), changelog.released_versions.first
  end
end
