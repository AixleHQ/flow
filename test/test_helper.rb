ENV["RAILS_ENV"] = "test"

require "simplecov"

SimpleCov.start("rails") do
  enable_coverage :branch
  primary_coverage :line
end

require_relative "../config/environment"
require "rails/test_help"
require "minitest/autorun"
require "minitest/power_assert"
require "webmock/minitest"
require "mocha/minitest"

# Load shared test helpers and support files
Dir[File.expand_path("../helpers/**/*.rb", __FILE__)].sort.each { |file| require file }
Dir[File.expand_path("../support/**/*.rb", __FILE__)].sort.each { |file| require file }

# Disable external web requests in tests
WebMock.disable_net_connect!(allow_localhost: true, allow: "lvh.me")

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

class FactoryBot::Syntax::Default::DSL
  include UploadSupport
end
