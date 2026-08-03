# frozen_string_literal: true

require "test_helper"

class CatalogSearchQueryTest < ActiveSupport::TestCase
  test "records a term and counts repeats" do
    assert_equal "playwright", CatalogSearchQuery.record("playwright")
    CatalogSearchQuery.record("playwright")

    row = CatalogSearchQuery.sole
    assert_equal "playwright", row.term
    assert_equal 2, row.search_count
    assert_not_nil row.last_searched_at
  end

  test "normalises case and whitespace so one term is one row" do
    CatalogSearchQuery.record("  Playwright   Testing ")
    CatalogSearchQuery.record("playwright testing")

    assert_equal 1, CatalogSearchQuery.count
    assert_equal "playwright testing", CatalogSearchQuery.sole.term
    assert_equal 2, CatalogSearchQuery.sole.search_count
  end

  # People paste all sorts of things into a search box. None of it belongs in a global
  # table, and none of it belongs in an outbound query to skills.sh either.
  test "refuses anything that is not a plain search term" do
    [
      "a",                                   # below the endpoint's own minimum
      "x" * 65,                              # longer than the cap
      "sk-live-0123456789abcdef",            # token-shaped: leading letters, but underscored/paths below
      "/Users/me/secret/path",
      "SELECT * FROM users",
      "<script>alert(1)</script>",
      "email@example.com",
      "  ",
      nil
    ].each do |junk|
      assert_nil CatalogSearchQuery.record(junk), "#{junk.inspect} should not be recorded"
    end

    assert_equal 0, CatalogSearchQuery.count
  end

  test "accepts the punctuation real skill searches contain" do
    %w[next.js c++ c# node-fetch].each do |term|
      assert_equal term, CatalogSearchQuery.record(term)
    end
  end

  test "top_terms follows demand" do
    3.times { CatalogSearchQuery.record("react") }
    CatalogSearchQuery.record("vue")
    2.times { CatalogSearchQuery.record("svelte") }

    assert_equal %w[react svelte vue], CatalogSearchQuery.top_terms(3)
  end

  # The table is an index of demand, not a log.
  test "prune drops stale terms and anything past the top N" do
    stale = CatalogSearchQuery.create!(term: "forgotten", search_count: 99, last_searched_at: 40.days.ago)
    5.times { |i| CatalogSearchQuery.record("term-#{i}") }

    CatalogSearchQuery.prune!(keep: 2, stale_after: 30.days)

    assert_nil CatalogSearchQuery.find_by(id: stale.id)
    assert_equal 2, CatalogSearchQuery.count
  end

  # No user, project or company column: a global table linking terms to tenants would
  # be a cross-tenant log of what each customer is looking for.
  test "carries no tenant attribution" do
    attribution = CatalogSearchQuery.column_names.grep(/user|project|company|session|ip/)

    assert_empty attribution, "search terms must stay unattributed"
  end
end
