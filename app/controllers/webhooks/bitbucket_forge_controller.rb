# frozen_string_literal: true

# The remote end of the Aixle Flow Forge app (bitbucket-app/manifest.yml,
# docs/design/bitbucket-integration.md §5). Every request carries a Forge
# Invocation Token, verified before anything else runs, and most carry the app
# token, stored on every one of them.
#
# Forge gives events and schedules five seconds and counts a 3xx as a failure,
# so work is enqueued and nothing here redirects. UI calls answer 200 with
# `ok: false` for a refusal: the bridge rejects a non-2xx response before the
# page can read why.
class Webhooks::BitbucketForgeController < ActionController::API
  BUILD_STATUS_EVENTS = %w[avi:bitbucket:created:build-status avi:bitbucket:updated:build-status].freeze

  before_action :require_app_mode
  before_action :verify_invocation
  before_action :record_installation, except: :uninstall

  def lifecycle = acknowledge
  def heartbeat = acknowledge

  def events
    case event["eventType"]
    when *BUILD_STATUS_EVENTS
      ResolveBitbucketBuildStatusJob.perform_later(repository_uuid: Bitbucket::Forge::Ids.uuid(event.dig("repository", "uuid")),
                                                   commit: event.dig("buildStatus", "commit", "hash").to_s.presence)
    when "avi:bitbucket:updated:repository"
      RefreshBitbucketRepositoryJob.perform_later(installation_id: @installation.id, repository_uuid: event.dig("repository", "uuid"))
    when "avi:bitbucket:deleted:repository"
      Rails.logger.info("[Webhooks::BitbucketForgeController] repository #{event.dig('repository', 'uuid')} was deleted " \
                        "in workspace #{@installation.workspace_uuid}")
    end
    acknowledge
  end

  def uninstall
    installation = BitbucketInstallation.find_by(forge_installation_id: @invocation.installation_id)
    Bitbucket::Forge::Installations.uninstall!(installation) if installation && !installation.uninstalled?
    acknowledge
  end

  def status
    return refuse("not_workspace_admin", Bitbucket::Forge::Pairing::NOT_ADMIN) unless admin?

    render json: Bitbucket::Forge::Pairing.status(@installation)
  end

  def connect
    render json: { ok: true, url: Bitbucket::Forge::Pairing.start!(installation: @installation, account_id: @invocation.principal) }
  rescue Bitbucket::Forge::Pairing::Refused => e
    refuse(e.code, e.message)
  end

  def disconnect
    return refuse("not_workspace_admin", Bitbucket::Forge::Pairing::NOT_ADMIN) unless admin?

    Bitbucket::Forge::Installations.unbind!(@installation) if @installation.bound?
    render json: Bitbucket::Forge::Pairing.status(@installation)
  end

  rescue_from Bitbucket::Error do |error|
    refuse(error.code, error.message)
  end

  private

  def require_app_mode
    head :unauthorized unless Bitbucket::AppConfig.app_mode_enabled?
  end

  def verify_invocation
    @invocation = Bitbucket::Forge::InvocationToken.verify!(request.authorization)
  rescue Bitbucket::Forge::InvocationToken::Invalid => e
    Rails.logger.warn("[Webhooks::BitbucketForgeController] refused an invocation: #{e.message}")
    head :unauthorized
  end

  def record_installation
    @installation = Bitbucket::Forge::Installations.record!(
      @invocation, system_token: request.headers["x-forge-oauth-system"], installer_account_id: event["installerAccountId"]
    )
    return if @installation

    action_name.in?(%w[status connect disconnect]) ? refuse("uninstalled", Bitbucket::Forge::Installations::REMOVED) : acknowledge
  end

  def admin? = Bitbucket::Forge::WorkspaceAdmin.admin?(@installation, @invocation.principal)

  # Product events may arrive wrapped in `payload`; UI calls send their body as is.
  def event
    @event ||= begin
      body = request.request_parameters
      body["payload"].is_a?(Hash) ? body["payload"] : body
    end
  end

  def acknowledge = render(json: { ok: true })

  def refuse(code, message) = render(json: { ok: false, error: code, message: message })
end
