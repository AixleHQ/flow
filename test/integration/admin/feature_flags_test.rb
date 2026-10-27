# frozen_string_literal: true

require "test_helper"

class Admin::FeatureFlagsTest < ActionDispatch::IntegrationTest
  setup do
    @company = create(:company, name: "Northwind")
    @admin = create(:user, :super_admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD)
  end

  def flag(key) = FeatureFlag.find_by(key: key.to_s)

  def set_override(key, company, enabled)
    FeatureFlags::Admin.set_override(key, company, enabled, actor: @admin, reason: "pilot customer")
  end

  test "company admins and employees get the rejection the rest of /admin gives" do
    set_override(:external_runners, @company, true)
    FeatureFlag.create!(key: "coder_reap")
    audits = Audit.count

    [ create(:user, :admin, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD),
      create(:user, :employee, :onboarding_completed, company: @company, password: AuthHelper::TEST_PASSWORD) ].each do |user|
      sign_in_as(user)

      get admin_feature_flags_path
      assert_redirected_to admin_login_path
      get admin_feature_flag_path(:external_runners)
      assert_redirected_to admin_login_path
      patch admin_feature_flag_path(:coder_reap), params: { value: "off", reason: "x" }
      assert_redirected_to admin_login_path
      post turn_off_everywhere_admin_feature_flag_path(:external_runners), params: { reason: "x" }
      assert_redirected_to admin_login_path
      post admin_feature_flag_overrides_path(:external_runners), params: { company_id: @company.id, value: "off", reason: "x" }
      assert_redirected_to admin_login_path
      delete admin_feature_flag_override_path(:external_runners, @company.id), params: { reason: "x" }
      assert_redirected_to admin_login_path
    end

    assert_nil flag(:coder_reap).enabled
    assert_equal [ true ], flag(:external_runners).overrides.pluck(:enabled)
    assert_equal audits, Audit.count
  end

  test "the index lists every declared flag, with or without rows" do
    sign_in_as(@admin)
    set_override(:external_runners, @company, true)

    stub_feature_env(:coder_reap, "off") do
      get admin_feature_flags_path
    end

    assert_response :success
    assert_select "a[href=?]", admin_feature_flag_path(:external_runners)
    assert_select "a[href=?]", admin_feature_flag_path(:coder_reap)
    assert_includes response.body, "External agent runners"
    assert_includes response.body, "1 on, 0 off"
    assert_match(/locked by <code>FEATURE_CODER_REAP<\/code>/, response.body)
  end

  test "a release flag past its remove_by is badged on the index" do
    sign_in_as(@admin)

    get admin_feature_flags_path
    assert_not_includes response.body, "past remove-by"

    travel_to FeatureFlags.registry.fetch(:external_runners).remove_by + 1.day do
      sign_in_as(@admin)
      get admin_feature_flags_path
    end
    assert_response :success
    assert_select ".flag-badge--danger", text: "past remove-by", count: 1
  end

  test "an undeclared key is not found, even with rows left from its declaration" do
    sign_in_as(@admin)
    FeatureFlag.new(key: "removed_flag", enabled: true).save!(validate: false)

    get admin_feature_flag_path(:no_such_flag)
    assert_response :not_found

    get admin_feature_flag_path(:removed_flag)
    assert_response :not_found

    get admin_feature_flags_path
    assert_response :success
    assert_not_includes response.body, "removed_flag"
  end

  test "the show page renders for a flag with no rows" do
    sign_in_as(@admin)

    get admin_feature_flag_path(:external_runners)
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

    follow_redirect!
    assert_includes response.body, "reaper misfiring"
  end

  test "a write without a reason is refused and leaves nothing behind" do
    sign_in_as(@admin)

    patch admin_feature_flag_path(:coder_reap), params: { value: "off", reason: " " }
    assert_redirected_to admin_feature_flag_path(:coder_reap)
    assert_equal "A reason is required", flash[:alert]

    post admin_feature_flag_overrides_path(:external_runners), params: { company_id: @company.id, value: "on" }
    post turn_off_everywhere_admin_feature_flag_path(:external_runners)

    assert_equal [ 0, 0 ], [ FeatureFlag.count, Audit.count ]
  end

  test "an ENV-locked flag shows its controls disabled and the writes refuse it" do
    sign_in_as(@admin)
    set_override(:external_runners, @company, true)
    audits = Audit.count

    stub_feature_env(:external_runners, "off") do
      get admin_feature_flag_path(:external_runners)
      assert_response :success
      assert_match(/Locked by <code>FEATURE_EXTERNAL_RUNNERS<\/code>/, response.body)
      assert_includes response.body, "shadowed by FEATURE_EXTERNAL_RUNNERS"
      assert_select "tr.flag-winner td", text: "ENV FEATURE_EXTERNAL_RUNNERS"
      assert_select "fieldset[disabled] input[type=submit][value=?]", "Save global value"
      assert_select "fieldset[disabled] input[type=submit][value=?]", "Turn off everywhere"
      assert_select "fieldset[disabled] input[type=submit][value=?]", "Remove"

      patch admin_feature_flag_path(:external_runners), params: { value: "on", reason: "x" }
      assert_redirected_to admin_feature_flag_path(:external_runners)
      assert_match(/locked by FEATURE_EXTERNAL_RUNNERS/, flash[:alert])
      post turn_off_everywhere_admin_feature_flag_path(:external_runners), params: { reason: "x" }
      post admin_feature_flag_overrides_path(:external_runners), params: { company_id: create(:company).id, value: "on", reason: "x" }
      delete admin_feature_flag_override_path(:external_runners, @company.id), params: { reason: "x" }
    end

    assert_nil flag(:external_runners).enabled
    assert_equal [ @company.id ], flag(:external_runners).overrides.pluck(:company_id)
    assert_equal audits, Audit.count
  end

  test "turning off everywhere removes the overrides" do
    sign_in_as(@admin)
    set_override(:external_runners, @company, true)

    post turn_off_everywhere_admin_feature_flag_path(:external_runners), params: { reason: "incident 42" }

    assert_redirected_to admin_feature_flag_path(:external_runners)
    assert_equal false, flag(:external_runners).enabled # rubocop:disable Minitest/RefuteFalse
    assert_empty flag(:external_runners).overrides
    assert Audit.exists?(action: "feature_flag.turned_off_everywhere", comment: "incident 42")
  end

  test "a company is found, checked, given an override and has it removed" do
    sign_in_as(@admin)

    get admin_feature_flag_path(:external_runners, company_query: "north")
    assert_response :success
    assert_select "select[name=company_id] option[value=?]", @company.id.to_s
    assert_select "td", text: "declared default"

    post admin_feature_flag_overrides_path(:external_runners), params: { company_id: @company.id, value: "on", reason: "pilot" }
    assert_redirected_to admin_feature_flag_path(:external_runners)
    override = flag(:external_runners).overrides.sole
    assert_equal [ @company, true, "pilot", @admin ], [ override.company, override.enabled, override.reason, override.created_by ]

    get admin_feature_flag_path(:external_runners, company_query: "north")
    assert_select "td", text: "company override"
    assert_select "a[href=?]", admin_company_path(@company)

    delete admin_feature_flag_override_path(:external_runners, @company.id), params: { reason: "pilot over" }
    assert_redirected_to admin_feature_flag_path(:external_runners)
    assert_empty flag(:external_runners).overrides
    assert_equal %w[feature_flag.override_removed feature_flag.override_set],
                 Audit.where(auditable: flag(:external_runners)).order(id: :desc).pluck(:action)
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
    set_override(:external_runners, @company, false)

    get admin_company_path(@company)

    assert_response :success
    assert_select "h2", text: "Feature overrides"
    assert_select "a[href=?]", admin_feature_flag_path(:external_runners)
    assert_includes response.body, "pilot customer"
  end

  test "CODER_REAP_ENABLED locks coder_reap, and admin names it" do
    sign_in_as(@admin)

    stub_feature_env(:coder_reap, "false", variable: "CODER_REAP_ENABLED") do
      get admin_feature_flags_path
      assert_match(/locked by <code>CODER_REAP_ENABLED<\/code>/, response.body)

      get admin_feature_flag_path(:coder_reap)
      assert_response :success
      assert_match(/Locked by <code>CODER_REAP_ENABLED<\/code>/, response.body)
      assert_select "tr.flag-winner td", text: "ENV CODER_REAP_ENABLED"
      assert_select "fieldset[disabled] input[type=submit][value=?]", "Save global value"

      patch admin_feature_flag_path(:coder_reap), params: { value: "off", reason: "x" }
      assert_redirected_to admin_feature_flag_path(:coder_reap)
      assert_match(/locked by CODER_REAP_ENABLED/, flash[:alert])
    end

    assert_nil flag(:coder_reap)
  end

  test "with CODER_REAP_ENABLED unset, coder_reap can be paused from admin" do
    sign_in_as(@admin)

    get admin_feature_flag_path(:coder_reap)
    assert_select "tr td", text: "ENV FEATURE_CODER_REAP or CODER_REAP_ENABLED"
    assert_select "fieldset[disabled]", count: 0

    patch admin_feature_flag_path(:coder_reap), params: { value: "off", reason: "incident: reaper misfiring" }
    assert_redirected_to admin_feature_flag_path(:coder_reap)
    assert_equal false, flag(:coder_reap).enabled # rubocop:disable Minitest/RefuteFalse
    assert_equal [ false, :global ], FeatureFlags::Overview.new.row(:coder_reap).resolution.then { |r| [ r.value, r.source ] }
  end
end
