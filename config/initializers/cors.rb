unless Rails.env.development?
  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins do |source|
        uri = URI.parse(source)
        host = uri.host.to_s.downcase
        # Require leading dot so "maliciousaixle.com" doesn't match when domain is "aixle.com"
        host == Settings.domain || host.end_with?(".#{Settings.domain}")
      rescue URI::InvalidURIError
        false
      end
      resource "*", headers: :any, methods: [ :get, :post, :options, :put, :patch, :delete ], credentials: true
    end
  end
end
