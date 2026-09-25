# frozen_string_literal: true

require "test_helper"

# Every runtime implements the whole BaseRuntime contract. The FakeRuntime the
# suite runs on implements all of it, so a method a real runtime leaves to the
# base class only shows up in production — as NotImplementedError, a ScriptError
# that no `rescue StandardError` catches. That is how container tools came to not
# work at all on Kubernetes.
class ContainerRuntime::RuntimeContractTest < ActiveSupport::TestCase
  ABSTRACT = File.read(Rails.root.join("app/services/container_runtime/base_runtime.rb"))
                 .scan(/def (\w+[!?]?)(?:\(.*?\))?\s*\n\s*raise NotImplementedError/).flatten.freeze

  test "the base runtime declares the contract the tool strategy relies on" do
    assert_includes ABSTRACT, "wait_container"
    assert_includes ABSTRACT, "container_logs"
    assert_operator ABSTRACT.size, :>, 10
  end

  [ ContainerRuntime::DockerRuntime, ContainerRuntime::KubernetesRuntime ].each do |runtime|
    test "#{runtime.name.demodulize} implements every abstract method" do
      missing = ABSTRACT.select { |name| runtime.instance_method(name).owner == ContainerRuntime::BaseRuntime }

      assert_empty missing, "#{runtime.name} leaves #{missing.join(', ')} to BaseRuntime, which raises NotImplementedError"
    end
  end
end
