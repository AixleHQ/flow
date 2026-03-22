# frozen_string_literal: true

module Api
  module V1
    module Company
      module TerminalSessions
        class ArtifactsController < ApplicationController
          def index
            artifacts = current_session.output_assets.pending_review.order(:name)
            respond_with artifacts, each_serializer: SessionArtifactSerializer
          end

          def review
            decisions = params.require(:decisions).to_unsafe_h

            ActiveRecord::Base.transaction do
              decisions.each do |asset_id, decision|
                asset = current_session.output_assets.find(asset_id)
                case decision
                when "save"
                  existing = Asset.where(
                    name: asset.name,
                    scope_type: asset.scope_type,
                    scope_id: asset.scope_id,
                    folder: nil,
                    deleted_at: nil
                  ).where.not(id: asset.id).first

                  if existing
                    # Merge as new version into existing asset
                    source_version = asset.latest_version
                    if source_version&.file
                      next_ver = (existing.latest_version&.version || 0) + 1
                      existing.versions.create!(version: next_ver, file: source_version.file, uploaded_by: current_user)
                    end
                    asset.update!(status: "dismissed", reviewed_at: Time.current)
                  else
                    asset.update!(
                      status: "active",
                      reviewed_at: Time.current,
                      folder: nil
                    )
                  end
                when "dismiss"
                  asset.update!(
                    status: "dismissed",
                    reviewed_at: Time.current
                  )
                end
              end
              current_session.update!(artifacts_reviewed: true)
            end

            respond_with current_session, serializer: TerminalSessionSerializer
          end

          def download
            asset = current_session.output_assets.find(params[:id])
            version = asset.latest_version
            raise ActiveRecord::RecordNotFound, "No file version" unless version&.file.present?

            redirect_to version.file_url(
              response_content_disposition: ::ContentDisposition.attachment(asset.name)
            ), allow_other_host: true
          end

          private
        end
      end
    end
  end
end
