# frozen_string_literal: true

module Tools
  # The Aixle Builder's tools are the personal MCP tools, served inside the
  # builder session and pinned to its project. They run as the user who started
  # the session, through the same Pundit policies as the personal server and the
  # UI, so the builder can do exactly what that user could do in this project.
  #
  # A tool qualifies when it requires `project_id` — the personal tools that act
  # on one project — or is a session reader, which pinning narrows to the
  # project's sessions. The session fills `project_id` in, so it is dropped from
  # the schema the agent sees. The personal token never enters the container.
  module BuilderToolset
    SESSION_READERS = %w[list_sessions get_session_log].freeze

    # Secret values would have to pass through the agent's transcript, and the
    # builder does not author custom tools or change project settings.
    EXCLUDED = %w[
      create_config_item update_config_item delete_config_item
      create_custom_tool update_custom_tool delete_custom_tool
      update_project_settings
    ].freeze

    ACTIVITY_ENTITIES = {
      "workflow_step" => "Step", "sub_step" => "SubStep", "workflow_trigger" => "Trigger",
      "board_column" => "BoardColumn", "board_task" => "BoardTask", "board_comment" => "BoardTask",
      "workflow_steps" => "Step", "sub_steps" => "SubStep", "board_columns" => "BoardColumn",
      "workflow" => "Workflow", "agent" => "Agent", "skill" => "Skill", "mcp_server" => "MCPServer",
      "repository" => "Repository", "connector" => "MCPServer", "board" => "Board",
      "step_run" => "WorkflowRun", "workflow_run" => "WorkflowRun"
    }.freeze

    class << self
      def definitions
        Registry.for_audience(:user)
                .select { |d| (project_scoped?(d) || SESSION_READERS.include?(d.name.to_s)) && EXCLUDED.exclude?(d.name.to_s) }
                .sort_by(&:name)
      end

      def serves?(session)
        session&.aixle_builder? && session.project.present? && session.user.present?
      end

      def input_schema(defn)
        schema = defn.input_schema.deep_stringify_keys.deep_dup
        schema["properties"]&.delete("project_id")
        schema["required"] = Array(schema["required"]) - [ "project_id" ]
        schema
      end

      def execute(defn, arguments, session)
        handler = defn.handler_class.new(
          params: arguments.deep_stringify_keys.merge("project_id" => session.project_id),
          user: session.user,
          pinned_project: session.project
        )
        result = handler.execute
        record_activity(defn, result, session) if result[:exit_code].zero? && !read_only?(defn)
        result
      rescue PersonalTools::Base::UnauthorizedError, PersonalTools::Base::NotFoundError => e
        { exit_code: 1, stdout: "", stderr: e.message }
      end

      private

      def project_scoped?(defn)
        Array(defn.input_schema.deep_stringify_keys["required"]).include?("project_id")
      end

      def read_only?(defn)
        defn.annotations["readOnlyHint"] == true
      end

      # Feeds the builder session page's activity feed.
      def record_activity(defn, result, session)
        payload = parse(result[:stdout])
        activity = {
          "action" => defn.name.to_s,
          "entity_type" => entity_type(defn.name.to_s),
          "entity_name" => payload["name"] || payload["title"] || payload["full_name"],
          "entity_id" => payload["id"],
          "timestamp" => Time.current.iso8601
        }.compact

        session.with_lock do
          metadata = session.metadata || {}
          metadata["builder_activities"] = (Array(metadata["builder_activities"]) << activity).last(100)
          session.update!(metadata: metadata)
        end
      rescue StandardError => e
        Rails.logger.warn("[BuilderToolset] activity not recorded for #{defn.name}: #{e.class} — #{e.message}")
      end

      def entity_type(name)
        noun = name.sub(/\A[a-z]+_/, "")
        ACTIVITY_ENTITIES[noun] || noun.camelize
      end

      def parse(stdout)
        value = JSON.parse(stdout.to_s)
        value.is_a?(Hash) ? value : {}
      rescue JSON::ParserError
        {}
      end
    end
  end
end
