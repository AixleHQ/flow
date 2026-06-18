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
        sentry_frontend_dsn: Settings.sentry.frontend_dsn,
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
    redirect_to admin_root_path if signed_in? && current_user.super_admin?
  end

  def enforce_onboarding
    return unless signed_in?
    return if current_user.onboarding_state == "completed"

    redirect_to onboarding_path unless request.path == onboarding_path
  end
end
