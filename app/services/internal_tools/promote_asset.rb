# frozen_string_literal: true

module InternalTools
  # Promotes an output asset produced by the current workflow run into a
  # durable, versioned project-level asset. If a project asset with the same
  # name and folder already exists, a new version is appended instead of
  # creating a duplicate (see AssetExportService).
  class PromoteAsset < Base
    tool do
      display_name "Promote Asset"
      description "Promote a workflow/session output asset to a versioned project-level asset. " \
                  "If a project asset with the same name and folder already exists, a new version " \
                  "is added instead of creating a duplicate. " \
                  "Only use this tool when the step instructions explicitly ask to promote (or save/publish) " \
                  "an asset; do not call it on your own initiative."
      tags :assets
      inject_when :workflow_step_session
      param :name, type: :string, required: true,
                   description: "Name of the workflow output asset to promote (as produced by the run)."
      param :folder, type: :string,
                     description: "Optional destination folder within project assets " \
                                  "(letters, digits, hyphens, underscores only)."
    end

    def execute
      require_workflow_context!
      return error("No project in the current context") unless project

      wra = find_workflow_run_asset
      return error("No workflow output asset named '#{params[:name]}' found in this run") unless wra

      promoter = workflow_run&.user
      return error("Cannot determine the promoting user") unless promoter

      result = AssetExportService.new(wra, project: project, user: promoter)
                                 .export!(folder: params[:folder].presence)

      asset = result[:asset]
      success({
        asset_id: asset.id,
        name: asset.name,
        folder: asset.folder,
        scope: asset.scope_indicator,
        version: result[:version]&.version,
        public: asset.public,
        share_url: asset.share_url
      }.to_json)
    end

    private

    def find_workflow_run_asset
      candidates = workflow_run.workflow_run_assets.where(name: params[:name])
      candidates.find_by(produced_by_step_run_id: step_run.id) ||
        candidates.order(created_at: :desc).first
    end
  end
end
