# frozen_string_literal: true

require "test_helper"

class EmailAddressTest < ActiveSupport::TestCase
  test "an address with a dotted domain passes" do
    [ "a@example.com", "first.last+tag@sub.example.co.uk" ].each do |email|
      assert_match EmailAddress::DOTTED_DOMAIN, email
    end
  end

  test "an address whose domain has no dot is refused" do
    [ "a@2005", "a@localhost" ].each do |email|
      assert_no_match EmailAddress::DOTTED_DOMAIN, email
    end
  end
end
