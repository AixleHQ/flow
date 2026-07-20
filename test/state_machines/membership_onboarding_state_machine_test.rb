# frozen_string_literal: true

require "test_helper"

# Onboarding is per COMPANY: the machine lives on CompanyMembership, because the
# role, the chosen agents and the agent credential all differ per company (the
# credential must, so vendor spend is billed to the company that incurred it).
class MembershipOnboardingStateMachineTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
  end

  def membership(role, state: "step3")
    create(:user, role, company: @company, onboarding_state: state,
                        position: "dev", preferred_agent_language: "en")
      .company_memberships.sole
  end

  test "viewer advances step3 to step4 with zero agent credentials" do
    m = membership(:viewer)
    assert m.aasm(:onboarding_state).fire!(:go_next)
    assert_equal "step4", m.onboarding_state
  end

  test "non-viewer is blocked at step3 without credentials" do
    m = membership(:employee)
    assert_not m.aasm(:onboarding_state).may_fire_event?(:go_next)
  end

  test "non-viewer advances step3 to step4 with credentials" do
    m = membership(:employee)
    create(:agent_credential, user: m.user, company: @company, agent_type: "claude_code")
    assert m.reload.aasm(:onboarding_state).fire!(:go_next)
    assert_equal "step4", m.onboarding_state
  end

  test "viewer completes onboarding with position+language and no agents" do
    m = membership(:viewer, state: "step4")
    assert m.aasm(:onboarding_state).fire!(:complete)
    assert_equal "completed", m.onboarding_state
    assert m.onboarding_completed_at.present?
  end

  test "viewer_advance transitions viewer from step2 to step4" do
    m = membership(:viewer, state: "step2")
    assert m.viewer_advance!
    assert_equal "step4", m.reload.onboarding_state
  end

  test "viewer_advance is blocked for non-viewer at step2" do
    m = membership(:employee, state: "step2")
    assert_raises(AASM::InvalidTransition) { m.viewer_advance! }
    assert_equal "step2", m.reload.onboarding_state
  end

  # A credential in ANOTHER company must not satisfy this company's agent gate —
  # that is the whole point of per-company credentials.
  test "a credential in another company does not unblock step3 here" do
    m = membership(:employee)
    other = create(:company)
    create(:company_membership, user: m.user, company: other)
    create(:agent_credential, user: m.user, company: other, agent_type: "claude_code")

    assert_not m.reload.aasm(:onboarding_state).may_fire_event?(:go_next)
  end

  # Completing onboarding in one company says nothing about another.
  test "onboarding state is independent per company" do
    m = membership(:viewer, state: "step4")
    other = create(:company)
    other_m = create(:company_membership, :viewer, user: m.user, company: other)

    m.aasm(:onboarding_state).fire!(:complete)

    assert m.reload.onboarding_completed?
    assert_equal "step1", other_m.reload.onboarding_state
  end
end
