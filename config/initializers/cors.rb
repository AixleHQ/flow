unless Rails.env.development?
  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins do |source|
        # Exact single-host match — ONLY the app's own origin may make credentialed
        # cross-origin requests. No subdomain is a legitimate API caller (the SPA is
        # same-origin, assets go to S3/CloudFront, MCP/webhooks are server-to-server),
        # so we do not allow "*.#{Settings.domain}" — that suffix match (F13/F37) let
        # any subdomain with content control steal sessions.
        URI.parse(source).host.to_s.downcase == Settings.domain
      rescue URI::InvalidURIError
        false
      end
      resource "*", headers: :any, methods: [ :get, :post, :options, :put, :patch, :delete ], credentials: true
    end
  end
end
