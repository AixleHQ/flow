# frozen_string_literal: true

require "test_helper"

module Users
  class PermanentDeletionServiceTest < ActiveSupport::TestCase
    setup do
      @company = create(:company)
      # Another active admin who can inherit owned projects.
      @heir = create(:user, :admin, company: @company)
      @heir_membership = @heir.company_memberships.first
      @user = create(:user, :admin, company: @company)
      @actor = create(:user, :super_admin)
    end

    test "removes the users row and frees the email for reuse" do
      email = @user.email

      assert_difference("User.count", -1) do
        PermanentDeletionService.call(user: @user, actor: @actor)
      end

      assert_nil User.find_by(id: @user.id)
      # The globally-unique email can be registered again.
      reused = build(:user, email: email)
      assert reused.valid?, reused.errors.full_messages.to_sentence
    end

    test "destroys the user's personal data" do
      membership = @user.company_memberships.first
      credential = create(:agent_credential, user: @user, company: @company)
      other_project = create(:project, company: @company, owner: @heir)
      favorite = create(:project_favorite, project: other_project, user: @user)
      collaborator = create(:project_collaborator, project: other_project, user: @user)
      session = build(:terminal_session, user: @user, project: other_project)
      session.save!(validate: false)
      board = create(:board, project: other_project)
      preset = BoardViewPreset.create!(board: board, user: @user, name: "Mine", filters: { "state" => "active" })

      PermanentDeletionService.call(user: @user, actor: @actor)

      assert_nil CompanyMembership.find_by(id: membership.id)
      assert_nil AgentCredential.find_by(id: credential.id)
      assert_nil ProjectFavorite.find_by(id: favorite.id)
      assert_nil ProjectCollaborator.find_by(id: collaborator.id)
      assert_nil TerminalSession.find_by(id: session.id)
      assert_nil BoardViewPreset.find_by(id: preset.id)
    end

    test "succeeds for a fully-wired user with tool_results and usage_statistics" do
      other_project = create(:project, company: @company, owner: @heir)
      session = build(:terminal_session, user: @user, project: other_project)
      session.save!(validate: false)
      UsageStatistic.create!(terminal_session: session, tokens: 100, cost_cents: 5)
      tool_result = create(:tool_result, terminal_session: session)

      assert_difference("User.count", -1) do
        PermanentDeletionService.call(user: @user, actor: @actor)
      end

      assert_nil User.find_by(id: @user.id)
      assert_nil TerminalSession.find_by(id: session.id)
      assert_nil tool_result.reload.terminal_session_id
    end

    test "transfers owned projects to the company heir admin" do
      project = create(:project, company: @company, owner: @user)

      PermanentDeletionService.call(user: @user, actor: @actor)

      assert_equal @heir.id, project.reload.owner_id
    end

    test "transfers owned projects per company to each company's own heir" do
      other_company = create(:company)
      other_heir = create(:user, :admin, company: other_company)
      create(:company_membership, user: @user, company: other_company, role: "admin", state: "active")
      project_a = create(:project, company: @company, owner: @user)
      project_b = create(:project, company: other_company, owner: @user)

      PermanentDeletionService.call(user: @user, actor: @actor)

      assert_equal @heir.id, project_a.reload.owner_id
      assert_equal other_heir.id, project_b.reload.owner_id
    end

    test "keeps history and nullifies the actor/author" do
      other_project = create(:project, company: @company, owner: @heir)
      board = create(:board, project: other_project)
      column = create(:board_column, board: board)
      task = create(:board_task, board: board, board_column: column)
      activity = BoardActivity.create!(board: board, event_type: :task_created,
                                       actor: @user, actor_type: :human)
      transition = ColumnTransition.create!(board_task: task, to_column: column,
                                            actor: @user, actor_type: :human)
      comment = create(:task_comment, board_task: task, author: @user)
      folder = create(:folder, path: "docs", scope: other_project, created_by: @user)

      PermanentDeletionService.call(user: @user, actor: @actor)

      assert_equal activity.id, activity.reload.id
      assert_nil activity.actor_id
      assert_nil transition.reload.actor_id
      assert_nil comment.reload.author_id
      assert_nil folder.reload.created_by_id
    end

    test "nullifies invited_by on memberships this user created" do
      invitee_membership = create(:company_membership, company: @company, invited_by: @user)

      PermanentDeletionService.call(user: @user, actor: @actor)

      assert_nil invitee_membership.reload.invited_by_id
    end

    test "raises OwnershipTransferError when a sole owner has no heir" do
      solo_company = create(:company)
      solo_user = create(:user, :admin, company: solo_company)
      create(:project, company: solo_company, owner: solo_user)

      error = assert_raises(PermanentDeletionService::OwnershipTransferError) do
        PermanentDeletionService.call(user: solo_user, actor: @actor)
      end
      assert_match solo_company.name, error.message
      # Nothing was deleted.
      assert User.exists?(solo_user.id)
    end

    test "raises SuperAdminProtected for super admins" do
      super_admin = create(:user, :super_admin)

      assert_raises(PermanentDeletionService::SuperAdminProtected) do
        PermanentDeletionService.call(user: super_admin, actor: @actor)
      end
      assert User.exists?(super_admin.id)
    end

    test "writes an audit record with id and email but not the profile" do
      email = @user.email
      id = @user.id

      assert_difference("Audited::Audit.where(action: 'permanent_delete').count", 1) do
        PermanentDeletionService.call(user: @user, actor: @actor)
      end

      audit = Audited::Audit.where(action: "permanent_delete").order(:id).last
      assert_equal id, audit.audited_changes["id"]
      assert_equal email, audit.audited_changes["email"]
      assert_equal @actor.id, audit.user_id
      assert_match email, audit.comment
    end
  end
end
