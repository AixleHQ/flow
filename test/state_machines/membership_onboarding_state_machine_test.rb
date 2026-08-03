# frozen_string_literal: true

require "test_helper"

# Onboarding is per COMPANY: the machine lives on CompanyMembership, because the
# role, the chosen agents and the agent credential all differ per company (the
# credential must, so vendor spend is billed to the company that incurred it).
#
# Two steps only: step1 (profile) → step2 (connect agents / viewer preview) →
# completed. `complete` finishes directly from step2 — no intermediate
# "ready to finish" state.
class MembershipOnboardingStateMachineTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
  end

  def membership(role, state: "step2")
    create(:user, role, company: @company, onboarding_state: state,
                        position: "dev", preferred_agent_language: "en")
      .company_memberships.sole
  end

  test "go_next advances step1 to step2" do
    m = membership(:employee, state: "step1")
    assert m.aasm(:onboarding_state).fire!(:go_next)
    assert_equal "step2", m.onboarding_state
  end

  test "go_previous returns step2 to step1" do
    m = membership(:employee, state: "step2")
    assert m.aasm(:onboarding_state).fire!(:go_previous)
    assert_equal "step1", m.onboarding_state
  end

  test "viewer completes onboarding from step2 with zero agent credentials" do
    m = membership(:viewer)
    assert m.aasm(:onboarding_state).fire!(:complete)
    assert_equal "completed", m.onboarding_state
    assert m.onboarding_completed_at.present?
  end

  test "non-viewer is blocked from completing at step2 without credentials" do
    m = membership(:employee)
    assert_not m.aasm(:onboarding_state).may_fire_event?(:complete)
  end

  test "non-viewer completes onboarding from step2 with credentials" do
    m = membership(:employee)
    create(:agent_credential, user: m.user, company: @company, agent_type: "claude_code")
    assert m.reload.aasm(:onboarding_state).fire!(:complete)
    assert_equal "completed", m.onboarding_state
  end

  # A credential in ANOTHER company must not satisfy this company's agent gate —
  # that is the whole point of per-company credentials.
  test "a credential in another company does not unblock completion here" do
    m = membership(:employee)
    other = create(:company)
    create(:company_membership, user: m.user, company: other)
    create(:agent_credential, user: m.user, company: other, agent_type: "claude_code")

    assert_not m.reload.aasm(:onboarding_state).may_fire_event?(:complete)
  end

  # Completing onboarding in one company says nothing about another.
  test "onboarding state is independent per company" do
    m = membership(:viewer)
    other = create(:company)
    other_m = create(:company_membership, :viewer, user: m.user, company: other)

    m.aasm(:onboarding_state).fire!(:complete)

    assert m.reload.onboarding_completed?
    assert_equal "step1", other_m.reload.onboarding_state
  end

  test "reopen sends a completed membership back to step2" do
    m = membership(:employee, state: "completed")
    assert m.aasm(:onboarding_state).fire!(:reopen)
    assert_equal "step2", m.onboarding_state
  end
end
