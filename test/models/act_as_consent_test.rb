# frozen_string_literal: true

require "test_helper"

class ActAsConsentTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :admin, company: @company)
    @project = create(:project, company: @company, owner: @user)
  end

  test "both switches default to off" do
    consent = ActAsConsent.create!(user: @user, project: @project, company: @company, provider: "github")

    assert_not consent.in_own_tasks
    assert_not consent.in_others_tasks
  end

  test "a user has one row per project and provider" do
    create(:act_as_consent, user: @user, project: @project)

    duplicate = build(:act_as_consent, user: @user, project: @project)

    assert_not duplicate.valid?
  end

  test "the company has to be the project's company" do
    consent = build(:act_as_consent, user: @user, project: @project, company: create(:company))

    assert_not consent.valid?
    assert consent.errors.of_kind?(:company, :invalid) || consent.errors[:company].any?
  end

  test "allows? answers per switch and treats a missing row as off" do
    allows = ->(scope) { ActAsConsent.allows?(user: @user, project: @project, provider: "github", scope: scope) }

    assert_not allows.call(:own)
    assert_not allows.call(:others)

    create(:act_as_consent, :own, user: @user, project: @project)

    assert allows.call(:own)
    assert_not allows.call(:others)
  end

  test "allows? is scoped to the project" do
    create(:act_as_consent, :own, user: @user, project: @project)
    other = create(:project, company: @company, owner: @user)

    assert_not ActAsConsent.allows?(user: @user, project: other, provider: "github", scope: :own)
  end
end
