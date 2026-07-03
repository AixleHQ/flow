ENV["RAILS_ENV"] = "test"

require "simplecov"

SimpleCov.start("rails") do
  primary_coverage :line
end

require_relative "../config/environment"
require "rails/test_help"
require "minitest/autorun"
require "minitest/power_assert"
require "webmock/minitest"
require "mocha/minitest"
require "inertia_rails/minitest"

# Load shared test helpers and support files
Dir[File.expand_path("../helpers/**/*.rb", __FILE__)].sort.each { |file| require file }
Dir[File.expand_path("../support/**/*.rb", __FILE__)].sort.each { |file| require file }

# Disable external web requests in tests
WebMock.disable_net_connect!(allow_localhost: true, allow: "localhost")

# Configure gitlab-ruby gem so the default client has a valid endpoint.
# Without this, any code path that invokes Gitlab.client() without explicit
# options (e.g. via def_delegators :client) raises MissingCredentials.
Gitlab.configure do |c|
  c.endpoint = ENV.fetch("GITLAB_ENDPOINT", "https://gitlab.com/api/v4")
end

class ActiveSupport::TestCase
  setup do
  end

  # Run tests in parallel with specified workers
  # parallelize(workers: :number_of_processors)

  # Include FactoryBot methods
  include FactoryBot::Syntax::Methods
  include AuthHelper
  include TemporalHelper
  include UploadSupport
  include StubSupport
  # Add more helper methods to be used by all tests here...

  # Helper for parsing JSON responses as Hashie::Mash
  def body
    Hashie::Mash.new(JSON.parse(response.body))
  end
end

# Base class for API controller tests
class ActionController::TestCase
  include ActiveJob::TestHelper

  def process(action, **args)
    super(action, format: :json, **args)
  end
end

class Admin::ActionControllerTestCase < ActionController::TestCase
  def process(action, **args)
    super(action, format: :html, **args)
  end
end

class ActionDispatch::IntegrationTest
  def assert_inertia_page(component)
    assert_response :success
    assert_inertia_component component
  end
end

class FactoryBot::Syntax::Default::DSL
  include UploadSupport
end
