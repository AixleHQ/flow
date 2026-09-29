# frozen_string_literal: true

require "test_helper"

class Domains::VerificationTest < ActiveSupport::TestCase
  setup do
    @company = create(:company, email_domain: "acme-robotics.example")
    @company.update_columns(domain_verified_at: nil, domain_verification_token: nil)
  end

  def host = "_aixle-challenge.acme-robotics.example"

  test "it asks for a record of its own rather than one at the root" do
    assert_equal host, Domains::Verification.host_for(@company)
  end

  # The root TXT set is shared with SPF, DMARC and every other vendor's proof,
  # and has a length budget those already strain.
  test "the record names this product and carries the company's own token" do
    record = Domains::Verification.record_for(@company)

    assert record.start_with?("aixle-domain-verification=")
    assert_equal @company.reload.domain_verification_token, record.split("=").last
  end

  test "the token is minted once and then kept" do
    first = Domains::Verification.token_for(@company)

    assert_equal first, Domains::Verification.token_for(@company.reload)
  end

  test "two companies never share a token" do
    other = create(:company)
    other.update_columns(domain_verification_token: nil)

    assert_not_equal Domains::Verification.token_for(@company), Domains::Verification.token_for(other)
  end

  test "a published record proves the domain" do
    published_txt_records(host => [ Domains::Verification.record_for(@company) ])

    assert Domains::Verification.verify!(@company)
    assert @company.reload.domain_verified?
  end

  test "a domain with no record is not proved" do
    published_txt_records

    assert_not Domains::Verification.verify!(@company)
    assert_not @company.reload.domain_verified?
  end

  # Somebody else's token at your domain proves nothing about you.
  test "another company's token does not prove this one" do
    other = create(:company)
    published_txt_records(host => [ Domains::Verification.record_for(other) ])

    assert_not Domains::Verification.verify!(@company)
  end

  # A domain usually has several TXT records and ours is one among them.
  test "the record is found among the others a domain carries" do
    published_txt_records(host => [ "v=spf1 include:_spf.google.com ~all",
                                    Domains::Verification.record_for(@company),
                                    "some-other-vendor=abc123" ])

    assert Domains::Verification.verify!(@company)
  end

  test "surrounding whitespace does not stop it matching" do
    published_txt_records(host => [ "  #{Domains::Verification.record_for(@company)} " ])

    assert Domains::Verification.verify!(@company)
  end

  # A screen that polls must not cost a lookup per poll, and a company already
  # proved must not become unproved because a resolver blinked.
  test "a proved domain stays proved without another lookup" do
    @company.update!(domain_verified_at: 1.day.ago)
    Dns::TxtLookup.expects(:call).never

    assert Domains::Verification.verify!(@company)
  end
end
