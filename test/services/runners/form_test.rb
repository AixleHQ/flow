# frozen_string_literal: true

require "test_helper"

# Runners::Form.attributes (docs/design/agent-runtimes/runner-coder.md §7.1): the
# type and the integration are chosen once, when the runner is created.
class Runners::FormTest < ActiveSupport::TestCase
  def params(**runner)
    ActionController::Parameters.new(runner: { name: "Farm", max_concurrency: 2, runner_type: "coder", integration_id: 7, **runner })
  end

  test "creating permits the type and the integration" do
    attributes = Runners::Form.attributes(params, creating: true)

    assert_equal "coder", attributes[:runner_type]
    assert_equal 7, attributes[:integration_id]
    assert_equal "Farm", attributes[:name]
  end

  test "updating permits neither the type nor the integration" do
    attributes = Runners::Form.attributes(params, creating: false)

    assert_not attributes.key?(:runner_type)
    assert_not attributes.key?(:integration_id)
    assert_equal 2, attributes[:max_concurrency]
  end

  test "creating without an integration leaves the key out" do
    attributes = Runners::Form.attributes(ActionController::Parameters.new(runner: { name: "Farm", runner_type: "manual" }), creating: true)

    assert_not attributes.key?(:integration_id)
  end
end
