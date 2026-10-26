# frozen_string_literal: true

require "test_helper"

# FeatureFlags.client_value is how the `features` shared prop (FeaturesResource)
# resolves each client flag for a browser.
class FeatureFlags::ClientValueTest < ActiveSupport::TestCase
  ENTRIES = {
    "board_ai_summary" => { "description" => "AI summary panel.", "owner" => "@AixleHQ/board", "kind" => "release",
                            "scope" => "company", "default" => false, "client" => true,
                            "remove_by" => Date.new(2027, 1, 31) },
    "new_sidebar" => { "description" => "Redesigned sidebar.", "owner" => "@AixleHQ/web", "kind" => "release",
                       "scope" => "global", "default" => true, "client" => true,
                       "remove_by" => Date.new(2027, 1, 31) }
  }.freeze

  setup do
    @company = Company.new(id: 7)
    @other = Company.new(id: 8)
  end

  def with_flags(&) = with_feature_registry(FeatureFlags::Registry.new(ENTRIES, source: "test registry"), &)

  def value(key, company:) = FeatureFlags.client_value(FeatureFlags.registry.fetch(key), company: company)

  test "values are the declared defaults when nothing is set" do
    with_flags do
      assert_equal [ false, true ], [ value(:board_ai_summary, company: @company), value(:new_sidebar, company: @company) ]
    end
  end

  test "a company override reaches that company and no other" do
    with_flags do
      with_feature(:board_ai_summary, true, company: @company) do
        assert value(:board_ai_summary, company: @company)
        refute value(:board_ai_summary, company: @other)
      end
    end
  end

  test "it resolves like the backend, ENV lock included" do
    with_flags do
      with_feature(:board_ai_summary, true, company: @company) do
        stub_feature_env(:board_ai_summary, "off") do
          assert_equal Feature.enabled?(:board_ai_summary, company: @company), value(:board_ai_summary, company: @company)
          refute value(:board_ai_summary, company: @company)
        end
      end
    end
  end

  test "a global flag is read without the company, which would raise" do
    with_flags do
      with_feature(:new_sidebar, false) do
        refute value(:new_sidebar, company: @company)
      end
    end
  end

  test "no company reads a company-scoped flag at its global value" do
    with_flags do
      with_feature(:board_ai_summary, true) do
        with_feature(:board_ai_summary, false, company: @company) do
          assert value(:board_ai_summary, company: nil)
        end
      end
    end
  end
end
