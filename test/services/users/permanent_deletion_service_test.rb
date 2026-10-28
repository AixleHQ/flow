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
      board = create(:board, project: other_project)
      preset = BoardViewPreset.create!(board: board, user: @user, name: "Mine", filters: { "state" => "active" })
      oauth = OauthCredential.create!(owner: @user, provider: "sentry", status: :active, access_token: "at-1",
                                      oauth_client: OauthClient.create!(issuer: "https://sentry.io", client_id: "c",
                                                                        authorization_endpoint: "https://sentry.io/a",
                                                                        token_endpoint: "https://sentry.io/t",
                                                                        source: "static"))
      UserSession.start!(user: @user)

      PermanentDeletionService.call(user: @user, actor: @actor)

      assert_nil CompanyMembership.find_by(id: membership.id)
      assert_nil AgentCredential.find_by(id: credential.id)
      assert_nil ProjectFavorite.find_by(id: favorite.id)
      assert_nil ProjectCollaborator.find_by(id: collaborator.id)
      assert_nil BoardViewPreset.find_by(id: preset.id)
      assert_nil OauthCredential.find_by(id: oauth.id), "a deleted user's grants must not keep refreshing"
      assert_not UserSession.exists?(user_id: @user.id)
    end

    # The company's analytics are built on sessions and their usage; deleting a
    # person must not shrink what the company spent.
    test "keeps the user's sessions and their usage as the company's history" do
      other_project = create(:project, company: @company, owner: @heir)
      session = create(:terminal_session, :agent_session, user: @user, project: other_project, state: "finished")
      usage = UsageStatistic.create!(terminal_session: session, cost_cents: 5)

      PermanentDeletionService.call(user: @user, actor: @actor)

      assert_nil session.reload.user_id
      assert_equal 5, usage.reload.cost_cents
    end

    test "refuses to delete a company's only admin" do
      solo_company = create(:company)
      solo_admin = create(:user, :admin, company: solo_company)

      error = assert_raises(PermanentDeletionService::LastAdminError) do
        PermanentDeletionService.call(user: solo_admin, actor: @actor)
      end
      assert_match solo_company.name, error.message
      assert User.exists?(solo_admin.id)
    end

    test "refuses while one of the user's sessions is still running" do
      create(:terminal_session, :agent_session, :running, user: @user, project: create(:project, company: @company, owner: @heir))

      assert_raises(PermanentDeletionService::LiveSessionsError) do
        PermanentDeletionService.call(user: @user, actor: @actor)
      end
      assert User.exists?(@user.id)
    end

    test "succeeds for a fully-wired user with tool_results and usage_statistics" do
      other_project = create(:project, company: @company, owner: @heir)
      session = build(:terminal_session, user: @user, project: other_project, state: "finished")
      session.save!(validate: false)
      UsageStatistic.create!(terminal_session: session, cost_cents: 5)
      tool_result = create(:tool_result, terminal_session: session)

      assert_difference("User.count", -1) do
        PermanentDeletionService.call(user: @user, actor: @actor)
      end

      assert_nil User.find_by(id: @user.id)
      assert_nil session.reload.user_id
      assert_equal session.id, tool_result.reload.terminal_session_id
    end

    # In production every user has rows nearly everywhere, so one unhandled
    # foreign key fails every deletion. The scenario must keep up with the
    # schema: a new foreign key that reaches users fails this test until the
    # scenario has a row behind it.
    test "deletes a user who has a row behind every foreign key that reaches them" do
      FullyWiredUserScenario.new(user: @user, company: @company, heir: @heir).build
      references = references_reaching(@user)

      unwired = references.reject { |reference| connection.select_value("SELECT EXISTS (#{reference.rows})") }
      assert_empty unwired.map(&:to_s), "FullyWiredUserScenario has no row behind these foreign keys"
      undeclared = User.reflect_on_all_associations.select { |a| a.options[:dependent] && !@user.public_send(a.name).exists? }
      assert_empty undeclared.map(&:name), "FullyWiredUserScenario has no row in these User associations"

      survivors = references.select(&:nullified_user?).to_h { |reference| [ reference, connection.select_values(reference.rows) ] }

      assert_difference("User.count", -1) do
        PermanentDeletionService.call(user: @user, actor: @actor)
      end

      survivors.each do |reference, ids|
        fk = reference.foreign_key
        kept = connection.select_values("SELECT id FROM #{connection.quote_table_name(fk.from_table)} " \
                                        "WHERE id IN (#{ids.join(', ')}) AND #{connection.quote_column_name(fk.column)} IS NULL")
        assert_equal ids.sort, kept.sort, "#{reference} rows must outlive the user with the reference nullified"
      end
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

    test "keeps the feature flag values the user set, with the author nullified" do
      flag = FeatureFlag.create!(key: "external_runners", enabled: true, updated_by: @user)
      override = flag.overrides.create!(company: @company, enabled: false, reason: "asked to wait", created_by: @user)

      PermanentDeletionService.call(user: @user, actor: @actor)

      assert_equal [ true, nil ], [ flag.reload.enabled, flag.updated_by_id ]
      assert_equal [ false, nil ], [ override.reload.enabled, override.created_by_id ]
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

      assert_difference("Audit.where(action: 'permanent_delete').count", 1) do
        PermanentDeletionService.call(user: @user, actor: @actor)
      end

      audit = Audit.where(action: "permanent_delete").order(:id).last
      assert_equal id, audit.audited_changes["id"]
      assert_equal email, audit.audited_changes["email"]
      assert_equal @actor.id, audit.user_id
      assert_match email, audit.comment
    end

    Reference = Data.define(:foreign_key, :rows) do
      def nullified_user? = foreign_key.to_table == "users" && foreign_key.on_delete == :nullify
      def to_s = "#{foreign_key.from_table}.#{foreign_key.column} -> #{foreign_key.to_table}"
    end

    # Owned projects are handed to the heir, not deleted with the user.
    TRANSFERRED = [ %w[projects owner_id] ].freeze

    private

    def connection = ActiveRecord::Base.connection

    # Every foreign key that reaches `user`, with the SQL selecting the rows behind
    # it: the keys on `users`, then the keys on every table whose rows are deleted
    # along with the user, recursively. A nullified reference ends the walk.
    def references_reaching(user)
      foreign_keys = connection.tables.flat_map { |table| connection.foreign_keys(table) }
      pending = [ [ "users", user.id.to_s ] ]
      walked = Set["users"]
      references = []

      until pending.empty?
        table, ids = pending.shift
        foreign_keys.select { |fk| fk.to_table == table }.each do |fk|
          rows = "SELECT id FROM #{connection.quote_table_name(fk.from_table)} " \
                 "WHERE #{connection.quote_column_name(fk.column)} IN (#{ids})"
          references << Reference.new(foreign_key: fk, rows: rows)
          next if fk.on_delete == :nullify || TRANSFERRED.include?([ fk.from_table, fk.column ]) || walked.include?(fk.from_table)

          walked << fk.from_table
          pending << [ fk.from_table, rows ]
        end
      end
      references
    end
  end
end
