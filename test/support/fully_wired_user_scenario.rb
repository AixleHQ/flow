# frozen_string_literal: true

# A user with a row behind every foreign key that reaches them: the tables that
# point at the user, and the tables that point at rows deleted along with them.
# Rows that outlive the user (history, authorship) belong to someone else's
# record — `heir`'s session, `heir`'s project — so a test can tell a nullified
# reference from a deleted row.
#
#   FullyWiredUserScenario.new(user:, company:, heir:).build
class FullyWiredUserScenario
  include FactoryBot::Syntax::Methods

  def initialize(user:, company:, heir:)
    @user = user
    @company = company
    @heir = heir
  end

  def build
    @project = create(:project, company: @company, owner: @heir)
    create(:project, company: @company, owner: @user)
    build_personal_data
    build_sign_ins
    build_board
    build_workflow
    build_company_records
    self
  end

  private

  def build_personal_data
    @credential = create(:agent_credential, user: @user, company: @company)
    @user.company_memberships.find_by!(company: @company).update!(default_agent_credential: @credential)
    create(:company_membership, company: @company, invited_by: @user)
    create(:project_collaborator, project: @project, user: @user)
    create(:project_favorite, project: @project, user: @user)
    OauthCredential.create!(owner: @user, provider: "sentry", status: :active, access_token: "at-mine", oauth_client: oauth_client)
    OauthCredential.create!(owner: @project, connected_by: @user, provider: "sentry", status: :active,
                            access_token: "at-project", oauth_client: oauth_client)
  end

  def build_sign_ins
    provider = create(:identity_provider, company: @company)
    create(:user_identity, user: @user, identity_provider: provider)
    Auth::SessionService.record_proof(UserSession.start!(user: @user), provider)
    UserSession.start!(user: @heir, impersonator: @user)
    MagicLinkToken.issue!(@user)
    WebauthnCredential.create!(user: @user, external_id: "passkey-1", public_key: "public-key")
    ChatIdentity.create!(provider: "slack", workspace_id: "T1", external_user_id: "U1", user: @user,
                         proof: "slack_sign_in", linked_at: Time.current)
    YoutrackPairing.start!(instance_url: "https://acme.youtrack.cloud", project: @project, user: @user)
  end

  def build_board
    @board = create(:board, project: @project)
    @column = create(:board_column, board: @board)
    task = create(:board_task, board: @board, board_column: @column, assignee: @user)
    BoardActivity.create!(board: @board, event_type: :task_created, actor: @user, actor_type: :human)
    ColumnTransition.create!(board_task: task, to_column: @column, actor: @user, actor_type: :human)
    BoardViewPreset.create!(board: @board, user: @user, name: "Mine", filters: { "state" => "active" })
    create(:task_comment, board_task: task, author: @user)
    create(:task_asset, board_task: task, author: @user, shared_by: @user)
    Gate.create!(board_task: task, creator: @user, gate_type: "github_checks_completed")
    create(:folder, path: "docs", scope: @project, created_by: @user)
  end

  def build_workflow
    workflow = create(:workflow, scope: @project, published_by: @user, published_at: Time.current)
    EntityVersion.create!(versionable: workflow, project_id: @project.id, company_id: @company.id, author: @user,
                          event: "created", source: "ui", number: 1)
    ColumnWorkflowBinding.create!(board_column: @column, workflow: workflow, created_by: @user)
    create(:trigger_binding, project: @project, workflow: workflow, created_by: @user)
    create(:trigger_event, actor: @user, event_type: "webhook.deploy", source: "webhook", project: @project,
                           company: @company)
    WebhookEndpoint.create_for_trigger!(project: @project, created_by: @user)
    TemplateInstall.create!(project: @project, installed_by: @user, namespace: "aixle", slug: "starter", version: 1,
                            commit_sha: "abc123", package_digest: "digest", idempotency_key: "install-1")

    run = create(:workflow_run, :completed, workflow: workflow, project: @project, user: @user)
    create(:workflow_run, :failed, workflow: workflow, project: @project, user: @heir,
                                   failed_agent_credential: @credential)
    create(:workflow_run_asset, workflow_run: run, shared_by: @user)
    create(:terminal_session, :agent_session, user: @user, project: @project, state: "finished")

    asset = create(:asset, scope: @project, created_by: @user, shared_by: @user)
    create(:asset_version, asset: asset, uploaded_by: @user)
  end

  def build_company_records
    create(:integration, company: @company, connected_by: @user)
    create(:runner, :manual, company: @company, created_by: @user)
    create(:azure_devops_installation, company: @company, approved_by: @user, approved_at: Time.current)
    create(:bitbucket_installation, :bound, company: @company, bound_by: @user)
    create(:billing_cancellation, company: @company, user: @user)
    conversation = ChatChannelTestHelper.connect_chat_channel(company: @company)
    ChatChannelConnection.find_by!(chat_conversation: conversation, company: @company).update!(requested_by: @user)
    ChatConnectCode.issue!(project: @project, provider: "slack", user: @user, channel: "#deploys")
    flag = FeatureFlag.create!(key: "external_runners", enabled: true, updated_by: @user)
    flag.overrides.create!(company: @company, enabled: false, reason: "asked to wait", created_by: @user)
  end

  def oauth_client
    @oauth_client ||= OauthClient.create!(issuer: "https://sentry.io", client_id: "c", source: "static",
                                          authorization_endpoint: "https://sentry.io/a",
                                          token_endpoint: "https://sentry.io/t")
  end
end
