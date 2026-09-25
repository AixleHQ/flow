# frozen_string_literal: true

# A model whose explicit saves are recorded as EntityVersions. Including it does
# not record anything by itself: versions are written by Versions.save! and its
# siblings, never by a callback — the same rule app/models/audit.rb follows.
#
# The including model also answers the archive interface Versions relies on:
# `archived?`, `archive!` and `unarchive!`.
module Versioned
  extend ActiveSupport::Concern

  included do
    has_many :entity_versions, -> { order(number: :desc) }, as: :versionable, inverse_of: :versionable
  end

  def latest_version
    entity_versions.first
  end
end
