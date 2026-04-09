# frozen_string_literal: true

module Api
  module V1
    module Projects
      class WorkflowRunAssetsController < ApplicationController
        def index
          workflow_run = current_project.workflow_runs.find(params[:workflow_run_id])
          assets = workflow_run.workflow_run_assets.includes(:produced_by_step_run)
          render json: assets.map { |a| WorkflowRunAssetResource.new(a).to_h }
        end

        def export
          workflow_run = current_project.workflow_runs.find(params[:workflow_run_id])
          asset = workflow_run.workflow_run_assets.find(params[:id])

          result = AssetExportService.new(asset, project: current_project, user: current_user)
                     .export!(folder: export_params[:folder], public: export_params[:public] == true)

          render json: AssetResource.new(result[:asset]).to_h, status: :created
        end

        def download
          workflow_run = current_project.workflow_runs.find(params[:workflow_run_id])
          asset = workflow_run.workflow_run_assets.find(params[:id])

          unless asset.file
            return render json: { error: "File not available" }, status: :not_found
          end

          redirect_to asset.file.url, allow_other_host: true
        end

        def export_all
          workflow_run = current_project.workflow_runs.find(params[:workflow_run_id])
          assets = workflow_run.workflow_run_assets

          exported = assets.map do |wra|
            AssetExportService.new(wra, project: current_project, user: current_user)
              .export!(folder: export_params[:folder])
          end

          render json: { exported_count: exported.size }, status: :created
        end

        private

        def export_params
          params.permit(:folder, :public)
        end
      end
    end
  end
end
