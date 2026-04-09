Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, Settings.google_oauth.client_id, Settings.google_oauth.client_secret, {
    scope: "email,profile",
    prompt: "select_account",
    image_aspect_ratio: "square",
    image_size: 50,
    access_type: "offline",
    name: "google"
  }
end

# Protect from CSRF attacks
OmniAuth.config.allowed_request_methods = [ :post, :get ]
OmniAuth.config.path_prefix = "/auth"

# Set failure path
OmniAuth.config.on_failure = Proc.new { |env|
  OmniAuth::FailureEndpoint.new(env).redirect_to_failure
}
