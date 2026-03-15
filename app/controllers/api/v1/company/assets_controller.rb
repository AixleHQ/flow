# frozen_string_literal: true

module Api
  module V1
    module Company
      class AssetsController < ApplicationController
        def index
          assets = current_company.assets.where(deleted_at: nil).ransack(params[:q]).result.includes(:versions)
          respond_with assets, each_serializer: AssetSerializer
        end

        def show
          asset = current_company.assets.find(params[:id])
          respond_with asset, serializer: AssetDetailSerializer
        end

        def versions
          asset = current_company.assets.find(params[:id])
          respond_with asset.versions.order(version: :desc),
                       each_serializer: AssetVersionSerializer
        end

        def download
          asset = current_company.assets.find(params[:id])
          version = asset.resolve_version(params[:version])

          disposition = params[:inline] ? ::ContentDisposition.inline(asset.name)
                                        : ::ContentDisposition.attachment(asset.name)

          redirect_to version.file_url(
            response_content_disposition: disposition
          ), allow_other_host: true
        end

        def create
          asset = find_or_initialize_asset(current_company)

          version = asset.versions.build(version_params)
          version.uploaded_by = current_user
          version.source = :upload

          ActiveRecord::Base.transaction do
            asset.save!
            version.save!
          end

          respond_with asset, serializer: AssetSerializer, status: :created
        end

        def update
          asset = current_company.assets.find(params[:id])
          asset.update(asset_update_params)
          respond_with asset, serializer: AssetSerializer
        end

        def destroy
          asset = current_company.assets.find(params[:id])
          asset.soft_delete!
          respond_with asset
        end

        def restore
          asset = current_company.assets.find(params[:id])
          asset.restore!
          respond_with asset, serializer: AssetSerializer
        end

        private

        def find_or_initialize_asset(scope)
          asset = scope.assets.find_or_initialize_by(name: asset_params[:name]) do |a|
            a.created_by = current_user
          end
          asset.restore! if asset.persisted? && asset.deleted?
          asset.assign_attributes(asset_params.except(:name))
          asset
        end

        def asset_params
          params.require(:asset).permit(:name, :folder, :public, tags: [])
        end

        def asset_update_params
          params.require(:asset).permit(:name, :folder, :public, tags: [])
        end

        def version_params
          params.require(:asset).permit(:content_type, file: {})
        end
      end
    end
  end
end
