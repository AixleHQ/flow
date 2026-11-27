# frozen_string_literal: true

# A session now gets a tool only when its workflow, its step or the session itself
# attached it (docs/design/tool-attachment.md). The tools that used to arrive by rule
# are attached here, to each step the old rules would have served, so every existing
# workflow keeps what it could do. Afterwards a step can remove them like any other tool.
#
# The old rules are deleted from the app, so this migration keeps its own copy of their
# predicates. It reads the tables through inline models and loads no app class.
#
# Left out on purpose:
# - System workflows (no project): the Aixle Builder is not a workflow run.
# - Workflows under `inherit_all_project_resources`: they already reach every attachable
#   tool of the project, so they get no platform link and no custom-tool fallback.
# - The plumbing tools, which stay automatic.
#
# Idempotent: a link that exists is not added again. Prints one summary line.
class AttachFormerlyInjectedTools < ActiveRecord::Migration[8.1]
  BOARD_AND_ASSET_TOOLS = %w[
    board_add_comment board_attach_asset board_create_gate board_create_task board_get_board_info
    board_get_comments board_get_task board_get_task_assets board_list_gates board_list_members
    board_list_tasks board_manage_tags board_move_task board_update_task
    share_asset promote_asset
  ].freeze

  CHAT_TOOLS = %w[chat_delete_message chat_post_message chat_read_thread chat_update_message].freeze

  CODER_TOOLS = %w[coder_allocate_machine coder_job_status coder_prepare_repo coder_release_machine coder_ssh_exec].freeze

  AZURE_BUILD_TOOLS = %w[azure_devops_list_builds azure_devops_list_connections].freeze

  AZURE_PULL_REQUEST_TOOLS = %w[
    azure_devops_add_pull_request_reviewer azure_devops_complete_pull_request azure_devops_create_pull_request
    azure_devops_create_pull_request_thread azure_devops_get_pull_request azure_devops_get_pull_request_changes
    azure_devops_get_pull_request_policies azure_devops_link_work_item azure_devops_list_pull_request_reviewers
    azure_devops_list_pull_request_threads azure_devops_list_pull_requests azure_devops_reply_pull_request_thread
    azure_devops_update_pull_request azure_devops_update_pull_request_thread azure_devops_vote_pull_request
  ].freeze

  TRACKER_TOOLS = %w[
    tracker_add_comment tracker_assign_issue tracker_attach_files tracker_create_issue tracker_describe
    tracker_download_attachments tracker_get_issue tracker_link_task tracker_list tracker_list_attachments
    tracker_list_comments tracker_list_users tracker_search_issues tracker_transition_issue tracker_update_issue
  ].freeze

  GITHUB_TOOLS = %w[refresh_github_token].freeze

  CHAT_PROVIDERS = %w[slack teams].freeze
  TRACKER_EVENT_PREFIX = "tracker."

  class MigrationWorkflow < ActiveRecord::Base
    self.table_name = "workflows"
  end

  class MigrationStep < ActiveRecord::Base
    self.table_name = "steps"
  end

  class MigrationWorkflowLink < ActiveRecord::Base
    self.table_name = "workflow_resource_links"
  end

  class MigrationStepLink < ActiveRecord::Base
    self.table_name = "step_resource_links"
  end

  def up
    @tool_ids = select_rows(<<~SQL.squish).to_h { |id, name| [ name, id.to_i ] }
      SELECT id, name FROM tools WHERE source = 'code' AND deleted_at IS NULL
        AND name IN (#{all_platform_tools.map { |name| connection.quote(name) }.join(', ')})
    SQL
    @added = Hash.new(0)
    @workflows_touched = 0

    MigrationWorkflow.where(deleted_at: nil, scope_type: "Project").where.not(project_id: nil).find_each do |workflow|
      next if inherits_everything?(workflow)

      attach_to_workflow_steps(workflow)
    end

    summary = @added.sort.map { |name, count| "#{name}=#{count}" }.join(" ")
    say "attach_formerly_injected_tools: #{@workflows_touched} workflows touched; links added: #{summary.presence || 'none'}"
  end

  def down
    # Irreversible by intent: after this runs, a step's tool may have been attached by a
    # person, and nothing records which links came from here.
  end

  private

  def all_platform_tools
    BOARD_AND_ASSET_TOOLS + CHAT_TOOLS + CODER_TOOLS + AZURE_BUILD_TOOLS +
      AZURE_PULL_REQUEST_TOOLS + TRACKER_TOOLS + GITHUB_TOOLS
  end

  def inherits_everything?(workflow)
    workflow.config.is_a?(Hash) && workflow.config["inherit_all_project_resources"] == true
  end

  def attach_to_workflow_steps(workflow)
    names = BOARD_AND_ASSET_TOOLS.dup
    names += CHAT_TOOLS if integration_active?(workflow, CHAT_PROVIDERS)
    names += CODER_TOOLS if integration_active?(workflow, %w[coder])
    names += AZURE_BUILD_TOOLS if integration_active?(workflow, %w[azure_devops])
    names += AZURE_PULL_REQUEST_TOOLS if project_repository?(workflow, "azure_devops")
    names += TRACKER_TOOLS if tracker_binding?(workflow)
    names += GITHUB_TOOLS if project_repository?(workflow, "github")

    platform_ids = names.filter_map { |name| @tool_ids[name] }
    base_tool_ids = MigrationWorkflowLink.where(workflow_id: workflow.id).where.not(tool_id: nil).pluck(:tool_id)
    custom_ids = custom_tool_ids(workflow)
    base_has_custom = (base_tool_ids & custom_ids).any?

    touched = false
    MigrationStep.where(workflow_id: workflow.id, deleted_at: nil).find_each do |step|
      links = MigrationStepLink.where(step_id: step.id)
      step_tool_ids = links.where.not(tool_id: nil).pluck(:tool_id)

      wanted = platform_ids.dup
      wanted += custom_ids unless base_has_custom || (step_tool_ids & custom_ids).any?
      missing = wanted.uniq - step_tool_ids
      next if missing.empty?

      position = links.maximum(:position).to_i
      missing.each_with_index do |tool_id, index|
        MigrationStepLink.create!(step_id: step.id, tool_id: tool_id, position: position + index + 1)
        @added[tool_name(tool_id)] += 1
      end
      touched = true
    end
    @workflows_touched += 1 if touched
  end

  # Same predicate as Tools::Context#connected_providers: an active integration of the
  # workflow's company, company-wide or for the workflow's project.
  def integration_active?(workflow, providers)
    select_value(<<~SQL.squish).present?
      SELECT 1 FROM integrations
        WHERE status = 'active' AND company_id = #{workflow.company_id.to_i}
          AND (project_id IS NULL OR project_id = #{workflow.project_id.to_i})
          AND provider IN (#{providers.map { |provider| connection.quote(provider) }.join(', ')})
        LIMIT 1
    SQL
  end

  # Repository.visible_for_project: project-scoped repositories, whatever the step lists.
  def project_repository?(workflow, provider)
    select_value(<<~SQL.squish).present?
      SELECT 1 FROM repositories
        JOIN integrations ON integrations.id = repositories.integration_id
        WHERE repositories.scope_type = 'Project' AND repositories.scope_id = #{workflow.project_id.to_i}
          AND integrations.provider = #{connection.quote(provider)}
        LIMIT 1
    SQL
  end

  # A binding with or without a tracker, enabled or not: the old rule asked only whether
  # the run came from a tracker event.
  def tracker_binding?(workflow)
    select_value(<<~SQL.squish).present?
      SELECT 1 FROM trigger_bindings
        WHERE workflow_id = #{workflow.id.to_i}
          AND left(event_type, #{TRACKER_EVENT_PREFIX.length}) = #{connection.quote(TRACKER_EVENT_PREFIX)}
        LIMIT 1
    SQL
  end

  def custom_tool_ids(workflow)
    select_values(<<~SQL.squish).map(&:to_i)
      SELECT id FROM tools
        WHERE source = 'db' AND deleted_at IS NULL AND enabled IS NOT FALSE
          AND scope_type = 'Project' AND scope_id = #{workflow.project_id.to_i}
    SQL
  end

  def tool_name(tool_id)
    @tool_names ||= {}
    @tool_names[tool_id] ||= @tool_ids.key(tool_id) || "custom"
  end
end
