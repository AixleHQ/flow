# frozen_string_literal: true

module Templates
  # The actions behind a template install's post-install checklist (design §7.5).
  #
  # Items the user completes here (a secret, a repository, activating a
  # trigger) are marked done by the action. Items that depend on something done
  # elsewhere — an integration connected, an OAuth sign-in — resolve themselves
  # in #refresh!, which the checklist page calls on every render.
  class SetupChecklist
    Error = Class.new(StandardError)

    def initialize(install, user:)
      @install = install
      @project = install.project
      @user = user
    end

    def items = @install.setup_items.reload

    def refresh!
      connected = Tool.active_integration_providers(@project)
      @install.setup_items.where(status: %w[pending failed]).find_each do |item|
        done = case item.kind
        when "integration" then connected.include?(item.detail["provider"])
        when "oauth" then oauth_connected?(item)
        when "secret" then adopt_existing_secret(item)
        else false
        end
        item.update!(status: "done") if done
      end
      self
    end

    # Creates the secret and attaches it wherever the template referenced it.
    def add_secret!(item, value)
      expect_kind!(item, "secret")
      raise Error, "Enter a value" if value.blank?

      ActiveRecord::Base.transaction do
        config_item = ConfigItem.for_project(@project).find_by(name: item.detail["name"]) ||
                      @project.config_items.create!(name: item.detail["name"], item_type: "secret", value: value,
                                                    description: item.detail["description"])
        attach!(item, workflow_key: "base_config_item_ids", step_column: :config_item_ids, id: config_item.id)
        item.update!(status: "done")
      end
    end

    # Attaches one of the project's repositories wherever the template needed one.
    def attach_repository!(item, repository_id)
      expect_kind!(item, "repository")
      repository = @project.repositories.find(repository_id)

      ActiveRecord::Base.transaction do
        attach!(item, workflow_key: "base_repository_ids", step_column: :repository_ids, id: repository.id)
        item.update!(status: "done", detail: item.detail.merge("repository_id" => repository.id))
      end
    end

    # Switches an installed trigger on, restoring the template's own mode. The
    # off-board kinds still have to pass TriggerBinding's auto-run rule, so a
    # workflow with a manual step is refused here with the model's message.
    def activate_trigger!(item)
      expect_kind!(item, "trigger")
      raise Error, item.detail["missing"] if item.detail["missing"]

      if item.detail["record"] == "column"
        column_bindings.find(item.detail["trigger_id"]).update!(trigger_mode: item.detail["activate_mode"])
      else
        TriggerBinding.where(project: @project).find(item.detail["trigger_id"])
                      .update!(enabled: true, trigger_mode: item.detail["activate_mode"])
      end
      item.update!(status: "done")
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    end

    def recheck!(item)
      raise Error, "Only a server can be checked again" unless %w[oauth probe].include?(item.kind)

      ProbeServersJob.perform_later(@install.id, [ item.detail["server_id"] ])
    end

    def dismiss!(item) = item.update!(status: "dismissed")

    private

    def expect_kind!(item, kind)
      raise Error, "Not a #{kind} item" unless item.kind == kind && item.template_install_id == @install.id
    end

    def attach!(item, workflow_key:, step_column:, id:)
      targets = item.detail["attach_to"].to_h
      @project.workflows.where(id: targets["workflow_ids"]).find_each do |workflow|
        ids = Array(workflow.config[workflow_key])
        workflow.update!(config: workflow.config.merge(workflow_key => (ids | [ id ])))
      end
      Step.joins(:workflow).where(id: targets["step_ids"], workflows: { scope_type: "Project", scope_id: @project.id })
          .find_each { |step| step.update!(step_column => (step.public_send(step_column) | [ id ])) }
    end

    def column_bindings
      ColumnWorkflowBinding.joins(board_column: :board).where(boards: { project_id: @project.id })
    end

    def oauth_connected?(item)
      MCPServer.where(scope: @project, id: item.detail["server_id"]).joins(:oauth_credentials)
               .merge(OauthCredential.with_status(:active)).exists?
    end

    # A secret with the same name added elsewhere (the project's config page)
    # counts: it is attached where the template needed it.
    def adopt_existing_secret(item)
      config_item = ConfigItem.for_project(@project).find_by(name: item.detail["name"])
      return false unless config_item

      attach!(item, workflow_key: "base_config_item_ids", step_column: :config_item_ids, id: config_item.id)
      true
    end
  end
end
