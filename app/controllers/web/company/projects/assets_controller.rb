# frozen_string_literal: true

class Web::Company::Projects::AssetsController < Web::Company::Projects::ApplicationController
  def index
    assets = Asset.accessible_from_project(current_project)
                  .includes(:versions, :created_by)
                  .order(updated_at: :desc)

    props = {
      project: project_props,
      assets: assets.map { |a| AssetResource.new(a).to_h }
    }

    if params[:history_asset_id].present?
      asset = Asset.accessible_from_project(current_project).find(params[:history_asset_id])
      props[:asset_versions] = asset.versions.order(version: :desc).map { |v| AssetVersionResource.new(v).to_h }
    end

    render inertia: "Projects/Assets/AssetsPage", props: props
  end
end
