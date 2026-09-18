# frozen_string_literal: true

require "test_helper"

class SessionConcurrencyLimitTest < ActiveSupport::TestCase
  setup do
    @user = create(:user, :with_company)
    @company = @user.companies.first
    @project = create(:project, owner: @user, company: @company)
  end

  def limit_for(project, max_sessions)
    SessionConcurrencyLimit.new(scope_type: "Project", scope_id: project.id, max_sessions: max_sessions)
  end

  def allocation(excluding: nil)
    SessionConcurrencyAllocation.new(company_id: @company.id, excluding: excluding)
  end

  test "only Project and Company are scopes" do
    limit = SessionConcurrencyLimit.new(scope_type: "User", scope_id: @user.id, max_sessions: 2)

    assert_not limit.valid?
    assert_includes limit.errors[:scope_type].to_sentence, "is not included"
  end

  test "with no company limit a project may be given any positive limit" do
    limit = limit_for(@project, 500)

    assert limit.valid?, limit.errors.full_messages.to_sentence
  end

  test "explicit project limits are allocated out of their company's limit" do
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 10)
    other = create(:project, owner: @user, company: @company)
    SessionConcurrencyLimit.set!(scope: other, max_sessions: 7)

    assert limit_for(@project, 3).valid?, "the company limit is a budget, and 3 is what is left of it"

    refused = limit_for(@project, 4)
    assert_not refused.valid?
    assert_match(/at most 3/, refused.errors[:max_sessions].to_sentence)
  end

  # Otherwise raising a project from 4 to 5 would be refused by its own 4.
  test "a project's own current allocation is not counted against changing it" do
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 10)
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 10)

    existing = SessionConcurrencyLimit.find_by(scope_type: "Project", scope_id: @project.id)
    existing.max_sessions = 9

    assert existing.valid?, existing.errors.full_messages.to_sentence
  end

  # The whole point of moving the budget down a tier: what another customer has
  # reserved is not spent out of this one's capacity, and never was theirs to see.
  test "another company's reservations do not touch this company's budget" do
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 4)
    rival = create(:user, :with_company)
    rival_company = rival.companies.first
    SessionConcurrencyLimit.set!(scope: rival_company, max_sessions: 4)
    elsewhere = create(:project, owner: rival, company: rival_company, name: "Rival Gateway")
    SessionConcurrencyLimit.set!(scope: elsewhere, max_sessions: 4)

    allowed = limit_for(@project, 4)

    assert allowed.valid?, allowed.errors.full_messages.to_sentence
  end

  test "the refusal says what the company has and what is left" do
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 4)
    mine = create(:project, owner: @user, company: @company)
    SessionConcurrencyLimit.set!(scope: mine, max_sessions: 4)

    refused = limit_for(@project, 2)

    assert_not refused.valid?
    message = refused.errors[:max_sessions].to_sentence
    assert_match(/company limit of 4/, message)
    assert_match(/4 of 4/, message)
  end

  test "a breakdown names the company's own projects" do
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 20)
    mine = create(:project, owner: @user, company: @company, name: "Gateway")
    SessionConcurrencyLimit.set!(scope: mine, max_sessions: 3)
    rival = create(:user, :with_company)
    theirs = create(:project, owner: rival, company: rival.companies.first)
    SessionConcurrencyLimit.set!(scope: theirs, max_sessions: 5)

    breakdown = allocation.breakdown

    assert_equal [ "Gateway" ], breakdown.map { |a| a[:name] }
    assert_equal [ 3 ], breakdown.map { |a| a[:max_sessions] }
  end

  test "a fully allocated company leaves nothing rather than a negative number" do
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 5)
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 5)

    assert_equal 0, allocation.available
  end

  test "no company limit means no budget to be left of" do
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 5)

    assert_nil allocation.available
  end

  # A downgrade of what a customer pays for must not be blocked by how they
  # divided it among projects.
  test "a company may be lowered below its own projects' reservations" do
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 10)
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 8)

    row = SessionConcurrencyLimit.find_by(scope_type: "Company", scope_id: @company.id)
    row.max_sessions = 3

    assert row.valid?, row.errors.full_messages.to_sentence
  end

  test "over-commitment is reported rather than refused" do
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 10)
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 3)
    other = create(:project, owner: @user, company: @company)
    SessionConcurrencyLimit.set!(scope: other, max_sessions: 2)
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 3)

    overcommitted = SessionConcurrencyLimit.overcommitted_companies

    assert_equal [ { company_id: @company.id, limit: 3, reserved: 5 } ], overcommitted
  end

  test "a company within its reservations is not reported" do
    SessionConcurrencyLimit.set!(scope: @company, max_sessions: 10)
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 4)

    assert_empty SessionConcurrencyLimit.overcommitted_companies
  end
end
