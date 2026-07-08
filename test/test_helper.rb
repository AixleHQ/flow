ENV["RAILS_ENV"] = "test"

require "simplecov"

# Coverage is instrumented only when SKIP_COVERAGE is not set. CI skips it on
# non-develop branch pushes (see the Makefile coverage gating / task #288): SimpleCov
# instrumentation is a large multiplier on the suite runtime. The floor is still
# enforced on develop and on local `make check_all`.
COVERAGE_ENABLED = ENV["SKIP_COVERAGE"].to_s.strip != "1"

# System tests run as a separate suite (make: system-test) after the unit run; skip
# coverage there so its partial result doesn't clobber the unit run's .last_run.json
# (the coverage floor is enforced on the unit `rails test`, see COVERAGE_MIN below).
if COVERAGE_ENABLED
  SimpleCov.start("rails") do
    primary_coverage :line
    # Parallel workers each write a result under a distinct command_name (see
    # parallelize_setup below); the parent process merges them and enforces the
    # floor on the merged total. Keep the merge window well above the suite
    # wall-clock so no worker result is dropped as stale.
    merge_timeout 3600
  end
end

# Coverage floor is opt-in (COVERAGE_MIN is set by `make be_check`/`be_check_all`):
# enforcing it on partial runs (`rails test test/models/foo_test.rb`) would always fail.
# Ratchet the floor in the Makefile as coverage grows — never lower it.
SimpleCov.minimum_coverage Float(ENV["COVERAGE_MIN"]) if COVERAGE_ENABLED && !ENV["COVERAGE_MIN"].to_s.strip.empty?

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

  # Parallel test execution (task #288). The unit suite (~2.8k cases) dominated the
  # CI backend job single-threaded, leaving a CPU core idle for the whole run. Rails
  # forks one worker per core, each with its own isolated database (aixle_test-0,
  # aixle_test-1, …), and automatically skips parallelization for runs below its
  # threshold (default 50) — so partial `rails test <file>` runs and the small
  # system suite stay serial. Make-driven suite runs remain flock-serialized (see
  # the Makefile TEST_LOCK) so concurrent invocations never fight over the shared
  # per-worker databases — the collision vector that previously made this unsafe.
  parallelize(workers: :number_of_processors)

  # SimpleCov runs inside each forked worker: give each a distinct command_name so
  # results don't clobber one another, then flush each worker's result at teardown.
  # The parent process merges all worker results and enforces the floor on the merged
  # total. No-op when coverage is skipped (non-develop CI branches, see Makefile).
  parallelize_setup do |worker|
    SimpleCov.command_name "#{SimpleCov.command_name}-#{worker}" if COVERAGE_ENABLED
  end

  parallelize_teardown do |_worker|
    SimpleCov.result if COVERAGE_ENABLED
  end

  # Include FactoryBot methods
  include FactoryBot::Syntax::Methods
  include AuthHelper
  include TemporalHelper
  include UploadSupport
  include StubSupport
  include SlackTestHelper
  include TemporalActivityHelper
  include TemporalWorkflowHelper
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
