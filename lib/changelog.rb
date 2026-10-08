# frozen_string_literal: true

# CHANGELOG.md in Keep a Changelog form: a preamble, `## [Unreleased]`, then
# `## [X.Y.Z] - YYYY-MM-DD` sections newest first, then the link references.
#
# Plain Ruby with no gems: the release workflow runs it on a bare runner.
class Changelog
  REPOSITORY = "https://github.com/AixleHQ/flow"
  VERSION = /\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\z/
  LINKS = /(?:^\[[^\]]+\]: \S+\n?)+\z/

  Error = Class.new(StandardError)

  attr_reader :text

  def initialize(text)
    @text = text
  end

  def notes(version)
    heading = "## [#{version}]"
    section = sections.find { |title, _| title == heading || title.start_with?("#{heading} ") }
    raise Error, "CHANGELOG.md has no #{heading} section" unless section

    section.last.strip
  end

  def released_versions
    sections.filter_map { |title, _| title[/\A## \[(\d[^\]]*)\]/, 1] }
  end

  # Moves everything under [Unreleased] into a dated section and points the
  # link references at the new tag.
  def release(version, date:)
    raise Error, "#{version} is not a SemVer version" unless version.match?(VERSION)
    raise Error, "CHANGELOG.md already has a [#{version}] section" if released_versions.include?(version)
    raise Error, "[Unreleased] is empty: nothing to release" if notes("Unreleased").empty?

    previous = released_versions.first
    body = text.sub(LINKS, "").sub("## [Unreleased]\n", "## [Unreleased]\n\n## [#{version}] - #{date}\n")
    "#{body.rstrip}\n\n#{links(version, previous)}"
  end

  private

  def sections
    text.sub(LINKS, "").split(/^(?=## )/).drop(1).map { |chunk| chunk.split("\n", 2).then { |title, rest| [ title, rest.to_s ] } }
  end

  def links(version, previous)
    kept = text[LINKS].to_s.lines.reject { |line| line.start_with?("[Unreleased]:") }
    since = previous ? "#{REPOSITORY}/compare/v#{previous}...v#{version}" : "#{REPOSITORY}/releases/tag/v#{version}"

    [ "[Unreleased]: #{REPOSITORY}/compare/v#{version}...develop\n", "[#{version}]: #{since}\n", *kept ].join
  end
end
