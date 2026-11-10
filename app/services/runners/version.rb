# frozen_string_literal: true

module Runners
  # A runner's version, `X-Aixle-Runner-Version` (runner/protocol/PROTOCOL.md §1):
  # strict Semantic Versioning 2.0 (https://semver.org), ordered by its precedence,
  # with build metadata ignored. The platform's pins compare against it
  # (Runners::Release).
  #
  #   Runners::Version.parse("1.4.0") < Runners::Version.parse("1.5.0-rc.1") # => true
  #   Runners::Version.parse("v1.4")                                          # => nil
  class Version
    include Comparable

    IDENTIFIER = "(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*)"
    PATTERN = /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-(#{IDENTIFIER}(?:\.#{IDENTIFIER})*))?(?:\+[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*)?\z/

    attr_reader :core, :prerelease, :to_s

    def self.parse(value)
      match = PATTERN.match(value) if value.is_a?(String)
      match && new(value, match)
    end

    def self.valid?(value) = !parse(value).nil?

    def initialize(string, match)
      @to_s = string
      @core = match.captures.first(3).map(&:to_i)
      @prerelease = match[4]&.split(".") || []
    end

    def <=>(other)
      return nil unless other.is_a?(Version)

      by_core = core <=> other.core
      return by_core unless by_core.zero?
      # A version without a pre-release ranks above the same one with it.
      return 0 if prerelease.empty? && other.prerelease.empty?
      return 1 if prerelease.empty?
      return -1 if other.prerelease.empty?

      compare_prerelease(other.prerelease)
    end

    private

    def compare_prerelease(other)
      prerelease.zip(other).each do |mine, theirs|
        return 1 if theirs.nil?

        order = compare_identifier(mine, theirs)
        return order unless order.zero?
      end
      prerelease.size <=> other.size
    end

    # Numeric identifiers by value, below every alphanumeric one; alphanumeric
    # ones in ASCII order.
    def compare_identifier(mine, theirs)
      mine_numeric = mine.match?(/\A\d+\z/)
      theirs_numeric = theirs.match?(/\A\d+\z/)
      return mine.to_i <=> theirs.to_i if mine_numeric && theirs_numeric
      return -1 if mine_numeric
      return 1 if theirs_numeric

      mine <=> theirs
    end
  end
end
