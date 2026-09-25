# frozen_string_literal: true

# The trail of administrative actions: sign-outs of every session, impersonation,
# permanent deletion. Rows are written where the action happens — nothing is
# audited by callback. The table keeps the shape the audited gem gave it, and the
# rows it wrote (YAML in audited_changes) still read.
class Audit < ApplicationRecord
  belongs_to :auditable, polymorphic: true, optional: true
  belongs_to :user, polymorphic: true, optional: true
  belongs_to :associated, polymorphic: true, optional: true

  serialize :audited_changes, coder: YAML

  before_create :number_within_auditable

  private

  def number_within_auditable
    self.version = Audit.where(auditable_type:, auditable_id:).maximum(:version).to_i + 1
    self.created_at ||= Time.current
  end
end
