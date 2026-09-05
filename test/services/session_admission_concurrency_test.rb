# frozen_string_literal: true

require "test_helper"

class SessionAdmissionConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "competing database connections never grant more than the installation cap" do
    previous_policy = SessionAdmissionPolicy.current.attributes.except("id", "created_at", "updated_at")
    user = create(:user, :with_company)
    company = user.companies.first
    sessions = []
    admission_ids = []
    pool = nil
    SessionAdmissionPolicy.sync!(installation_limit: 2)
    6.times do
      session = create(:terminal_session, user: user)
      sessions << session
      admission = SessionAdmissionService.enqueue!(session)
      admission_ids << admission.id
      pool = admission.session_admission_pool
    end
    gate = Queue.new
    threads = 3.times.map do
      Thread.new do
        gate.pop
        ActiveRecord::Base.connection_pool.with_connection { SessionAdmissionService.drain! }
      end
    end
    3.times { gate << true }
    grants = threads.flat_map(&:value)
    assert_equal admission_ids.first(2), grants.sort
    assert_equal 2, SessionAdmission.occupied.where(id: admission_ids).count
    assert_equal 4, SessionAdmission.where(id: admission_ids, admitted_at: nil).count
  ensure
    threads&.each(&:join)
    SessionAdmission.where(id: admission_ids).delete_all if admission_ids
    TerminalSession.where(id: sessions.map(&:id)).delete_all if sessions
    pool&.destroy! if pool && !pool.session_admissions.exists?
    user&.company_memberships&.delete_all
    user&.delete
    company&.delete
    SessionAdmissionPolicy.current.update!(previous_policy) if previous_policy
  end
end
