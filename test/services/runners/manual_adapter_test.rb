# frozen_string_literal: true

require "test_helper"

class Runners::ManualAdapterTest < ActiveSupport::TestCase
  test "the registry hands out the manual adapter, and refuses the types that have none yet" do
    assert_instance_of Runners::ManualAdapter, Runners::Adapter.for(build(:runner, :manual))
    assert_equal %w[manual], Runners::Adapter.available_types

    %w[coder kubernetes].each do |type|
      error = assert_raises(Runners::Adapter::UnavailableType) { Runners::Adapter.for_type(type) }
      assert_match(/not available yet/, error.message)
    end
  end

  test "a manual runner can neither be provisioned nor rebuilt" do
    capabilities = Runners::ManualAdapter.new.capabilities(build(:runner, :manual))

    assert_equal({ provisionable: false, rebuildable: false }, capabilities.to_h)
  end
end
