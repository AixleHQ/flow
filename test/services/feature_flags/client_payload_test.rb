# frozen_string_literal: true

require "test_helper"

# FeatureFlags.client_payload is the `features` shared prop: what a browser may
# learn about flags at all.
class FeatureFlags::ClientPayloadTest < ActiveSupport::TestCase
  ENTRIES = {
    "board_ai_summary" => { "description" => "AI summary panel.", "owner" => "@AixleHQ/board", "kind" => "release",
                            "scope" => "company", "default" => false, "client" => true,
                            "remove_by" => Date.new(2027, 1, 31) },
    "new_sidebar" => { "description" => "Redesigned sidebar.", "owner" => "@AixleHQ/web", "kind" => "release",
                       "scope" => "global", "default" => true, "client" => true,
                       "remove_by" => Date.new(2027, 1, 31) },
    "coder_reap" => { "description" => "Lets the reaper delete workspaces.", "owner" => "@AixleHQ/platform",
                      "kind" => "ops", "scope" => "global", "default" => true },
    "internal_rollout" => { "description" => "A server-only release.", "owner" => "@AixleHQ/platform",
                            "kind" => "release", "scope" => "company", "default" => true, "client" => false,
                            "remove_by" => Date.new(2027, 1, 31) }
  }.freeze

  setup do
    @company = Company.new(id: 7)
    @other = Company.new(id: 8)
  end

  def with_flags(&) = with_feature_registry(FeatureFlags::Registry.new(ENTRIES, source: "test registry"), &)

  test "only flags declared client: true are in the payload" do
    with_flags do
      assert_equal %i[board_ai_summary new_sidebar], FeatureFlags.client_payload(company: @company).keys.sort
    end
  end

  test "values are the declared defaults when nothing is set" do
    with_flags do
      assert_equal({ board_ai_summary: false, new_sidebar: true }, FeatureFlags.client_payload(company: @company))
    end
  end

  test "a company override reaches that company's payload and no other" do
    with_flags do
      with_feature(:board_ai_summary, true, company: @company) do
        assert FeatureFlags.client_payload(company: @company)[:board_ai_summary]
        refute FeatureFlags.client_payload(company: @other)[:board_ai_summary]
      end
    end
  end

  test "the payload resolves like the backend, ENV lock included" do
    with_flags do
      with_feature(:board_ai_summary, true, company: @company) do
        stub_feature_env(:board_ai_summary, "off") do
          assert_equal Feature.enabled?(:board_ai_summary, company: @company),
                       FeatureFlags.client_payload(company: @company)[:board_ai_summary]
          refute FeatureFlags.client_payload(company: @company)[:board_ai_summary]
        end
      end
    end
  end

  test "a global flag is read without the company, which would raise" do
    with_flags do
      with_feature(:new_sidebar, false) do
        refute FeatureFlags.client_payload(company: @company)[:new_sidebar]
      end
    end
  end

  test "no company reads company-scoped flags at their global value" do
    with_flags do
      with_feature(:board_ai_summary, true) do
        with_feature(:board_ai_summary, false, company: @company) do
          assert_equal({ board_ai_summary: true, new_sidebar: true }, FeatureFlags.client_payload(company: nil))
        end
      end
    end
  end

  test "the shipped registry sends nothing" do
    assert_equal({}, FeatureFlags.client_payload(company: @company))
  end
end
