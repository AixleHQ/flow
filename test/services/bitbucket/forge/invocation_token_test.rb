# frozen_string_literal: true

require "test_helper"

module Bitbucket
  module Forge
    class InvocationTokenTest < ActiveSupport::TestCase
      include ForgeTestHelper

      setup do
        with_bitbucket_settings(app_mode: true)
        @keys = stub_forge_keys!
        @installation_id = forge_installation_ari
      end

      def verify(token) = InvocationToken.verify!("Bearer #{token}")

      test "a token Forge signed for this app and environment names its installation and workspace" do
        invocation = verify(forge_invocation_token(installation_id: @installation_id, principal: "acct-1"))

        assert_equal @installation_id, invocation.installation_id
        assert_equal ForgeTestHelper::FORGE_WORKSPACE_UUID, invocation.workspace_uuid
        assert_equal "acct-1", invocation.principal
        assert_equal BitbucketTestHelper::FORGE_ENVIRONMENT_ID, invocation.environment_id
      end

      test "a token for another app is refused" do
        token = forge_invocation_token(installation_id: @installation_id, aud: "ari:cloud:ecosystem::app/someone-else")

        error = assert_raises(InvocationToken::Invalid) { verify(token) }
        assert_match(/another app/, error.message)
      end

      test "a token from another environment of the same app is refused" do
        token = forge_invocation_token(installation_id: @installation_id,
                                       app: { environment: { id: "ari:cloud:ecosystem::environment/development-env" } })

        error = assert_raises(InvocationToken::Invalid) { verify(token) }
        assert_match(/another environment/, error.message)
      end

      test "an expired token is refused" do
        token = forge_invocation_token(installation_id: @installation_id, exp: 5.minutes.ago.to_i)

        assert_raises(InvocationToken::Invalid) { verify(token) }
      end

      test "a token that is not RS256 is refused before any key is consulted" do
        hs256 = forge_invocation_token(installation_id: @installation_id, key: "shared-secret", algorithm: "HS256")
        unsigned = JWT.encode({ aud: BitbucketTestHelper::FORGE_APP_ID }, nil, "none")

        assert_raises(InvocationToken::Invalid) { verify(hs256) }
        assert_raises(InvocationToken::Invalid) { verify(unsigned) }
        assert_not_requested @keys
      end

      test "a token signed by a key Forge does not publish is refused after one refetch" do
        token = forge_invocation_token(installation_id: @installation_id, key: OpenSSL::PKey::RSA.new(2048), kid: "unknown")

        error = assert_raises(InvocationToken::Invalid) { verify(token) }
        assert_match(/unknown signing key/, error.message)
        assert_requested @keys, times: 2
      end

      test "a key Forge publishes but did not sign with fails the signature" do
        token = forge_invocation_token(installation_id: @installation_id, key: OpenSSL::PKey::RSA.new(2048))

        assert_raises(InvocationToken::Invalid) { verify(token) }
      end

      test "no bearer at all is refused" do
        assert_raises(InvocationToken::Invalid) { InvocationToken.verify!(nil) }
        assert_raises(InvocationToken::Invalid) { InvocationToken.verify!("Basic abc") }
      end

      test "the app id may be configured bare or as an ARI" do
        Settings.bitbucket.forge.app_id = BitbucketTestHelper::FORGE_APP_ID.split("/").last

        assert_equal @installation_id, verify(forge_invocation_token(installation_id: @installation_id)).installation_id
      end
    end
  end
end
