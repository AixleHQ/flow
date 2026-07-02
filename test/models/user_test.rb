# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
  end

  # === membership-derived predicates ===

  test "viewer_everywhere? is true when every active membership is viewer" do
    user = create(:user, :viewer, company: @company)
    assert user.viewer_everywhere?
  end

  test "viewer_everywhere? is false for employee/admin/super_admin" do
    assert_not create(:user, :employee, company: @company).viewer_everywhere?
    assert_not create(:user, :admin, company: @company).viewer_everywhere?
    assert_not create(:user, :super_admin).viewer_everywhere?
  end

  test "viewer_everywhere? is false with no memberships and false for mixed roles" do
    user = create(:user)
    assert_not user.viewer_everywhere?

    create(:company_membership, :viewer, user: user, company: @company)
    # viewer_everywhere? is memoized per instance — reload clears it.
    assert user.reload.viewer_everywhere?

    create(:company_membership, :admin, user: user, company: create(:company))
    assert_not user.reload.viewer_everywhere?
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

  # === email domain no longer constrains identity (invite-any-domain) ===

  test "any-role user with mismatched email domain saves" do
    user = build(:user, email: "client@external-domain.com")
    assert user.valid?, user.errors.full_messages.to_sentence
    create(:company_membership, user: user.tap(&:save!), company: @company)
    assert user.reload.valid?
  end

  test "user is valid with zero memberships" do
    user = build(:user)
    assert user.valid?
  end

  # === soft delete ===

  test "soft_delete! sets deleted_at and marks the user deleted without removing the row" do
    user = create(:user, company: @company)

    assert_no_difference("User.count") { user.soft_delete! }
    assert user.deleted?
    assert user.deleted_at.present?
    assert_not_nil User.find(user.id)
  end

  test "not_deleted and deleted scopes partition users by deleted_at" do
    kept = create(:user, company: @company)
    removed = create(:user, company: @company)
    removed.soft_delete!

    assert_includes User.not_deleted, kept
    assert_not_includes User.not_deleted, removed
    assert_includes User.deleted, removed
    assert_not_includes User.deleted, kept
  end

  test "restore! clears deleted_at" do
    user = create(:user, company: @company)
    user.soft_delete!

    user.restore!
    assert_not user.deleted?
    assert_nil user.deleted_at
  end

  test "restore! raises when the user is not deleted" do
    user = create(:user, company: @company)
    assert_raises(ActiveRecord::RecordNotFound) { user.restore! }
  end

  test "soft_delete! preserves board activities authored by the user" do
    user = create(:user, company: @company)
    project = create(:project, company: @company, owner: user)
    board = create(:board, project: project)
    activity = BoardActivity.create!(
      board: board, event_type: :task_created, actor: user, actor_type: :human
    )

    assert_no_difference("BoardActivity.count") { user.soft_delete! }
    assert_equal user.id, activity.reload.actor_id
  end
end
