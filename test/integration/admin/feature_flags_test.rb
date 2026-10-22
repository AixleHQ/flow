# frozen_string_literal: true

require "test_helper"

class Admin::FeatureFlagsTest < ActionDispatch::IntegrationTest
  uses_feature_registry FeatureFlagsHelper::EXAMPLE_REGISTRY

  setup do
    @token = FakeFeatureFlagVersionToken.new
    @token_before_test = FeatureFlags.version_token
    FeatureFlags.version_token = @token
    @company = create(:company, name: "Northwind")
    @admin = create(:user, :super_admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
  end

  teardown { FeatureFlags.version_token = @token_before_test }

  def flag(key) = FeatureFlag.find_by(key: key.to_s)

  def set_override(key, company, enabled)
    FeatureFlags::Admin.set_override(key, company, enabled, actor: @admin, reason: "pilot customer")
  end

  test "company admins and employees get the rejection the rest of /admin gives" do
    set_override(:board_ai_summary, @company, true)
    FeatureFlag.create!(key: "coder_reap")
    audits = Audit.count

    [ create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD),
      create(:user, :employee, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD) ].each do |user|
      sign_in_as(user)

      get admin_feature_flags_path
      assert_redirected_to admin_login_path
      get admin_feature_flag_path(:board_ai_summary)
      assert_redirected_to admin_login_path
      patch admin_feature_flag_path(:coder_reap), params: { value: "off", reason: "x" }
      assert_redirected_to admin_login_path
      post turn_off_everywhere_admin_feature_flag_path(:board_ai_summary), params: { reason: "x" }
      assert_redirected_to admin_login_path
      post admin_feature_flag_overrides_path(:board_ai_summary), params: { company_id: @company.id, value: "off", reason: "x" }
      assert_redirected_to admin_login_path
      delete admin_feature_flag_override_path(:board_ai_summary, @company.id), params: { reason: "x" }
      assert_redirected_to admin_login_path
      delete admin_feature_flag_path(:coder_reap), params: { reason: "x" }
      assert_redirected_to admin_login_path
    end

    assert_nil flag(:coder_reap).enabled
    assert_equal [ true ], flag(:board_ai_summary).overrides.pluck(:enabled)
    assert_equal audits, Audit.count
  end

  test "the index renders with no flags declared" do
    sign_in_as(@admin)

    with_feature_registry(FeatureFlags::Registry.new({})) do
      get admin_feature_flags_path
    end

    assert_response :success
    assert_includes response.body, "No feature flags are declared."
  end

  test "the index lists every declared flag, with or without rows" do
    sign_in_as(@admin)
    set_override(:board_ai_summary, @company, true)

    stub_feature_env(:coder_reap, "off") do
      get admin_feature_flags_path
    end

    assert_response :success
    assert_select "a[href=?]", admin_feature_flag_path(:board_ai_summary)
    assert_select "a[href=?]", admin_feature_flag_path(:coder_reap)
    assert_includes response.body, "AI summary panel on the board task drawer."
    assert_includes response.body, "1 on, 0 off"
    assert_match(/locked by <code>FEATURE_CODER_REAP<\/code>/, response.body)
  end

  test "orphaned rows are listed and can be deleted with a reason" do
    sign_in_as(@admin)
    set_override(:board_ai_summary, @company, true)

    with_feature_registry(FeatureFlags::Registry.new({})) do
      get admin_feature_flags_path
      assert_includes response.body, "Orphaned rows"
      assert_includes response.body, "board_ai_summary"

      get admin_feature_flag_path(:board_ai_summary)
      assert_redirected_to admin_feature_flags_path

      delete admin_feature_flag_path(:board_ai_summary), params: { reason: "" }
      assert_redirected_to admin_feature_flags_path
      assert flag(:board_ai_summary)

      delete admin_feature_flag_path(:board_ai_summary), params: { reason: "flag removed" }
      assert_redirected_to admin_feature_flags_path
      assert_nil flag(:board_ai_summary)
      assert Audit.exists?(action: "feature_flag.pruned", comment: "flag removed")
    end
  end

  test "an unknown key with no rows is not found" do
    sign_in_as(@admin)

    get admin_feature_flag_path(:no_such_flag)

    assert_response :not_found
  end

  test "the show page renders for a flag with no rows" do
    sign_in_as(@admin)

    get admin_feature_flag_path(:board_ai_summary)
    assert_response :success
    assert_includes response.body, "No company is an exception."
    assert_includes response.body, "Nobody has changed this flag."
    assert_select "tr.flag-winner td", text: "Declared default"

    get admin_feature_flag_path(:coder_reap)
    assert_response :success
    assert_select "h2", text: "Company overrides", count: 0
  end

  test "the global value is set, cleared and audited with the reason" do
    sign_in_as(@admin)

    patch admin_feature_flag_path(:coder_reap), params: { value: "off", reason: "reaper misfiring" }
    assert_redirected_to admin_feature_flag_path(:coder_reap)
    assert_equal false, flag(:coder_reap).enabled # rubocop:disable Minitest/RefuteFalse

    patch admin_feature_flag_path(:coder_reap), params: { value: "default", reason: "fixed" }
    assert_nil flag(:coder_reap).enabled

    audit = Audit.where(auditable: flag(:coder_reap)).order(:id).last
    assert_equal [ "feature_flag.global_cleared", @admin, "fixed" ], [ audit.action, audit.user, audit.comment ]
    assert_equal 2, @token.bumps

    follow_redirect!
    assert_includes response.body, "reaper misfiring"
  end

  test "a write without a reason is refused and leaves nothing behind" do
    sign_in_as(@admin)

    patch admin_feature_flag_path(:coder_reap), params: { value: "off", reason: " " }
    assert_redirected_to admin_feature_flag_path(:coder_reap)
    assert_equal "A reason is required", flash[:alert]

    post admin_feature_flag_overrides_path(:board_ai_summary), params: { company_id: @company.id, value: "on" }
    post turn_off_everywhere_admin_feature_flag_path(:board_ai_summary)

    assert_equal [ 0, 0, 0 ], [ FeatureFlag.count, Audit.count, @token.bumps ]
  end

  test "an ENV-locked flag shows its controls disabled and the writes refuse it" do
    sign_in_as(@admin)
    set_override(:board_ai_summary, @company, true)
    audits = Audit.count

    stub_feature_env(:board_ai_summary, "off") do
      get admin_feature_flag_path(:board_ai_summary)
      assert_response :success
      assert_match(/Locked by <code>FEATURE_BOARD_AI_SUMMARY<\/code>/, response.body)
      assert_includes response.body, "shadowed by FEATURE_BOARD_AI_SUMMARY"
      assert_select "tr.flag-winner td", text: "ENV FEATURE_BOARD_AI_SUMMARY"
      assert_select "fieldset[disabled] input[type=submit][value=?]", "Save global value"
      assert_select "fieldset[disabled] input[type=submit][value=?]", "Turn off everywhere"
      assert_select "fieldset[disabled] input[type=submit][value=?]", "Remove"

      patch admin_feature_flag_path(:board_ai_summary), params: { value: "on", reason: "x" }
      assert_redirected_to admin_feature_flag_path(:board_ai_summary)
      assert_match(/locked by FEATURE_BOARD_AI_SUMMARY/, flash[:alert])
      post turn_off_everywhere_admin_feature_flag_path(:board_ai_summary), params: { reason: "x" }
      post admin_feature_flag_overrides_path(:board_ai_summary), params: { company_id: create(:company).id, value: "on", reason: "x" }
      delete admin_feature_flag_override_path(:board_ai_summary, @company.id), params: { reason: "x" }
    end

    assert_nil flag(:board_ai_summary).enabled
    assert_equal [ @company.id ], flag(:board_ai_summary).overrides.pluck(:company_id)
    assert_equal audits, Audit.count
  end

  test "turning off everywhere removes the overrides" do
    sign_in_as(@admin)
    set_override(:board_ai_summary, @company, true)

    post turn_off_everywhere_admin_feature_flag_path(:board_ai_summary), params: { reason: "incident 42" }

    assert_redirected_to admin_feature_flag_path(:board_ai_summary)
    assert_equal false, flag(:board_ai_summary).enabled # rubocop:disable Minitest/RefuteFalse
    assert_empty flag(:board_ai_summary).overrides
    assert Audit.exists?(action: "feature_flag.turned_off_everywhere", comment: "incident 42")
  end

  test "a company is found, checked, given an override and has it removed" do
    sign_in_as(@admin)

    get admin_feature_flag_path(:board_ai_summary, company_query: "north")
    assert_response :success
    assert_select "select[name=company_id] option[value=?]", @company.id.to_s
    assert_select "td", text: "declared default"

    post admin_feature_flag_overrides_path(:board_ai_summary), params: { company_id: @company.id, value: "on", reason: "pilot" }
    assert_redirected_to admin_feature_flag_path(:board_ai_summary)
    override = flag(:board_ai_summary).overrides.sole
    assert_equal [ @company, true, "pilot", @admin ], [ override.company, override.enabled, override.reason, override.created_by ]

    get admin_feature_flag_path(:board_ai_summary, company_query: "north")
    assert_select "td", text: "company override"
    assert_select "a[href=?]", admin_company_path(@company)

    delete admin_feature_flag_override_path(:board_ai_summary, @company.id), params: { reason: "pilot over" }
    assert_redirected_to admin_feature_flag_path(:board_ai_summary)
    assert_empty flag(:board_ai_summary).overrides
    assert_equal %w[feature_flag.override_removed feature_flag.override_set],
                 Audit.where(auditable: flag(:board_ai_summary)).order(id: :desc).pluck(:action)
  end

  test "a global flag takes no override" do
    sign_in_as(@admin)

    post admin_feature_flag_overrides_path(:coder_reap), params: { company_id: @company.id, value: "off", reason: "x" }

    assert_redirected_to admin_feature_flag_path(:coder_reap)
    assert_match(/global/, flash[:alert])
    assert_equal 0, FeatureFlagOverride.count
  end

  test "the company page lists the company's feature overrides" do
    sign_in_as(@admin)
    set_override(:board_ai_summary, @company, false)

    get admin_company_path(@company)

    assert_response :success
    assert_select "h2", text: "Feature overrides"
    assert_select "a[href=?]", admin_feature_flag_path(:board_ai_summary)
    assert_includes response.body, "pilot customer"
  end
end
