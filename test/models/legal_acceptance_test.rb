# frozen_string_literal: true

require "test_helper"

class LegalAcceptanceTest < ActiveSupport::TestCase
  def evidence
    LegalAcceptance::Evidence.new(accepted_at: Time.utc(2026, 11, 2, 9, 30), ip_address: "203.0.113.7",
                                  user_agent: "Browser/1.0")
  end

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

    LegalAcceptance.record!(LegalDocument::TERMS_OF_USE, user: user, evidence: evidence)

    assert LegalAcceptance.current?(LegalDocument::TERMS_OF_USE, user: user)
  end

  test "the Terms of Use bind the person, not the company they accepted them in" do
    acceptance = LegalAcceptance.record!(
      LegalDocument::TERMS_OF_USE, user: create(:user), company: create(:company), evidence: evidence
    )

    assert_nil acceptance.company
    assert_nil acceptance.company_name
  end

  test "it is recorded with the evidence of the ticked box and names who accepted for whom" do
    user = create(:user, email: "dana@acme-robotics.example")
    company = create(:company, name: "Acme Robotics", email_domain: "acme-robotics.example")

    acceptance = LegalAcceptance.record!(LegalDocument::TERMS_OF_SERVICE, user: user, company: company, evidence: evidence)

    assert_equal [ Time.utc(2026, 11, 2, 9, 30), "203.0.113.7", "Browser/1.0" ],
                 [ acceptance.accepted_at, acceptance.ip_address, acceptance.user_agent ]
    assert_equal [ "dana@acme-robotics.example", "Acme Robotics", "acme-robotics.example" ],
                 [ acceptance.user_email, acceptance.company_name, acceptance.company_email_domain ]
  end

  test "a company's acceptance outlives the person who gave it, and still says who that was" do
    user = create(:user, email: "dana@acme-robotics.example")
    acceptance = create(:legal_acceptance, :terms_of_service, user: user)

    user.destroy!

    assert_nil acceptance.reload.user_id
    assert_equal "dana@acme-robotics.example", acceptance.user_email
    assert LegalAcceptance.current?(LegalDocument::TERMS_OF_SERVICE, company: acceptance.company)
  end

  test "an acceptance outlives the company it was given for, and still says which that was" do
    company = create(:company, name: "Acme Robotics", email_domain: "acme-robotics.example")
    acceptance = create(:legal_acceptance, :terms_of_service, company: company)

    company.destroy!

    acceptance.reload
    assert_nil acceptance.company_id
    assert_equal [ "Acme Robotics", "acme-robotics.example" ], [ acceptance.company_name, acceptance.company_email_domain ]
  end
end
