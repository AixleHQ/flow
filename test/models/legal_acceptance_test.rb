# frozen_string_literal: true

require "test_helper"

class LegalAcceptanceTest < ActiveSupport::TestCase
  test "the Terms of Service are accepted for a company" do
    acceptance = build(:legal_acceptance, :terms_of_service, company: nil)

    assert acceptance.invalid?
    assert_includes acceptance.errors[:company], "can't be blank"
  end

  test "only documents that are accepted can be" do
    acceptance = build(:legal_acceptance, document: LegalDocument::PRIVACY_POLICY.key)

    assert acceptance.invalid?
    assert_includes acceptance.errors.attribute_names, :document
  end

  test "an acceptance counts only for the version it names" do
    user = create(:user)
    create(:legal_acceptance, user: user, version: "2020-01-01")

    refute LegalAcceptance.current?(LegalDocument::TERMS_OF_USE, user: user)

    LegalAcceptance.record!(LegalDocument::TERMS_OF_USE, user: user)

    assert LegalAcceptance.current?(LegalDocument::TERMS_OF_USE, user: user)
  end

  test "the Terms of Use bind the person, not the company they accepted them in" do
    acceptance = LegalAcceptance.record!(LegalDocument::TERMS_OF_USE, user: create(:user), company: create(:company))

    assert_nil acceptance.company
  end

  test "a company's acceptance outlives the person who gave it" do
    acceptance = create(:legal_acceptance, :terms_of_service)

    acceptance.user.destroy!

    assert_nil acceptance.reload.user_id
    assert LegalAcceptance.current?(LegalDocument::TERMS_OF_SERVICE, company: acceptance.company)
  end
end
