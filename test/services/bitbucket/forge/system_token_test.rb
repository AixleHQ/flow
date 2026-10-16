# frozen_string_literal: true

require "test_helper"

module Bitbucket
  module Forge
    class SystemTokenTest < ActiveSupport::TestCase
      include ForgeTestHelper

      test "reads the expiry of the pushed app token" do
        expires = 3.hours.from_now.change(usec: 0)

        assert_equal expires, SystemToken.expires_at(forge_system_token(expires_at: expires))
      end

      test "a token whose expiry cannot be read has none" do
        assert_nil SystemToken.expires_at(nil)
        assert_nil SystemToken.expires_at("opaque-token")
        assert_nil SystemToken.expires_at("a.#{Base64.urlsafe_encode64('[1,2]', padding: false)}.c")
        assert_nil SystemToken.expires_at("a.!!!.c")
      end
    end
  end
end
