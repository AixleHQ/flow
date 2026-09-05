# frozen_string_literal: true

class SessionConcurrencyLimit < ApplicationRecord
  validates :scope_type, inclusion: { in: %w[Project User] }
  validates :max_sessions, numericality: { only_integer: true, greater_than: 0 }
  validates :scope_id, uniqueness: { scope: :scope_type }
  validate :scope_must_exist

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

  private

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
