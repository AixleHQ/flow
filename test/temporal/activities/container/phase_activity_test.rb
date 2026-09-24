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
        # mode: "non_interactive" — an interactive agent_session with no stored credential is a
        # legitimate first-time login (see AgentSessionStrategy#before_exec's first_login check) and
        # is deliberately let through instead of raising here; non_interactive can't complete that
        # login, so it must still hit raise_unresolved_credential! for this test to exercise it.
        session = create(:terminal_session, :agent_session, user: @user, agent_type: "codex",
                                                              mode: "non_interactive", initial_prompt: "Run tests")

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

      def agent_session
        create(:terminal_session, :agent_session, user: @user, agent_type: "codex")
      end

      test "a transient runtime failure is retried, a real one is not" do
        session = agent_session
        @runtime.stubs(:start_container).raises(Errno::ECONNREFUSED)
        transient = assert_raises(Temporalio::Error::ApplicationError) do
          run_activity(PhaseActivity, { phase: "start_container", session_id: session.id, state: { container_id: "c1" } })
        end
        assert_not transient.non_retryable

        @runtime.stubs(:start_container).raises(Kubeclient::HttpError.new(403, "forbidden", nil))
        fatal = assert_raises(Temporalio::Error::ApplicationError) do
          run_activity(PhaseActivity, { phase: "start_container", session_id: session.id, state: { container_id: "c1" } })
        end
        assert fatal.non_retryable
      end

      # Only a cleanup that finds the object already gone is expected; any other
      # cleanup failure leaves something behind and has to be seen.
      test "a cleanup that finds the container gone is benign, any other cleanup failure is not" do
        session = agent_session
        @runtime.stubs(:resolve_container).raises(Kubeclient::ResourceNotFoundError.new(404, "gone", nil))
        gone = assert_raises(Temporalio::Error::ApplicationError) do
          run_activity(PhaseActivity, { phase: "cleanup", session_id: session.id, state: { container_id: "c1" } })
        end
        assert_equal TemporalExceptions::BENIGN, gone.category

        @runtime.stubs(:resolve_container).raises(RuntimeError, "runtime refused")
        failed = assert_raises(Temporalio::Error::ApplicationError) do
          run_activity(PhaseActivity, { phase: "cleanup", session_id: session.id, state: { container_id: "c1" } })
        end
        assert_not_equal TemporalExceptions::BENIGN, failed.category
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
