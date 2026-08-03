# frozen_string_literal: true

# A search term someone typed into the skills catalog, with how often.
#
# Feeds the daily demand sweep (Skills::CatalogSync): the static seed list covers
# topics we guessed at, this covers the ones we did not. Users search for what they
# are about to install, so their terms are the best available signal for which slice
# of a 600k-skill registry is worth mirroring.
#
# NOT ATTRIBUTED, by design — see the migration. No user, project or company is
# recorded, so this cannot become a cross-tenant log of who is looking for what.
class CatalogSearchQuery < ApplicationRecord
  # Plain search shapes only. People paste all sorts of things into a search box —
  # tokens, paths, snippets, occasionally something private — and none of that
  # belongs in a global table or in an outbound query to skills.sh.
  TERM_FORMAT = /\A[\p{L}\p{N}][\p{L}\p{N} \-.+#]*\z/
  MAX_LENGTH = 64
  MIN_LENGTH = 2
  # Secret-shaped input is refused even though it satisfies TERM_FORMAT: an API key
  # pasted into a search box is exactly the thing that must not land in a global table
  # or travel to skills.sh. Real search terms are words — `node-fetch`, `next.js`,
  # `c++` — so a long unbroken alphanumeric run mixing letters and digits is the
  # signal, and a single very long word is refused outright.
  SECRET_LIKE = /[a-z0-9]{16,}/
  MAX_WORD_LENGTH = 24

  # How many terms the daily sweep follows, and how much history is worth keeping.
  # A sweep of 50 terms is ~50 requests; the cap keeps the table from growing into a
  # log rather than an index of demand.
  DEMAND_LIMIT = 50
  KEEP_TOP = 300
  STALE_AFTER = 30.days

  validates :term, presence: true, uniqueness: true, length: { maximum: MAX_LENGTH }
  validates :search_count, numericality: { greater_than_or_equal_to: 0 }

  scope :by_demand, -> { order(search_count: :desc, last_searched_at: :desc) }

  # Records one search. Called only when a search actually reached upstream (i.e. on a
  # cache miss), so a debounced field cannot turn one person's typing into a write per
  # keystroke.
  #
  # Returns nil for anything that is not a plain search term, rather than storing it.
  def self.record(term)
    term = normalize(term)
    return nil if term.blank?

    now = Time.current
    # Upsert-with-increment: two people searching the same term concurrently must not
    # lose a count or raise on the unique index.
    upsert_all(
      [ { term: term, search_count: 1, last_searched_at: now, created_at: now, updated_at: now } ],
      unique_by: :term,
      on_duplicate: Arel.sql(
        "search_count = catalog_search_queries.search_count + 1, " \
        "last_searched_at = excluded.last_searched_at, updated_at = excluded.updated_at"
      )
    )
    term
  end

  def self.normalize(term)
    term = term.to_s.unicode_normalize(:nfkc).strip.squish.downcase
    return nil if term.length < MIN_LENGTH || term.length > MAX_LENGTH
    return nil unless term.match?(TERM_FORMAT)
    return nil if secret_like?(term)

    term
  end

  def self.secret_like?(term)
    segments = term.split(/[\s\-.+#]+/)
    return true if segments.any? { |segment| segment.length > MAX_WORD_LENGTH }

    segments.any? do |segment|
      segment.match?(SECRET_LIKE) && segment.match?(/[a-z]/) && segment.match?(/\d/)
    end
  end

  def self.top_terms(limit = DEMAND_LIMIT)
    by_demand.limit(limit).pluck(:term)
  end

  # Keeps the table an index of demand rather than an ever-growing log: drops terms
  # nobody has searched in a month, then anything past the top N.
  def self.prune!(keep: KEEP_TOP, stale_after: STALE_AFTER)
    where(last_searched_at: ...stale_after.ago).delete_all

    survivors = by_demand.limit(keep).pluck(:id)
    where.not(id: survivors).delete_all if survivors.any?
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[term search_count last_searched_at created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end
end
