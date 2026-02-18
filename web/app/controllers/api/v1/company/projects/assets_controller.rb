# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        class AssetsController < ApplicationController
          def index
            assets = Asset.merged_for_project(current_project)
            respond_with assets, each_serializer: Api::V1::AssetSerializer
          end

          def create
            asset = find_or_initialize_asset(current_project)

            version = asset.versions.build(version_params)
            version.uploaded_by = current_user

            ActiveRecord::Base.transaction do
              asset.save!
              version.save!
            end

            respond_with asset, serializer: Api::V1::AssetSerializer, status: :created
          end

          def update
            asset = current_project.assets.find(params[:id])
            asset.update(asset_update_params)
            respond_with asset, serializer: Api::V1::AssetSerializer
          end

          def destroy
            asset = current_project.assets.find(params[:id])
            asset.destroy
            respond_with asset
          end

          private

          def find_or_initialize_asset(scope)
            scope.assets.find_or_initialize_by(name: asset_params[:name]) do |a|
              a.created_by = current_user
              a.asset_type = asset_params[:asset_type] || "document"
            end
          end

          def asset_params
            params.require(:asset).permit(:name, :asset_type, :folder, :public, tags: [])
          end

          def asset_update_params
            params.require(:asset).permit(:folder, :public, :asset_type, tags: [])
          end

          def version_params
            params.require(:asset).permit(:file, :cached_attachment_data, :content_type, provenance: {})
          end
        end
      end
    end
  end
end
