# frozen_string_literal: true

require "test_helper"

# TypelizerModelPlugin (config/initializers/typelizer.rb) relies on typelizer's
# ModelPlugins::ActiveRecord and on AASM's state machine store, neither of
# which is public API, and nothing in CI regenerates the types to notice when
# an upgrade changes them: the unions in Runner.ts would quietly widen back to
# `string`. These tests pin what the plugin infers.
class TypelizerModelPluginTest < ActiveSupport::TestCase
  def plugin_for(model_class) = TypelizerModelPlugin.new(model_class: model_class, config: Typelizer.configuration)

  def prop(column_name, **attrs) = Typelizer::Property.new(name: column_name, column_name: column_name, **attrs)

  test "an ActiveRecord model gets the inferring plugin, anything else typelizer's own" do
    assert_instance_of TypelizerModelPlugin::ActiveRecord, plugin_for(Runner)
    assert_instance_of Typelizer::ModelPlugins::Poro, plugin_for(nil)
  end

  test "Runner's enumerize and AASM columns get their values as a union" do
    plugin = plugin_for(Runner)

    assert_equal %w[manual coder kubernetes], plugin.enum_for(prop(:runner_type))
    assert_equal %w[reuse fresh], plugin.enum_for(prop(:reuse_policy))
    assert_equal %w[pending connected degraded unreachable disabled revoked], plugin.enum_for(prop(:status))
  end

  test "a plain column has no union" do
    assert_nil plugin_for(Runner).enum_for(prop(:name))
  end

  test "a prop the serializer already typed keeps its type, whatever the column" do
    nested = Typelizer::Interface.new(serializer: RunnerResource, context: nil)

    assert_nil plugin_for(Runner).enum_for(prop(:status, type: nested))
  end

  test "a model outside INFERRED_ENUM_MODELS is left as typelizer types it" do
    assert_not_includes TypelizerModelPlugin::INFERRED_ENUM_MODELS, "Agent"
    assert_nil plugin_for(Agent).enum_for(prop(:source))
  end

  test "a Rails enum keeps typelizer's own named enum type" do
    model = Class.new(ApplicationRecord) do
      def self.name = "Runner"

      self.table_name = "runners"
      enum :reuse_policy, { reuse: "reuse", fresh: "fresh" }
    end
    reuse_policy = prop(:reuse_policy)

    assert_equal %w[reuse fresh], plugin_for(model).enum_for(reuse_policy)
    assert_equal "RunnerReusePolicy", reuse_policy.enum_type_name
  end
end
