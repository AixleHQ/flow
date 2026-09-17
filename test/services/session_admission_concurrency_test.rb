# frozen_string_literal: true

require "test_helper"

class SessionAdmissionConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "competing database connections never grant more than the installation cap" do
    previous_policy = SessionAdmissionPolicy.current.attributes.except("id", "created_at", "updated_at")
    user = create(:user, :with_company)
    company = user.companies.first
    project = create(:project, owner: user, company: company)
    sessions = []
    admission_ids = []
    pool = nil
    # Two slots of SHARED pool, whatever else this database happens to hold: the
    # free pool is the ceiling less every reservation, and this test opts out of
    # transactional cleanup, so a reservation left by anything else would silently
    # shrink what these six sessions are competing for.
    with_ceiling(SessionConcurrencyLimit.sum(:max_sessions) + 2)
    6.times do
      session = create(:terminal_session, user: user, project: project)
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
    # Before the user: projects.owner_id references it, and this test opts out of
    # transactional cleanup.
    project&.delete
    user&.company_memberships&.delete_all
    UserIdentity.where(user_id: user.id).delete_all if user
    AuthSession.where(user_id: user.id).delete_all if user
    user&.delete
    # This test deletes rows directly (threads run outside the test
    # transaction), so `dependent: :destroy` never fires — every dependent must
    # be cleared by hand, the same way memberships already are.
    CompanyAuthPolicy.where(company_id: company.id).delete_all if company
    IdentityProvider.where(company_id: company.id).delete_all if company
    company&.delete
    SessionAdmissionPolicy.current.update!(previous_policy) if previous_policy
  end
end
