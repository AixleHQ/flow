class ApplicationController < ActionController::Base
  include AuthConcern

  helper_method :current_user, :true_user, :impersonated?

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  before_action :underscore_params

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

  # Param paths whose hash values should not have keys underscored.
  # Override in subcontrollers: [[:mcpServer, :env], [:mcpServer, :headers]]
  def preserved_param_paths
    []
  end

  def underscore_params
    raw = preserved_param_paths.each_with_object({}) do |path, memo|
      value = params.dig(*path)
      memo[path] = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    end

    params.deep_transform_keys! { |key| key.to_s.underscore }

    raw.each do |path, value|
      underscored = path.map { |s| s.to_s.underscore }
      target = params
      underscored[0..-2].each { |seg| target = target[seg] }
      target[underscored.last] = value
    end
  end
end
