unless Rails.env.development?
  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins do |source|
        uri = URI.parse(source)
        uri.host == Settings.domain || uri.host.ends_with?(Settings.domain)
      end
      resource "*", headers: :any, methods: [ :get, :post, :options, :put, :patch, :delete ], credentials: true
    end
  end
end
