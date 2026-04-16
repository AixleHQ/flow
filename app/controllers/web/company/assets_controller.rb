# frozen_string_literal: true

class Web::Company::AssetsController < Web::Company::ApplicationController
  def index
    assets = current_company.assets
                            .active
                            .includes(:versions, :created_by)
                            .order(updated_at: :desc)

    props = {
      assets: assets.map { |a| AssetResource.new(a).to_h }
    }

    if params[:history_asset_id].present?
      asset = current_company.assets.find(params[:history_asset_id])
      props[:asset_versions] = asset.versions.order(version: :desc).map { |v| AssetVersionResource.new(v).to_h }
    end

    render inertia: "Company/Assets/Index", props: props
  end
end
