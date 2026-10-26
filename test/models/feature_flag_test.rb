# frozen_string_literal: true

require "test_helper"

class FeatureFlagTest < ActiveSupport::TestCase
  setup { @company = create(:company) }

  # A row whose flag was removed from config/feature_flags.yml.
  def undeclared_row = FeatureFlag.new(key: "removed_flag", enabled: false).tap { |flag| flag.save!(validate: false) }

  test "a row is created only for a declared key, once" do
    assert FeatureFlag.create(key: "coder_reap").persisted?

    undeclared = FeatureFlag.new(key: "board_ai_sumary")
    assert_not undeclared.valid?
    assert_includes undeclared.errors[:key], "is not declared in config/feature_flags.yml"

    assert_not FeatureFlag.new(key: "coder_reap").valid?
  end

  test "a row outlives its flag's declaration" do
    flag = undeclared_row

    assert_nil flag.definition
    assert flag.update(enabled: true), flag.errors.full_messages.to_sentence
  end

  test "a nil value means the declared default" do
    flag = FeatureFlag.create!(key: "coder_reap")

    assert_nil flag.enabled
    assert_equal({ coder_reap: { global: nil, overrides: {} } }, FeatureFlag.load_snapshot)
  end

  test "a company override needs a value and a reason, once per company" do
    flag = FeatureFlag.create!(key: "external_runners")
    override = flag.overrides.create!(company: @company, enabled: true, reason: "pilot customer")

    assert override.persisted?
    missing = flag.overrides.build(company: create(:company))
    assert_not missing.valid?
    assert_equal %i[enabled reason], missing.errors.attribute_names.sort
    assert_not flag.overrides.build(company: @company, enabled: false, reason: "again").valid?
  end

  test "a global flag refuses company overrides" do
    flag = FeatureFlag.create!(key: "coder_reap")
    override = flag.overrides.build(company: @company, enabled: false, reason: "pilot customer")

    assert_not override.valid?
    assert_includes override.errors[:feature_flag], "is global: it has no company overrides"
  end

  test "an override is refused for a flag that is no longer declared" do
    override = undeclared_row.overrides.build(company: @company, enabled: true, reason: "pilot customer")

    assert_not override.valid?
    assert_includes override.errors[:feature_flag], "is not declared in config/feature_flags.yml"
  end

  test "load_snapshot reads every value in two queries" do
    reap = FeatureFlag.create!(key: "coder_reap", enabled: false)
    runners = FeatureFlag.create!(key: "external_runners", enabled: true)
    other = create(:company)
    runners.overrides.create!(company: @company, enabled: false, reason: "asked to wait")
    runners.overrides.create!(company: other, enabled: true, reason: "pilot customer")

    snapshot = assert_queries_count(2) { FeatureFlag.load_snapshot }

    assert_equal({ reap.key.to_sym => { global: false, overrides: {} },
                   runners.key.to_sym => { global: true, overrides: { @company.id => false, other.id => true } } },
                 snapshot)
    assert snapshot.frozen?
  end

  test "a fresh install loads an empty snapshot" do
    assert_empty FeatureFlag.load_snapshot
  end

  test "deleting a flag deletes its overrides" do
    flag = FeatureFlag.create!(key: "external_runners")
    flag.overrides.create!(company: @company, enabled: true, reason: "pilot customer")

    flag.destroy!

    assert_not FeatureFlagOverride.exists?(company_id: @company.id)
  end
end
