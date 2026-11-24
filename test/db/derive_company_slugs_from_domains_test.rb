# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261124100000_derive_company_slugs_from_domains")

class DeriveCompanySlugsFromDomainsTest < ActiveSupport::TestCase
  test "rewrites every slug from the domain, the oldest company keeping the bare label" do
    older = create(:company, name: "Acme Corporation", email_domain: "acme.com")
    newer = create(:company, name: "Acme Europe", email_domain: "acme.co.uk")
    sectioned = create(:company, name: "Members Club", email_domain: "members.org")
    older.update_columns(slug: "acme-corporation")
    newer.update_columns(slug: "acme")
    sectioned.update_columns(slug: "members-club")

    migration = DeriveCompanySlugsFromDomains.new
    migration.suppress_messages { migration.up }

    assert_equal "acme", older.reload.slug
    assert_equal "acme-1", newer.reload.slug
    assert_equal "members-1", sectioned.reload.slug
    assert [ older, newer, sectioned ].all?(&:valid?)
  end
end
