# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
  end

  # === role predicates ===

  test "viewer? and read_only? are true for viewer" do
    user = build(:user, :viewer, company: @company)
    assert user.viewer?
    assert user.read_only?
  end

  test "read_only? is false for employee/admin/super_admin" do
    assert_not build(:user, :employee, company: @company).read_only?
    assert_not build(:user, :admin, company: @company).read_only?
    assert_not build(:user, :super_admin).read_only?
  end

  # === onboarding helpers ===

  test "can_complete_onboarding? true for viewer with position+language and no agents" do
    user = create(:user, :viewer, company: @company, position: "dev", preferred_agent_language: "en")
    assert_not user.has_configured_agents?
    assert user.can_complete_onboarding?
  end

  test "can_complete_onboarding? false for viewer missing position or language" do
    user = create(:user, :viewer, company: @company, position: nil, preferred_agent_language: "en")
    assert_not user.can_complete_onboarding?
  end

  test "can_complete_onboarding? still requires agents for non-viewer" do
    user = create(:user, :employee, company: @company, position: "dev", preferred_agent_language: "en")
    assert_not user.can_complete_onboarding?
    create(:agent_credential, user: user, agent_type: "claude_code")
    assert user.reload.can_complete_onboarding?
  end

  test "can_advance_to_authenticated? true for viewer regardless of credentials" do
    user = create(:user, :viewer, company: @company)
    assert user.can_advance_to_authenticated?
  end

  test "can_advance_to_authenticated? requires agents for non-viewer" do
    user = create(:user, :employee, company: @company)
    assert_not user.can_advance_to_authenticated?
    create(:agent_credential, user: user, agent_type: "claude_code")
    assert user.reload.can_advance_to_authenticated?
  end

  # === email domain matching exemption (constraint b) ===

  test "viewer with mismatched email domain saves" do
    user = build(:user, :viewer, company: @company, email: "client@external-domain.com")
    assert user.valid?, user.errors.full_messages.to_sentence
  end

  test "non-viewer with mismatched email domain fails" do
    user = build(:user, :employee, company: @company, email: "someone@external-domain.com")
    assert_not user.valid?
    assert_includes user.errors[:email].to_sentence, "domain"
  end

  test "viewer still requires company_id" do
    user = build(:user, :viewer, company: nil)
    assert_not user.valid?
    assert user.errors[:company_id].present?
  end
end
