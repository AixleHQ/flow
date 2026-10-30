# frozen_string_literal: true

require "test_helper"

class Usage::TenantWaitsTest < ActiveSupport::TestCase
  setup do
    @hour = Time.utc(2026, 10, 14, 10)
    @owner = create(:user)
  end

  def project_of(company) = create(:project, company: company, owner: create(:user, company: company))

  def admission(project, created:, admitted:)
    pool = SessionAdmissionPool.find_or_create_by!(key: "project:#{project.id}") do |p|
      p.limit = 4
      p.policy_revision = 1
    end
    session = create(:terminal_session, :agent_session, project: project, user: project.owner)
    SessionAdmission.create!(terminal_session: session, session_admission_pool: pool,
                             created_at: created, admitted_at: admitted)
  end

  test "each company's p95 is over the sessions admitted in the range" do
    acme = project_of(create(:company))
    globex = project_of(create(:company))
    20.times { |i| admission(acme, created: @hour + i.minutes, admitted: @hour + i.minutes) }
    admission(acme, created: @hour, admitted: @hour + 40.minutes)
    admission(globex, created: @hour, admitted: @hour + 2.minutes)
    admission(globex, created: @hour - 2.days, admitted: @hour - 2.days + 1.hour)

    waits = Usage::TenantWaits.call(from: @hour.to_date, to: @hour.to_date).to_h { |row| row.values_at(:company_id, :p95) }

    assert_equal 0, waits.fetch(acme.company_id), "one slow session in twenty-one is past the 95th percentile"
    assert_equal 2.minutes, waits.fetch(globex.company_id), "the session admitted two days before is not counted"
  end
end
