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
        github_app_slug: Settings.github.app_slug,
        app_version: Settings.app.version
      }
    }

    if signed_in?
      shared.merge(
        current_user: InertiaRails.always { CurrentUserResource.new(current_user).to_h },
        projects: InertiaRails.always { Project.for_user(current_user).with_state(:active).with_computed_counts.order(:name).map { |p| ProjectResource.new(p).to_h } }
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
