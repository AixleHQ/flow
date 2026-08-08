# frozen_string_literal: true

class Web::Company::Sessions::ArtifactsController < Web::Company::ApplicationController
  def index
    session = company_sessions_scope
                .includes(:output_assets)
                .find(params[:session_id])
    authorize_session_visibility!(session)

    artifacts = session.output_assets
                       .where(status: %w[pending_review active])
                       .order(:name)

    render inertia: "Company/Sessions/Artifacts", props: {
      session: TerminalSessionResource.new(session, params: { viewer: current_user }).to_h,
      artifacts: artifacts.map { |a| SessionArtifactResource.new(a).to_h },
      already_reviewed: session.artifacts_reviewed?
    }
  end

  def review
    session = company_sessions_scope
                .find(params[:session_id])
    authorize_session_visibility!(session)

    asset_ids = session.output_assets.pluck(:id).map(&:to_s)
    decisions = params.require(:decisions).permit(*asset_ids).to_h.select { |_, v| %w[save dismiss].include?(v) }

    ActiveRecord::Base.transaction do
      decisions.each do |asset_id, decision|
        asset = session.output_assets.find(asset_id)
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
            source_version = asset.latest_version
            if source_version&.file
              next_ver = (existing.latest_version&.version || 0) + 1
              existing.versions.create!(version: next_ver, file: source_version.file, uploaded_by: current_user)
            end
            existing.update!(status: "active", reviewed_at: Time.current) if existing.status != "active"
            asset.update!(status: "dismissed", reviewed_at: Time.current)
          else
            asset.update!(status: "active", reviewed_at: Time.current, folder: nil)
          end
        when "dismiss"
          asset.update!(status: "dismissed", reviewed_at: Time.current)
        end
      end
      session.update!(artifacts_reviewed: true)
    end

    redirect_to company_session_path(session), notice: "Artifacts reviewed successfully"
  end
end
