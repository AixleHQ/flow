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

  test "Project is the only scope there is" do
    limit = SessionConcurrencyLimit.new(scope_type: "User", scope_id: @user.id, max_sessions: 2)

    assert_not limit.valid?
    assert_includes limit.errors[:scope_type].to_sentence, "is not included"
  end

  test "with no installation ceiling a project may be given any positive limit" do
    with_ceiling(nil)

    limit = limit_for(@project, 500)
    assert limit.valid?, limit.errors.full_messages.to_sentence
  end

  test "explicit project limits are allocated out of the installation ceiling" do
    with_ceiling(10)
    other = create(:project, owner: @user, company: @company)
    SessionConcurrencyLimit.set!(scope: other, max_sessions: 7)

    assert limit_for(@project, 3).valid?, "the ceiling is a budget, and 3 is what is left of it"

    refused = limit_for(@project, 4)
    assert_not refused.valid?
    assert_match(/at most 3/, refused.errors[:max_sessions].to_sentence)
  end

  # Otherwise raising a project from 4 to 5 would be refused by its own 4.
  test "a project's own current allocation is not counted against changing it" do
    with_ceiling(10)
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 10)

    existing = SessionConcurrencyLimit.find_by(scope_type: "Project", scope_id: @project.id)
    existing.max_sessions = 9

    assert existing.valid?, existing.errors.full_messages.to_sentence
  end

  # The budget is installation-wide, but the person spending it is not: a company
  # admin must not learn the names, or the count, of projects they cannot see.
  test "the refusal names nobody" do
    with_ceiling(4)
    rival = create(:user, :with_company)
    elsewhere = create(:project, owner: rival, company: rival.companies.first, name: "Rival Gateway")
    SessionConcurrencyLimit.set!(scope: elsewhere, max_sessions: 4)

    refused = limit_for(@project, 2)

    assert_not refused.valid?
    message = refused.errors[:max_sessions].to_sentence
    assert_no_match(/Rival/, message)
    assert_no_match(/#{elsewhere.name}/, message)
    assert_match(/4 of 4/, message)
  end

  test "a breakdown names this company's own projects and sums the rest" do
    with_ceiling(20)
    mine = create(:project, owner: @user, company: @company, name: "Gateway")
    SessionConcurrencyLimit.set!(scope: mine, max_sessions: 3)
    rival = create(:user, :with_company)
    theirs = create(:project, owner: rival, company: rival.companies.first)
    SessionConcurrencyLimit.set!(scope: theirs, max_sessions: 5)

    breakdown = SessionConcurrencyAllocation.new.breakdown_for(@company.id)

    assert_equal [ "Gateway", SessionConcurrencyAllocation::ELSEWHERE ], breakdown.map { |a| a[:name] }
    assert_equal [ 3, 5 ], breakdown.map { |a| a[:max_sessions] }
  end

  test "a fully allocated ceiling leaves nothing rather than a negative number" do
    with_ceiling(5)
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 5)

    assert_equal 0, SessionConcurrencyAllocation.new.available
  end

  test "no ceiling means no budget to be left of" do
    with_ceiling(nil)
    SessionConcurrencyLimit.set!(scope: @project, max_sessions: 5)

    assert_nil SessionConcurrencyAllocation.new.available
  end
end
