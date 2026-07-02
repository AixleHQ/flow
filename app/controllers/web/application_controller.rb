class Web::ApplicationController < ApplicationController
  include AuthConcern
  include PaginationConcern

  wrap_parameters false

  before_action :negotiate_format
  before_action :redirect_super_admin_to_admin_panel
  before_action :enforce_onboarding

  inertia_share do
    shared = {
      flash: flash.to_hash,
      settings: {
        env: Rails.env,
        domain: Settings.domain,
        # Only exposed to signed-in users (F8) — nil for anonymous visitors so it
        # no longer ships in the /login data-page. Low sensitivity (a GitHub App
        # slug is public in its install URL), just not anonymous-facing.
        github_app_slug: signed_in? ? Settings.github.app_slug : nil,
        app_version: Settings.app.version,
        # Public by design (a browser Sentry DSN is write-only ingest for one
        # project and must ship to the client anyway). Kept in props — not baked
        # at build — so it stays runtime-configurable via ENV. Real abuse defense
        # is Sentry-side allowed-domains + spike protection, not hiding the DSN.
        sentry_frontend_dsn: Settings.sentry.frontend_dsn
      }
    }

    if signed_in?
      shared.merge(
        current_user: InertiaRails.always {
          # current_membership comes from AuthConcern (session-validated); the
          # resource needs it to render current_company/current_role.
          CurrentUserResource.new(current_user, params: { current_membership: current_membership }).to_h
        },
        # Sidebar projects are the CURRENT company's slice only — a
        # dual-membership user sees the other company's projects after a switch.
        projects: InertiaRails.always {
          scope = current_company ? Project.for_user(current_user).for_company(current_company) : Project.none
          scope.with_state(:active).with_computed_counts.order(:name).map { |p| ProjectResource.new(p).to_h }
        }
      )
    else
      shared
    end
  end

  private

  def negotiate_format
    return if request.headers["X-Inertia"].present?

    if request.content_type&.include?("json")
      request.format = :json
    elsif !request.format.html?
      # Bots/scanners hit paths like /login.jpg, which Rails negotiates to a
      # non-HTML format and Inertia then 500s on (no .jpeg template — Sentry
      # PALAD-AI-RAILS-1N). Web pages are HTML-only, so coerce to HTML.
      request.format = :html
    end
  end

  def redirect_super_admin_to_admin_panel
    return unless signed_in? && current_user.super_admin?

    # /admin is Administrate — a classic server-rendered page, not an Inertia
    # screen. During an Inertia visit (e.g. the redirect chain right after
    # login), a plain `redirect_to` makes the client receive a non-Inertia
    # HTML response it can't process, so Inertia dumps it into its error modal
    # (the admin page shown in a box over a dark backdrop, URL stuck on /login).
    # `inertia_location` replies 409 + X-Inertia-Location so the client does a
    # full-page visit to /admin instead.
    if request.headers["X-Inertia"].present?
      inertia_location(admin_root_path)
    else
      redirect_to admin_root_path
    end
  end

  def enforce_onboarding
    return unless signed_in?
    return if current_user.onboarding_state == "completed"

    redirect_to onboarding_path unless request.path == onboarding_path
  end
end
