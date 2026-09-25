# frozen_string_literal: true

# Archive in place of delete, on an `archived_at` column. An archived row keeps
# its id, so run and session history that names it still resolves, and it can
# be restored. Workflow and Tool keep their older `deleted_at` column and answer
# the same three methods themselves.
module Archivable
  extend ActiveSupport::Concern

  included do
    scope :unarchived, -> { where(archived_at: nil) }
    scope :archived, -> { where.not(archived_at: nil) }
  end

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def unarchive!
    update!(archived_at: nil)
  end
end
