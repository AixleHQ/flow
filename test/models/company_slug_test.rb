# frozen_string_literal: true

require "test_helper"

class CompanySlugTest < ActiveSupport::TestCase
  test "a new company is slugged after its domain without the public suffix" do
    assert_equal "acme", create(:company, email_domain: "acme.com").slug
    assert_equal "globex", create(:company, email_domain: "globex.co.uk").slug
    assert_equal "initech", create(:company, email_domain: "mail.initech.io").slug
  end

  test "a domain whose label is taken, or reads as a section of /company, gets a number" do
    create(:company, email_domain: "acme.com")

    assert_equal "acme-1", create(:company, email_domain: "acme.io").slug
    assert_equal "projects-1", create(:company, email_domain: "projects.com").slug
  end

  test "a slug that reads as a section of /company is refused" do
    company = build(:company, slug: "members")

    assert_not company.valid?
    assert_includes company.errors[:slug], "is reserved"
  end

  # Every page under /company/<slug> is also reachable as /company/<section>/…
  # (a link from before the slug, or a helper on a page with no company), and
  # Web::UnscopedCompanyPathsController only passes on the sections it knows.
  test "the word after the slug in every company route is reserved" do
    sections = Rails.application.routes.routes.filter_map do |route|
      route.path.spec.to_s[%r{/company/:company_slug/([^/(]+)}, 1]
    end

    assert_operator sections.uniq.size, :>, 10
    assert_empty sections.uniq - Company::RESERVED_SLUGS
  end
end
