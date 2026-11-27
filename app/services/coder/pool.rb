# frozen_string_literal: true

module Coder
  # Which workspaces belong to an integration's pool, and what a machine prefix may be
  # (docs/design/session-integrations.md §4.1, §4.2).
  #
  # A workspace belongs to the pool of prefix `aixle` when its name is `<prefix>-<suffix>` and
  # the suffix is one segment of [0-9a-z] with no hyphen. So `aixle` does not take
  # `aixle-r-1a2b3c4d`, which belongs to the pool `aixle-r`, while a prefix that nests inside
  # another pool's no longer shares its machines. The match ignores case: Coder treats a
  # workspace name as case-insensitive.
  module Pool
    # Coder limits a workspace name to 32 characters. A generated name is `<prefix>-<8 hex>`.
    NAME_LIMIT = 32
    SUFFIX_LENGTH = 8
    MAX_PREFIX_LENGTH = NAME_LIMIT - SUFFIX_LENGTH - 1
    PREFIX_FORMAT = /\A[0-9a-z]+(-[0-9a-z]+)*\z/

    module_function

    def matches?(prefix, name)
      prefix = prefix.to_s.downcase
      return true if prefix.blank?

      /\A#{Regexp.escape(prefix)}-[0-9a-z]+\z/.match?(name.to_s.downcase)
    end

    # Whether the prefix may be stored: lowercase [0-9a-z-], no leading or trailing hyphen,
    # at most MAX_PREFIX_LENGTH characters, not blank.
    def valid_prefix?(prefix)
      prefix = prefix.to_s
      prefix.length <= MAX_PREFIX_LENGTH && PREFIX_FORMAT.match?(prefix)
    end

    # The prefix the connect form starts from, made out of a project's or a company's name.
    def suggest_prefix(name)
      name.to_s.downcase.gsub(/[^0-9a-z]+/, "-").gsub(/\A-+|-+\z/, "").first(MAX_PREFIX_LENGTH).delete_suffix("-")
    end

    def generate_name(prefix)
      "#{prefix.presence || 'aixle'}-#{SecureRandom.hex(SUFFIX_LENGTH / 2)}"
    end
  end
end
