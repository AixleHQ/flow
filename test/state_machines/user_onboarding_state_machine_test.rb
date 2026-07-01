# frozen_string_literal: true

require "test_helper"

class UserOnboardingStateMachineTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
  end

  test "viewer advances step3 to step4 with zero agent credentials" do
    user = create(:user, :viewer, company: @company, onboarding_state: "step3",
                                  position: "dev", preferred_agent_language: "en")
    assert user.aasm(:onboarding_state).fire!(:go_next)
    assert_equal "step4", user.onboarding_state
  end

  test "non-viewer is blocked at step3 without credentials" do
    user = create(:user, :employee, company: @company, onboarding_state: "step3",
                                     position: "dev", preferred_agent_language: "en")
    assert_not user.aasm(:onboarding_state).may_fire_event?(:go_next)
  end

  test "non-viewer advances step3 to step4 with credentials" do
    user = create(:user, :employee, company: @company, onboarding_state: "step3",
                                     position: "dev", preferred_agent_language: "en")
    create(:agent_credential, user: user, agent_type: "claude_code")
    assert user.reload.aasm(:onboarding_state).fire!(:go_next)
    assert_equal "step4", user.onboarding_state
  end

  test "viewer completes onboarding with position+language and no agents" do
    user = create(:user, :viewer, company: @company, onboarding_state: "step4",
                                  position: "dev", preferred_agent_language: "en")
    assert user.aasm(:onboarding_state).fire!(:complete)
    assert_equal "completed", user.onboarding_state
  end
end
