# frozen_string_literal: true

module Api
  module V1
    module Company
      class FoldersController < Api::V1::ApplicationController
        # @summary Create a folder in the company's Assets folder view
        def create
          folder = folder_service.create!(params.require(:folder).require(:path))
          render json: FolderResource.new(folder).to_h, status: :created
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
        rescue FolderService::InvalidPathError, FolderService::CollisionError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        # @summary Rename or move a folder (and cascade to its contents)
        def relocate
          result = folder_service.relocate!(from_path: params.require(:from_path), to_path: params.require(:to_path))
          render json: DeepKeyCamelizer.call(result)
        rescue FolderService::InvalidPathError, FolderService::CollisionError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        # @summary Delete a folder — only when empty, unless `recursive` is set
        def destroy
          result = folder_service.destroy!(path: params.require(:path), recursive: recursive_param)
          render json: DeepKeyCamelizer.call(result)
        rescue FolderService::NotEmptyError => e
          render json: DeepKeyCamelizer.call({ error: e.message, item_count: e.item_count }),
                 status: :unprocessable_entity
        rescue FolderService::CollisionError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        def folder_service
          FolderService.new(scope: current_company, actor: current_user)
        end

        def recursive_param
          ActiveModel::Type::Boolean.new.cast(params[:recursive])
        end

        # The policy must judge read_only? against the RESOLVED company — a
        # viewer in their first company must not mutate its folders just
        # because they hold a writer role elsewhere.
        def policy_context
          BaseContext.new(current_user, params, company: current_company)
        end

        # API calls carry no web-session company; company-level folder endpoints
        # resolve the user's first active membership's company (mirrors
        # Api::V1::Company::AssetsController).
        def current_company
          @current_company ||= current_user.company_memberships.active
                                           .default_order
                                           .first&.company
          @current_company || raise(ActiveRecord::RecordNotFound)
        end
      end
    end
  end
end
