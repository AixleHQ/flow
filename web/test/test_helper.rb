ENV["RAILS_ENV"] = "test"

require "simplecov"

SimpleCov.start("rails") do
  add_filter "app/dashboards/audited/audit_dashboard.rb"
end

require_relative "../config/environment"
require "rails/test_help"
require "minitest/autorun"
require "minitest/power_assert"
require "webmock/minitest"
require "mocha/minitest"

# Load all support files
Dir[File.expand_path("../support/**/*.rb", __FILE__)].each { |file| require file }

# Disable external web requests in tests
WebMock.disable_net_connect!(allow_localhost: true, allow: "lvh.me")

class ActiveSupport::TestCase
  setup do
    stub_github_installation_requests
    stub_temporal_workflows
    ensure_default_preset_exists
  end

  def ensure_default_preset_exists
    return if Preset.is_default.exists?

    create(:preset, :default, :with_models)
  end
  # Run tests in parallel with specified workers
  # parallelize(workers: :number_of_processors)

  # Include FactoryBot methods
  include FactoryBot::Syntax::Methods
  include AuthHelper
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
