# frozen_string_literal: true

class SessionConcurrencyLimit < ApplicationRecord
  # Project is the only scope there is. A User scope existed for sessions launched
  # outside a project, which in practice meant agent logins — those are now exempt
  # from admission altogether (SessionAdmissionService#enqueue!), so nothing is
  # left for it to govern.
  validates :scope_type, inclusion: { in: %w[Project] }
  validates :max_sessions, numericality: { only_integer: true, greater_than: 0 }
  validates :scope_id, uniqueness: { scope: :scope_type }
  validate :scope_must_exist
  validate :fits_within_installation_limit

  # Every write path — admin, rake task, console — has to move the policy
  # revision so pools recompute their cap, and wake the queue so a raised cap
  # takes effect now instead of at the next reconciliation. Putting that here
  # rather than in one caller is what keeps the admin form honest.
  after_commit :publish_change

  def self.set!(scope:, max_sessions:)
    find_or_initialize_by(scope_type: scope.class.base_class.name, scope_id: scope.id)
      .update!(max_sessions: max_sessions)
  end

  def scope_record
    scope_type&.safe_constantize&.find_by(id: scope_id)
  end

  # What this project could be raised to right now, and who is holding the rest.
  # The screens need the same arithmetic the validation uses, so it lives in one
  # object and both ask it.
  def allocation = SessionConcurrencyAllocation.new(excluding: id)

  private

  # An explicit project limit is a reservation drawn from the installation limit,
  # so the reservations may not add up to more than there is. Enforced here rather
  # than in a controller because three places write these rows — the admin
  # dashboard, the rake task and now a project's own settings — and a rule that
  # lives in one of them is a rule the other two do not have.
  def fits_within_installation_limit
    return if max_sessions.blank?

    budget = allocation
    return if budget.fits?(max_sessions)

    errors.add(:max_sessions, budget.refusal_for(max_sessions))
  end

  def scope_must_exist
    return if scope_type.blank? || scope_id.blank?
    return if scope_record

    errors.add(:scope_id, "has no matching #{scope_type}")
  end

  def publish_change
    SessionAdmissionService.transaction { |policy| policy.update!(revision: policy.revision + 1) }
    SessionAdmissionService.drain!
  end
end
