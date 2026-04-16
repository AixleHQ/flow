# frozen_string_literal: true

module Api
  module V1
    module Company
      class AssetsController < Api::V1::ApplicationController
        def create
          asset = find_or_initialize_asset(current_company)
          version = asset.versions.build(version_params)
          version.uploaded_by = current_user
          version.source = :upload

          ActiveRecord::Base.transaction do
            asset.save!
            version.save!
          end

          render json: AssetResource.new(asset).to_h, status: :created
        end

        def destroy
          asset = current_company.assets.find(params[:id])
          asset.soft_delete!
          render json: { id: asset.id }, status: :ok
        end

        def download
          asset = current_company.assets.find(params[:id])
          version = asset.resolve_version(params[:version])
          disposition = params[:inline] ? ::ContentDisposition.inline(asset.name)
                                        : ::ContentDisposition.attachment(asset.name)
          redirect_to version.file_url(response_content_disposition: disposition), allow_other_host: true
        end

        private

        def current_company
          @current_company ||= current_user.company
        end

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

        def version_params
          params.require(:asset).permit(:content_type, file: {})
        end
      end
    end
  end
end
