# frozen_string_literal: true

module InternalTools
  # Makes a project-level asset publicly accessible and returns a stable share
  # link. The link is served through a public viewer that renders the asset
  # inside a sandboxed iframe, and its token lives on the asset — so the URL
  # stays the same even as new versions are promoted.
  #
  # Only this project's own assets: a company asset is shared by every project in
  # the company, and one step's session publishing it to the internet is not that
  # project's call to make. Every share records the session that made it.
  class ShareAsset < Base
    tool do
      display_name "Share Asset"
      description "Make a project-level asset publicly accessible and return a stable, safe share link. " \
                  "The link renders the asset inside a sandboxed iframe and does not change across " \
                  "asset versions. " \
                  "Only use this tool when the step instructions explicitly ask to share (or make public) " \
                  "an asset; do not call it on your own initiative."
      tags :assets
      inject_when :workflow_step_session
      idempotent
      param :asset_id, type: :integer,
                       description: "ID of the project asset to share (e.g. the value returned by promote_asset)."
      param :name, type: :string,
                   description: "Asset name to share (alternative to asset_id)."
      param :folder, type: :string,
                     description: "Folder of the asset when resolving by name."
    end

    def execute
      require_workflow_context!
      return error("No project in the current context") unless project
      return error("Provide asset_id or name") if params[:asset_id].blank? && params[:name].blank?

      asset = resolve_asset
      return error("Asset not found in this project — only the project's own assets can be shared") unless asset

      asset.share!(session: session)
      success({
        asset_id: asset.id,
        name: asset.name,
        public: true,
        share_url: asset.share_url
      }.to_json)
    end

    private

    def resolve_asset
      scope = Asset.active.where(scope_type: "Project", scope_id: project.id)
      if params[:asset_id].present?
        scope.find_by(id: params[:asset_id])
      else
        scope.find_by(name: params[:name], folder: Asset.normalize_folder(params[:folder]))
      end
    end
  end
end
