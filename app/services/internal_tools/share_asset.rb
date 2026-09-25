# frozen_string_literal: true

module InternalTools
  # Publishes a file at a stable share link: a project asset, an output of this
  # workflow run, or a file attached to a task on this project's board. The link
  # is served through a public viewer that renders the file inside a sandboxed
  # iframe, and its token lives on the file — so a project asset's URL stays the
  # same even as new versions are promoted.
  #
  # Never a company asset: every project of the company sees one, and one step's
  # session publishing it to the internet is not that project's call to make.
  # Every share records the session that made it.
  class ShareAsset < Base
    SOURCES = %w[project run task].freeze

    tool do
      display_name "Share Asset"
      description "Make an asset publicly accessible and return a stable, safe share link: a project asset " \
                  "(source \"project\", the default), an output of this workflow run (source \"run\"), or a " \
                  "file attached to a board task (source \"task\", with task_id). Company assets cannot be " \
                  "shared. A file this session writes to /workspace/outputs becomes a run output only after " \
                  "the session ends. The link renders the asset inside a sandboxed iframe and does not change " \
                  "across asset versions. " \
                  "Only use this tool when the step instructions explicitly ask to share (or make public) " \
                  "an asset; do not call it on your own initiative."
      tags :assets
      inject_when :workflow_step_session
      idempotent
      param :source, type: :string, enum: SOURCES,
                     description: "Where the asset lives: project (default), run or task."
      param :asset_id, type: :integer,
                       description: "ID of the asset to share (e.g. the value returned by promote_asset, " \
                                    "or a task asset id from board_get_task_assets)."
      param :name, type: :string,
                   description: "Asset name to share (alternative to asset_id)."
      param :folder, type: :string,
                     description: "Folder of a project asset when resolving by name."
      param :task_id, type: :integer,
                      description: "Board task whose attached file to share (source task)."
    end

    def execute
      require_workflow_context!
      return error("No project in the current context") unless project
      return error("source must be one of: #{SOURCES.join(', ')}") unless SOURCES.include?(source)
      return error("Provide asset_id or name") if params[:asset_id].blank? && params[:name].blank?
      return error("Provide task_id to share a task's asset") if source == "task" && params[:task_id].blank?

      candidates = candidate_scope
      return error("Task not found on this board") unless candidates

      asset = resolve(candidates)
      return error(not_found_message) unless asset

      asset.share!(session: session)
      success({
        source: source,
        asset_id: asset.id,
        name: asset.name,
        public: true,
        share_url: asset.share_url
      }.to_json)
    end

    private

    def source
      params[:source].presence || "project"
    end

    def candidate_scope
      case source
      when "project" then Asset.active.where(scope_type: "Project", scope_id: project.id)
      when "run" then workflow_run.workflow_run_assets
      when "task" then BoardContextResolver.resolve(session)&.board_tasks&.find_by(id: params[:task_id])&.task_assets
      end
    end

    def resolve(scope)
      return scope.find_by(id: params[:asset_id]) if params[:asset_id].present?
      return scope.find_by(name: params[:name], folder: Asset.normalize_folder(params[:folder])) if source == "project"

      scope.where(name: params[:name]).order(created_at: :desc).first
    end

    def not_found_message
      case source
      when "project" then "Asset not found in this project — only the project's own assets can be shared"
      when "run" then "No output of this workflow run matches — outputs of this session appear only after it ends"
      else "Asset not found on this task"
      end
    end
  end
end
