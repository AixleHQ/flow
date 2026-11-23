# frozen_string_literal: true

module Sessions
  # Turns a file a session left in /workspace/outputs into a pending-review asset. Used
  # when a session ends (ContainerStrategies::AgentSessionStrategy) and when a suspended
  # session's restore window closes and its outputs come out of the checkpoint
  # (Sessions::SuspensionExpiry).
  module OutputAssets
    module_function

    # `io` is anything Shrine can upload; its bytes become the asset's first version.
    def create!(session, relative, io)
      filename = File.basename(relative)
      io.define_singleton_method(:original_filename) { filename } unless io.respond_to?(:original_filename)
      scope_type, scope_id = scope_for(session)

      asset = Asset.create!(
        name: relative, folder: "session-#{session.id}",
        scope_type: scope_type, scope_id: scope_id,
        created_by: session.user, terminal_session: session,
        status: "pending_review"
      )
      AssetVersion.create!(asset: asset, uploaded_by: session.user, source: :session, file: io)
      asset
    end

    # Output scope follows the session's project; project-less sessions fall back to the
    # user's first active membership's company. A user with no active membership has no
    # valid scope, which raises rather than creating assets with a nil scope_id.
    def scope_for(session)
      return [ "Project", session.project_id ] if session.project.present?

      company_id = session.user.company_memberships.active.default_order.pick(:company_id)
      if company_id.nil?
        raise "cannot resolve output scope: user #{session.user_id} has no active membership (session #{session.id})"
      end

      [ "Company", company_id ]
    end
  end
end
