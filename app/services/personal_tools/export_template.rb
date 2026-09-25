# frozen_string_literal: true

module PersonalTools
  # Packages a working project (or some of its workflows) as a catalog template
  # and hands it back to the caller. Read-only: nothing is stored server-side,
  # and publishing is the caller's own pull request (see the publish_template
  # prompt) — Flow holds no token for the templates repository.
  class ExportTemplate < Base
    tool do
      display_name "Export Template"
      description "Export a project, some of its workflows, or single agents and skills as a template package: " \
                  "template.yaml plus the files next to it. For an agent or skill template pass workflow_ids: [] " \
                  "and include_board: false with agent_ids / skill_ids. " \
                  "Secrets are exported by name only; variables with their values. Anything " \
                  "that cannot be carried faithfully (a literal MCP header, an unpinned image) aborts the export " \
                  "with the reason. Follow the publish_template prompt to open the catalog pull request."
      audience :user
      tags :templates
      read_only
      param :project_id, type: :integer, description: "Project id.", required: true
      param :slug, type: :string, description: "Template slug: lowercase words joined by dashes.", required: true
      param :name, type: :string, description: "Template name shown in the catalog.", required: true
      param :summary, type: :string, description: "One-sentence catalog summary."
      param :workflow_ids, type: :array, items: { type: "integer" },
                           description: "Only these workflows. Omit to export every workflow; [] for none."
      param :agent_ids, type: :array, items: { type: "integer" }, description: "Agents to export on their own."
      param :skill_ids, type: :array, items: { type: "integer" }, description: "Skills to export on their own."
      param :include_board, type: :boolean, description: "Export the board and its column triggers (default true)."
      param :include_assets, type: :boolean, description: "Export the project assets the workflows use (default false)."
    end

    def execute
      project = find_project!
      authorize!(project, :index?, policy: Web::Company::Projects::WorkflowsPolicy, project: project)

      result = Templates::Exporter.new(
        project: project, slug: params[:slug].to_s, name: params[:name].to_s, summary: params[:summary],
        workflow_ids: params.key?(:workflow_ids) ? Array(params[:workflow_ids]) : nil,
        agent_ids: Array(params[:agent_ids]), skill_ids: Array(params[:skill_ids]),
        include_board: params[:include_board] != false,
        include_assets: params[:include_assets] == true
      ).call
      success(directory: "templates/#{params[:slug]}", template_yaml: result.template_yaml,
              files: result.package.files.map { |path, bytes| file_entry(path, bytes) }, notes: result.notes)
    rescue Templates::Exporter::ExportError => e
      error("Export refused:\n- #{e.errors.join("\n- ")}")
    end

    private

    def file_entry(path, bytes)
      text = bytes.dup.force_encoding(Encoding::UTF_8)
      text.valid_encoding? ? { path: path, content: text } : { path: path, base64: Base64.strict_encode64(bytes) }
    end
  end
end
