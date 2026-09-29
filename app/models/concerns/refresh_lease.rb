# frozen_string_literal: true

# One refresher at a time per credential.
#
# A refresh token is single-use: the provider rotates it on every refresh, so two
# refreshers sending the same one leave one of them with invalid_grant — and a
# provider with reuse detection may revoke the whole grant. Nor may the provider
# call run inside a database transaction: rolling back the write of a token the
# provider has already rotated loses the only valid one.
#
# So the lease is taken by one conditional UPDATE and given back by another, each
# committed on its own; the provider call runs in between, and the refresher
# persists what it got in a transaction of its own. A lease a crashed process
# never gave back lapses after LEASE — longer than any provider call is allowed
# to take. Re-entrant for the object that holds it, so a caller that took the
# lease can hand the same credential to code that asks for it again.
module RefreshLease
  extend ActiveSupport::Concern

  LEASE = 5.minutes
  WAIT_STEP = 0.25

  # Yields while holding the lease; returns :busy when another refresher holds it.
  def with_refresh_lease
    return yield if @refresh_lease_token

    token = SecureRandom.hex(12)
    now = Time.current
    taken = self.class.where(id: id)
                      .where("refresh_lease_until IS NULL OR refresh_lease_until < ?", now)
                      .update_all(refresh_lease_until: now + LEASE, refresh_lease_token: token) == 1
    return :busy unless taken

    @refresh_lease_token = token
    begin
      reload
      yield
    ensure
      @refresh_lease_token = nil
      self.class.where(id: id, refresh_lease_token: token).update_all(refresh_lease_until: nil, refresh_lease_token: nil)
    end
  end

  # Waits, within `timeout`, for another refresher to give the lease back, then
  # reloads so the caller sees what it stored.
  def await_refresh(timeout: 15.seconds)
    deadline = Time.current + timeout
    sleep(WAIT_STEP) while refresh_leased_elsewhere? && Time.current < deadline
    reload
  end

  def refresh_leased_elsewhere?
    self.class.where(id: id).where("refresh_lease_until >= ?", Time.current)
              .where.not(refresh_lease_token: @refresh_lease_token).exists?
  end
end
