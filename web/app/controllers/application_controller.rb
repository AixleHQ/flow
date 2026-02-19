class ApplicationController < ActionController::Base
  include AuthConcern

  helper_method :current_user, :true_user, :impersonated?

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  before_action :gon_settings

  def gon_settings
    gon.push(
      env: Rails.env,
      domain: Settings.domain,
      protocol: Settings.protocol,
      traefik_http_base: Settings.traefik.http_base,
      github_app_slug: Settings.github.app_slug
    )
  end

  def append_info_to_payload(payload)
    super
    payload[:host] = request.host
    payload[:ip] = request.env["HTTP_X_REAL_IP"]
    payload[:ff] = request.env["HTTP_X_FORWARDED_FOR"]
    # payload[:user] = current_user&.id
  end

  def q_params
    params[:q] || {}
  end
end
