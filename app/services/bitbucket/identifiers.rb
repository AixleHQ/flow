# frozen_string_literal: true

module Bitbucket
  # How Bitbucket spells the identities this integration routes on.
  module Identifiers
    UUID = /\A\{?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\}?\z/i
    # Bitbucket abbreviates commits in pull requests to twelve characters, so an
    # agent's full SHA is compared by prefix — never shorter than this.
    MIN_COMMIT_PREFIX = 7

    module_function

    # The REST API writes UUIDs in braces; Forge events may not. Every stored and
    # compared UUID is the braced, lowercase form.
    def uuid(value)
      match = UUID.match(value.to_s.strip)
      match ? "{#{match[1].downcase}}" : nil
    end

    def same_commit?(one, other)
      a = one.to_s.strip.downcase
      b = other.to_s.strip.downcase
      return false if a.length < MIN_COMMIT_PREFIX || b.length < MIN_COMMIT_PREFIX

      a.start_with?(b) || b.start_with?(a)
    end
  end
end
