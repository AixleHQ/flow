# frozen_string_literal: true

require "test_helper"

module Activities
  module Container
    class PhaseActivityTest < ActiveSupport::TestCase
      setup do
        @company = create(:company)
        @user = create(:user, :admin, company: @company)
        @runtime = stub_container_runtime(agent_type: "codex")
      end

      teardown do
        cleanup_runtime_overrides
      end

      # Board task #1308 / PR #193 code review: AgentSessionStrategy::ProvisioningError#details
      # (the secret-safe candidate set that answers "why did lookup return nil?") is preserved on
      # ContainerService::PhaseError#original_error, but this activity's rescue used to forward
      # only `error.message` into the Temporal ApplicationError — the diagnostic never reached the
      # workflow or Temporal history, defeating the whole point of building it.
      test "surfaces the secret-safe credential candidate set through the Temporal ApplicationError" do
        decoy = create(:agent_credential, user: @user, agent_type: "claude_code")
        session = create(:terminal_session, :agent_session, user: @user, agent_type: "codex")

        error = assert_raises(Temporalio::Error::ApplicationError) do
          run_activity(
            PhaseActivity,
            { phase: "exec", session_id: session.id, state: { container_id: "container_ref" } }
          )
        end

        assert error.non_retryable
        assert_match(/credential_not_resolved/, error.message)
        assert_equal 1, error.details.size
        candidate = error.details.first

        assert_equal session.id, candidate[:session_id]
        assert_equal "codex", candidate[:session_agent_type]
        assert_includes candidate[:credential_candidates], [ decoy.id, decoy.company_id, "claude_code" ]

        # The whole reason this diagnostic exists is to be secret-safe: ids, company ids and
        # agent types only, never the credential's own token material.
        refute_includes error.details.inspect, decoy.config_data["api_key"]
      end

      # ArgumentError (the other class rescued alongside PhaseError here) has no #details, and a
      # PhaseError can wrap an original error that isn't a diagnostic at all — both must fall back
      # to no details instead of raising while building the ApplicationError.
      test "omits details when the underlying error carries none" do
        error = assert_raises(Temporalio::Error::ApplicationError) do
          run_activity(PhaseActivity, { phase: "exec" })
        end

        assert_empty error.details
      end
    end
  end
end
