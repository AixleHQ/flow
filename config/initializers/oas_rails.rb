# config/initializers/oas_rails.rb
if !Rails.env.development?
  OasRails::Engine.middleware.use(Rack::Auth::Basic) do |username, password|
    ActiveSupport::SecurityUtils.secure_compare(Settings.docs.login, username) &
      ActiveSupport::SecurityUtils.secure_compare(Settings.docs.password, password)
  end
end

OasRails.configure do |config|
  # Basic Information about the API
  config.info.title = "Aixle API"
  config.info.version = "1.0.0"
  config.info.summary = "Aixle Application JSON API"
  config.info.description = <<~HEREDOC
    # Aixle Application API Documentation

    This documentation provides details about all available API endpoints for the Aixle application.

    ## Authentication

    Most endpoints require authentication. Authentication is handled via session cookies.
    To authenticate, use the `/api/v1/sessions` endpoint with your credentials.

    ## Response Format

    All responses are returned in JSON format.

    ## Error Handling

    The API uses standard HTTP status codes to indicate success or failure:

    - 2xx: Success
    - 4xx: Client error (invalid input, unauthorized, etc.)
    - 5xx: Server error

    Error responses include details about the error in the response body.

    ## Rate Limiting

    API requests are subject to rate limiting. Excessive requests will be rejected with a 429 status code.
  HEREDOC
  config.info.contact.name = "Aixle Support"
  config.info.contact.email = "support@aixle.com"
  config.info.contact.url = "https://aixle.com/support"

  # Servers Information
  config.servers = [
    # { url: 'https://api.aixle.com', description: 'Production' },
    # { url: 'https://staging-api.aixle.com', description: 'Staging' },
    { url: "http://localhost:4000", description: "Aixle Development" },
    { url: "https://qa.aixle.com", description: "Aixle QA" },
    { url: "https://aixle.com", description: "Aixle Production" }
  ]

  # Tag Information
  # config.tags = [{ name: "Users", description: "Manage the `amazing` Users table." }]

  # config.tags = [
  #   { name: "Authentication", description: "User authentication operations" },
  #   { name: "Users", description: "User account management and information" },
  #   { name: "Accounts", description: "Account management operations" },
  #   { name: "Workspaces", description: "Workspace management operations within accounts and globally" },
  #   { name: "Specifications", description: "Specification management operations" }
  # ]

  # API path configuration
  config.api_path = "/api"

  # config.default_tags_from = :controller

  # Excluding custom controllers or controllers#action
  # config.ignored_actions = [ "web/home", "rails/health", "rails/welcome" ]

  # Authentication Settings
  config.authenticate_all_routes_by_default = true
  config.security_schema = :session_cookie
  # [:api_key_cookie, :api_key_header, :api_key_query, :basic, :bearer, :bearer_jwt, :mutual_tls]

  # Custom security schemas
  config.security_schemas = {
    session_cookie: {
      type: "apiKey",
      name: "_aixle_session",
      in: "cookie",
      description: "Session cookie for authentication"
    }
  }

  # Default error responses
  config.set_default_responses = true
  config.possible_default_responses = [ :not_found, :unauthorized, :forbidden, :internal_server_error, :unprocessable_entity ]
  config.response_body_of_default = "Hash{ success: Boolean, message: String }"
  config.response_body_of_unprocessable_entity = "Hash{ success: Boolean, errors: Hash }"
end
