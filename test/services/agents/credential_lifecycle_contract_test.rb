# frozen_string_literal: true

require "test_helper"

# The contract every agent runtime declares about its credential, and the invariants that
# keep a declaration honest. This is the mechanical answer to "does every harness actually
# refresh?" — a new runtime cannot ship half a lifecycle without failing here.
#
# The two shapes this exists to reject have both happened in production:
#   * an expiry with no way to act on it — a working credential reads "expired" an hour
#     after login, because only the CLI in the container can renew it;
#   * a refresh the sweep can never select — `refresh_due` filters on a non-null expiry,
#     so a runtime that refreshes but publishes no expiry is never swept (the cursor_cli
#     NULL-expiry population).
module Agents
  class CredentialLifecycleContractTest < ActiveSupport::TestCase
    EXPIRY_VALUES   = %i[token none].freeze
    REFRESH_VALUES  = %i[server container_only reauth_only none].freeze
    ROTATION_VALUES = %i[rotating static].freeze

    def adapters
      CompanyMembership::AVAILABLE_AGENTS.index_with { |type| AgentCredentialsService.new(type).adapter }
    end

    test "every available agent declares a credential lifecycle" do
      adapters.each do |agent_type, adapter|
        lifecycle = adapter.credential_lifecycle

        assert_kind_of Hash, lifecycle, "#{agent_type} declares no lifecycle"
        assert_includes EXPIRY_VALUES, lifecycle[:expiry], "#{agent_type} expiry"
        assert_includes REFRESH_VALUES, lifecycle[:refresh], "#{agent_type} refresh"
        assert_includes ROTATION_VALUES, lifecycle[:rotation], "#{agent_type} rotation"
        assert lifecycle.frozen?, "#{agent_type} lifecycle must be frozen"
      end
    end

    test "a server-side refresh requires a readable expiry, or the sweep can never select it" do
      adapters.each do |agent_type, adapter|
        next unless adapter.credential_lifecycle[:refresh] == :server

        assert_equal :token, adapter.credential_lifecycle[:expiry],
                     "#{agent_type} refreshes server-side but publishes no expiry: " \
                     "AgentCredential.refresh_due filters on a non-null expires_at, so it is never swept"
      end
    end

    test "a declared server-side refresh is actually implemented" do
      adapters.each do |agent_type, adapter|
        next unless adapter.credential_lifecycle[:refresh] == :server

        assert_not_equal BaseAdapter, adapter.method(:refresh!).owner,
                         "#{agent_type} declares refresh: :server but inherits BaseAdapter#refresh!"
        assert_not_equal BaseAdapter, adapter.method(:token_expires_at).owner,
                         "#{agent_type} declares refresh: :server but inherits BaseAdapter#token_expires_at"
      end
    end

    test "a declared expiry is actually implemented, and an undeclared one is not published" do
      adapters.each do |agent_type, adapter|
        implemented = adapter.method(:token_expires_at).owner != BaseAdapter

        if adapter.credential_lifecycle[:expiry] == :token
          assert implemented, "#{agent_type} declares expiry: :token but does not implement #token_expires_at"
        else
          assert_not implemented,
                     "#{agent_type} implements #token_expires_at but declares expiry: #{adapter.credential_lifecycle[:expiry].inspect} — " \
                     "an expiry nothing acts on paints a working credential 'expired'"
        end
      end
    end

    test "an expiry nothing can renew must say that re-authentication is the remedy" do
      silent = adapters.select do |_agent_type, adapter|
        lifecycle = adapter.credential_lifecycle
        lifecycle[:expiry] == :token && lifecycle[:refresh] != :server && !lifecycle[:reauth_required_on_expiry]
      end

      assert_empty silent.keys,
                   "these surface an expiry they cannot refresh without declaring reauth_required_on_expiry: " \
                   "the user must be told to sign in again, not left waiting for a sweep"
    end

    test "AgentCredential.refreshable_agent_types is derived from the declarations" do
      declared = adapters.select { |_type, adapter| adapter.credential_lifecycle[:refresh] == :server }.keys

      assert_equal declared.sort, AgentCredential.refreshable_agent_types.sort
    end

    # Today's answer, pinned so a change to the matrix is a deliberate edit rather than a
    # side effect. See docs/design/agent-credential-lifecycle.md §2 for why each is where
    # it is, and §Layer 1 for what closes the gaps.
    # gemini_cli is the one runtime left out, and deliberately: its credential is an API key.
    test "every runtime whose login can expire is refreshed server-side" do
      assert_equal %w[antigravity_cli claude_code codex cursor_cli grok kiro_cli].sort,
                   AgentCredential.refreshable_agent_types.sort
    end
  end
end
