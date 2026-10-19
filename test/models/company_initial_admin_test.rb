# frozen_string_literal: true

require "test_helper"

class CompanyInitialAdminTest < ActiveSupport::TestCase
  test "a new company's initial admin must be an address that can be invited" do
    create(:user, :super_admin, email: "root@example.com")
    company = build(:company, initial_admin_email: "not-an-email")

    assert_not company.valid?
    assert_equal [ "is invalid" ], company.errors[:initial_admin_email]

    company.initial_admin_email = " ROOT@example.com "
    assert_not company.valid?
    assert_equal [ "belongs to a platform administrator, who cannot be a member of a company" ],
                 company.errors[:initial_admin_email]

    company.initial_admin_email = "boss@example.com"
    assert company.valid?, company.errors.full_messages.to_sentence
  end

  test "a company without an initial admin, or one already saved, is not checked" do
    assert build(:company).valid?

    company = create(:company)
    company.initial_admin_email = "not-an-email"
    assert company.valid?, company.errors.full_messages.to_sentence
  end
end
