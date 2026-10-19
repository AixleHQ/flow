# frozen_string_literal: true

# A project with something in every place a project move touches: board, history,
# triggers, project resources, integrations on both sides of the company line,
# company assets its steps point at, people inside and outside the target, a run
# that has not started, and a reservation the target cannot hold.
#
#   scenario = ProjectMoveScenario.new.build
#   scenario.project, scenario.target, scenario.outsider, ...
class ProjectMoveScenario
  include FactoryBot::Syntax::Methods

  attr_reader :source, :target, :owner, :shared_member, :outsider, :target_admin, :project, :board, :parent_task,
              :child_task, :comment, :workflow, :step, :sub_step, :completed_run, :pending_run, :finished_session,
              :company_asset, :project_asset, :company_repository, :project_repository, :project_integration,
              :company_integration, :schedule_binding, :chat_binding, :webhook_endpoint, :reservation,
              :trigger_event, :entity_version, :config_item, :mcp_server, :tool, :skill, :agent, :folder

  def build(password: AuthHelper::TEST_PASSWORD)
    @source = create(:company, name: "Northwind")
    @target = create(:company, name: "Contoso")
    SessionConcurrencyLimit.set!(scope: @target, max_sessions: 1)

    @owner = create(:user, :admin, :onboarding_completed, company: @source, name: "Olga Owner", password: password)
    create(:company_membership, user: @owner, company: @target, role: "employee", state: "active", accepted_at: Time.current)
    @shared_member = create(:user, :onboarding_completed, company: @source, name: "Sam Shared")
    create(:company_membership, user: @shared_member, company: @target, role: "employee", state: "active", accepted_at: Time.current)
    @outsider = create(:user, :onboarding_completed, company: @source, name: "Oscar Outsider")
    @target_admin = create(:user, :admin, :onboarding_completed, company: @target, name: "Tina Target")

    @project = create(:project, company: @source, owner: @owner, name: "Launchpad")
    @project.add_collaborator(@shared_member)
    @project.add_collaborator(@outsider)
    create(:project, company: @target, owner: @target_admin, name: "Launchpad")

    build_board
    build_resources
    build_workflow
    build_history
    build_integrations
    build_triggers
    self
  end

  private

  def build_board
    @board = create(:board, project: @project)
    todo = create(:board_column, board: @board, name: "To do")
    create(:board_column, board: @board, name: "Done")
    @parent_task = create(:board_task, board: @board, board_column: todo, title: "Ship the launch", task_type: :epic,
                                       assignee: @outsider)
    @child_task = create(:board_task, board: @board, board_column: todo, title: "Write release notes",
                                      parent_task: @parent_task, assignee: @shared_member)
    @comment = create(:task_comment, board_task: @parent_task, author: @owner, body: "Starting today")
    create(:task_asset, board_task: @parent_task, author: @owner)
  end

  def build_resources
    @config_item = create(:config_item, :secret, scope: @project, name: "DEPLOY_TOKEN")
    @mcp_server = create(:mcp_server, scope: @project)
    @tool = create(:tool, scope: @project)
    @skill = create(:skill, scope: @project)
    @agent = create(:agent, scope: @project)
    @folder = create(:folder, scope: @project, path: "specs", created_by: @owner)
    @project_asset = create(:asset, scope: @project, folder: "specs", name: "brief.md", created_by: @owner)
    create(:asset_version, :with_file, asset: @project_asset, uploaded_by: @owner)
    @company_asset = create(:asset, scope: @source, folder: "handbook", name: "style.md", created_by: @owner)
    create(:asset_version, :with_file, asset: @company_asset, uploaded_by: @owner)
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 2)
    @reservation = @project.session_concurrency_limit
  end

  def build_workflow
    @workflow = create(:workflow, scope: @project, name: "Release", config: { "base_asset_ids" => [ @company_asset.id ] })
    @step = create(:step, :non_interactive, workflow: @workflow, name: "Draft", asset_ids: [ @company_asset.id ],
                                            instructions: "Follow {{asset:#{@company_asset.id}}} closely.")
    @sub_step = create(:sub_step, step: @step, instructions: "Check against {{asset:#{@company_asset.id}}}.")
    @entity_version = EntityVersion.create!(versionable: @workflow, project_id: @project.id, company_id: @source.id,
                                            author_id: @owner.id, event: "created", source: "ui", number: 1)
  end

  def build_history
    @completed_run = create(:workflow_run, :completed, workflow: @workflow, project: @project, user: @owner)
    @finished_session = create(:terminal_session, :agent_session, project: @project, user: @owner, state: "finished",
                                                                  started_at: 2.hours.ago, finished_at: 1.hour.ago)
    create(:step_run, :completed, workflow_run: @completed_run, step: @step, terminal_session: @finished_session)
    @pending_run = create(:workflow_run, workflow: @workflow, project: @project, user: @owner)
    @trigger_event = create(:trigger_event, event_type: "webhook.deploy", source: "webhook", project: @project,
                                            company: @source)
  end

  def build_integrations
    @company_integration = create(:integration, :github, :active, company: @source, name: "northwind-org")
    @company_repository = create(:repository, scope: @project, integration: @company_integration,
                                              full_name: "northwind/site")
    @project_integration = create(:integration, :github_pat, :active, company: @source, project: @project,
                                                                      name: "launchpad-pat")
    @project_repository = create(:repository, scope: @project, integration: @project_integration,
                                              full_name: "octodev/launchpad")
  end

  def build_triggers
    @schedule_binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @owner,
                                                 name: "Nightly", event_type: TriggerBinding::SCHEDULE_EVENT_TYPE,
                                                 schedule_config: { "cron" => "0 3 * * *" })
    @chat_binding = create(:trigger_binding, project: @project, workflow: @workflow, created_by: @owner, name: "Ask in Slack")
    @webhook_endpoint = create(:webhook_endpoint, :generic, project: @project, company: @source, slug: "launchpad-deploy")
  end
end
