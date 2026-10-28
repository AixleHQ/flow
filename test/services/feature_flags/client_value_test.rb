# frozen_string_literal: true

require "test_helper"

# FeatureFlags.client_value is how the `features` shared prop (FeaturesResource)
# resolves each client flag for a browser.
class FeatureFlags::ClientValueTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @other = create(:company)
  end

  def value(key, company:) = FeatureFlags.client_value(FeatureFlags.registry.fetch(key), company: company)

  test "values are the declared defaults when nothing is set" do
    assert_equal [ false, true ], [ value(:external_runners, company: @company), value(:coder_reap, company: @company) ]
  end

  test "a company override reaches that company and no other" do
    with_feature(:external_runners, true, company: @company) do
      assert value(:external_runners, company: @company)
      refute value(:external_runners, company: @other)
    end
  end

  test "it resolves like the backend, ENV lock included" do
    with_feature(:external_runners, true, company: @company) do
      stub_feature_env(:external_runners, "off") do
        assert_equal Feature.enabled?(:external_runners, company: @company), value(:external_runners, company: @company)
        refute value(:external_runners, company: @company)
      end
    end
  end

  test "a global flag is read without the company, which would raise" do
    with_feature(:coder_reap, false) do
      refute value(:coder_reap, company: @company)
    end
  end

  test "no company reads a company-scoped flag at its global value" do
    with_feature(:external_runners, true) do
      with_feature(:external_runners, false, company: @company) do
        assert value(:external_runners, company: nil)
      end
    end
  end
end
