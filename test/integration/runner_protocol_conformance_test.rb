# frozen_string_literal: true

require "test_helper"

# The runner protocol's conformance fixtures, runner-protocol/fixtures/v1/,
# run against the gateway's routes (docs/design/agent-runtimes/DESIGN.md §6,
# §14.1; the format is runner-protocol/fixtures/README.md). Every fixture file
# is one test, so a new file is picked up without a code change, and a fixture
# the gateway does not satisfy, or one this harness cannot read, fails the
# suite. The setup steps call the real services.
#
# Timing and concurrency (the long-poll's wake-up, races) are not fixtures:
# they stay in RunnerGatewayOperationsTest and the service tests.
class RunnerProtocolConformanceTest < ActionDispatch::IntegrationTest
  include ProcessModeHelper::RunnerGateway

  FIXTURES = Rails.root.join("runner-protocol/fixtures/v1")
  DEFAULT_HEADERS = { "X-Aixle-Runner-Protocol" => "1", "X-Aixle-Runner-Version" => "1.4.0" }.freeze
  RUNNER_VERSION = "1.4.0"
  PROTOCOL_VERSION = "1"
  OP_DEADLINE = 5.minutes

  INTERPOLATION = /\{\{([a-z0-9_.]+)\}\}/
  VARIABLE_NAME = /\A[a-z0-9_.]+\z/
  TIMESTAMP = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z/
  TYPES = {
    "string" => ->(value) { value.is_a?(String) },
    "integer" => ->(value) { value.is_a?(Integer) },
    "boolean" => ->(value) { value == true || value == false },
    "object" => ->(value) { value.is_a?(Hash) },
    "array" => ->(value) { value.is_a?(Array) },
    "timestamp" => ->(value) { value.is_a?(String) && value.match?(TIMESTAMP) }
  }.freeze

  # The arguments each setup step takes, and whether it requires them.
  SETUP_STEPS = {
    "registration_token" => { "as" => true },
    "registered_machine" => { "as" => true, "name" => false },
    "op_enqueued" => { "machine" => true, "as" => true, "op" => true, "payload" => true },
    "runner_revoked" => {},
    "flag_off" => {},
    "flag_on" => {},
    "time_passes" => { "seconds" => true }
  }.freeze
  EXCHANGE_KEYS = %w[request response capture].freeze
  REQUEST_KEYS = %w[method path token headers body].freeze
  RESPONSE_KEYS = %w[status headers body].freeze
  METHODS = %w[GET POST DELETE].freeze

  # A fixture this harness cannot read: an unknown key, step or matcher, or a
  # variable used before it is defined.
  class FixtureError < StandardError; end

  def self.fixture_paths
    FIXTURES.glob("**/*.json").sort
  end

  setup do
    @company = create(:company)
    @runner = create(:runner, :manual, company: @company)
    FeatureFlag.find_or_create_by!(key: "external_runners").overrides.create!(company: @company, enabled: true,
                                                                               reason: "conformance")
    @variables = {}
  end

  test "the fixtures of protocol 1 are there" do
    assert_operator self.class.fixture_paths.size, :>=, 1, "no fixture under #{FIXTURES}"
  end

  fixture_paths.each do |path|
    name = path.relative_path_from(FIXTURES).to_s

    test "fixture #{name}" do
      run_fixture(name, JSON.parse(path.read))
    end
  end

  private

  def run_fixture(name, fixture)
    check_keys(fixture, %w[description steps], name)
    raise FixtureError, "#{name}: `description` must be a string" unless fixture["description"].is_a?(String)
    steps = fixture["steps"]
    raise FixtureError, "#{name}: `steps` must be a non-empty array" unless steps.is_a?(Array) && steps.any?

    steps.each.with_index(1) do |step, number|
      where = "#{name}, step #{number}"
      raise FixtureError, "#{where}: a step must be an object" unless step.is_a?(Hash)

      step.key?("given") ? given(step, where) : exchange(step, where)
    end
  end

  # == setup steps ==

  def given(step, where)
    arguments = SETUP_STEPS.fetch(step["given"]) { raise FixtureError, "#{where}: unknown setup step #{step['given'].inspect}" }
    check_keys(step, [ "given", *arguments.keys ], where)
    missing = arguments.select { |_key, required| required }.keys - step.keys
    raise FixtureError, "#{where}: #{step['given']} needs #{missing.join(', ')}" if missing.any?

    case step["given"]
    when "registration_token"
      define(step["as"], Runners::Credentials.mint_registration!(@runner), where)
    when "registered_machine"
      register_machine(step["as"], step.fetch("name", step["as"]), where)
    when "op_enqueued"
      enqueue_op(step, where)
    when "runner_revoked"
      @runner.revoke!
    when "flag_off", "flag_on"
      flag_override.update!(enabled: step["given"] == "flag_on")
    when "time_passes"
      raise FixtureError, "#{where}: `seconds` must be a positive integer" unless step["seconds"].is_a?(Integer) && step["seconds"].positive?

      travel step["seconds"].seconds
    end
  end

  def register_machine(as, name, where)
    credential = Runners::Credentials.usable(Runners::Credentials.mint_registration!(@runner), kind: :registration)
    result = Runners::Registration.register!(credential, name: name, os: "linux", arch: "amd64", facts: {},
                                                         ephemeral: false, runner_version: RUNNER_VERSION,
                                                         protocol_version: PROTOCOL_VERSION)
    define("#{as}.access_token", result.pair.access_token, where)
    define("#{as}.refresh_token", result.pair.refresh_token, where)
    define("#{as}.environment_id", result.environment.id, where)
  end

  def enqueue_op(step, where)
    environment = @runner.environments.find(variable("#{step['machine']}.environment_id", where))
    operation = Runners::Operations.enqueue!(environment, op: step["op"], payload: step["payload"],
                                                          deadline_at: OP_DEADLINE.from_now.change(usec: 0))
    define("#{step['as']}.id", operation.id, where)
    define("#{step['as']}.sequence", operation.sequence, where)
    define("#{step['as']}.deadline_at", operation.deadline_at.iso8601, where)
  end

  def flag_override
    FeatureFlag.find_by!(key: "external_runners").overrides.find_by!(company: @company)
  end

  # == exchanges ==

  def exchange(step, where)
    check_keys(step, EXCHANGE_KEYS, where)
    request = step["request"]
    expected = step["response"]
    raise FixtureError, "#{where}: an exchange needs `request` and `response` objects" unless request.is_a?(Hash) && expected.is_a?(Hash)

    send_request(request, where)
    assert_response_matches(expected, where)
    captures = step["capture"] || {}
    raise FixtureError, "#{where}: `capture` must be an object" unless captures.is_a?(Hash)

    body = JSON.parse(response.body) if captures.any?
    captures.each { |name, pointer| define(name, at_pointer(body, pointer, where), where) }
  end

  def send_request(request, where)
    check_keys(request, REQUEST_KEYS, where)
    method = request["method"]
    raise FixtureError, "#{where}: `method` must be one of #{METHODS.join(', ')}" unless METHODS.include?(method)
    raise FixtureError, "#{where}: `path` must be a string" unless request["path"].is_a?(String)

    headers = request_headers(request, where)
    path = interpolate(request["path"], where)
    # A String `params` is sent as the raw body, as a runner sends it.
    if request.key?("body")
      body = substitute(request["body"], where).to_json
      public_send(method.downcase, path, params: body, headers: headers.merge("Content-Type" => "application/json"))
    else
      public_send(method.downcase, path, headers: headers)
    end
  end

  def request_headers(request, where)
    headers = DEFAULT_HEADERS.dup
    headers["Authorization"] = "Bearer #{interpolate(request['token'], where)}" if request.key?("token")
    (request["headers"] || {}).each do |name, value|
      headers.delete_if { |existing, _| existing.casecmp?(name) }
      headers[name] = interpolate(value, where) unless value.nil?
    end
    headers
  end

  def assert_response_matches(expected, where)
    check_keys(expected, RESPONSE_KEYS, where)
    assert_equal expected.fetch("status"), response.status, "#{where}: the status. The body was #{response.body}"
    (expected["headers"] || {}).each do |name, value|
      assert_equal value, response.headers[name], "#{where}: the #{name} header"
    end
    return unless expected.key?("body")

    if expected["body"].nil?
      assert_empty response.body, "#{where}: the body must be empty"
    else
      mismatches = []
      match(expected["body"], JSON.parse(response.body), "", mismatches, where)
      assert_empty mismatches, "#{where}: the body #{response.body} does not match:\n#{mismatches.join("\n")}"
    end
  end

  # Appends to `mismatches` every place where `actual` does not match
  # `expected` (README "Matching a body"). Objects must have exactly the
  # expected keys, so a changed response shape fails.
  def match(expected, actual, pointer, mismatches, where)
    if (matcher = matcher(expected, where))
      kind, argument = matcher
      matched = case kind
      when "$type" then TYPES.fetch(argument) { raise FixtureError, "#{where}: unknown $type #{argument.inspect}" }.call(actual)
      when "$prefix" then actual.is_a?(String) && actual.start_with?(argument)
      when "$var" then actual == variable(argument, where)
      end
      mismatches << "#{pointer.presence || '/'}: expected #{expected.to_json}, got #{actual.to_json}" unless matched
    elsif expected.is_a?(Hash)
      return mismatches << "#{pointer.presence || '/'}: expected an object, got #{actual.to_json}" unless actual.is_a?(Hash)

      (expected.keys - actual.keys).each { |key| mismatches << "#{pointer}/#{key}: missing" }
      (actual.keys - expected.keys).each { |key| mismatches << "#{pointer}/#{key}: not expected" }
      (expected.keys & actual.keys).each { |key| match(expected[key], actual[key], "#{pointer}/#{key}", mismatches, where) }
    elsif expected.is_a?(Array)
      unless actual.is_a?(Array) && actual.size == expected.size
        return mismatches << "#{pointer.presence || '/'}: expected #{expected.size} items, got #{actual.to_json}"
      end

      expected.zip(actual).each_with_index { |(item, value), index| match(item, value, "#{pointer}/#{index}", mismatches, where) }
    elsif expected != actual || expected.class != actual.class
      mismatches << "#{pointer.presence || '/'}: expected #{expected.to_json}, got #{actual.to_json}"
    end
  end

  # [kind, argument] for an object of one `$` key, nil for any other value.
  def matcher(value, where)
    return nil unless value.is_a?(Hash) && value.size == 1 && value.keys.first.start_with?("$")

    kind, argument = value.first
    raise FixtureError, "#{where}: unknown matcher #{kind}" unless %w[$type $prefix $var].include?(kind)

    [ kind, argument ]
  end

  # == variables ==

  # A request body with every {"$var": name} replaced by the variable's value.
  def substitute(value, where)
    if value.is_a?(Hash) && value.size == 1 && value.keys.first.start_with?("$")
      raise FixtureError, "#{where}: a request body takes only $var, not #{value.keys.first}" unless value.key?("$var")

      variable(value["$var"], where)
    elsif value.is_a?(Hash)
      value.transform_values { |item| substitute(item, where) }
    elsif value.is_a?(Array)
      value.map { |item| substitute(item, where) }
    else
      value
    end
  end

  def interpolate(string, where)
    raise FixtureError, "#{where}: expected a string, got #{string.inspect}" unless string.is_a?(String)

    string.gsub(INTERPOLATION) { variable(Regexp.last_match(1), where).to_s }
  end

  def define(name, value, where)
    raise FixtureError, "#{where}: #{name.inspect} is not a variable name" unless name.is_a?(String) && name.match?(VARIABLE_NAME)
    raise FixtureError, "#{where}: #{name} is already defined" if @variables.key?(name)

    @variables[name] = value
  end

  def variable(name, where)
    @variables.fetch(name) { raise FixtureError, "#{where}: #{name.inspect} is not defined" }
  end

  # RFC 6901.
  def at_pointer(document, pointer, where)
    raise FixtureError, "#{where}: #{pointer.inspect} is not a JSON Pointer" unless pointer.is_a?(String) && pointer.start_with?("/")

    pointer.split("/", -1).drop(1).reduce(document) do |node, token|
      token = token.gsub("~1", "/").gsub("~0", "~")
      if node.is_a?(Hash) && node.key?(token)
        node[token]
      elsif node.is_a?(Array) && token.match?(/\A(?:0|[1-9]\d*)\z/) && token.to_i < node.size
        node[token.to_i]
      else
        raise FixtureError, "#{where}: the response has nothing at #{pointer}"
      end
    end
  end

  def check_keys(object, allowed, where)
    unknown = object.keys - allowed
    raise FixtureError, "#{where}: unknown key #{unknown.join(', ')}" if unknown.any?
  end
end
