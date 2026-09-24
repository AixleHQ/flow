# frozen_string_literal: true

# One entry on a template install's post-install checklist: a secret to add, an
# integration to connect, a trigger to activate, a server to sign in to.
#
# `ref` is stable within an install ("secret:SENTRY_TOKEN", "trigger:3"), so a
# retry updates its item rather than adding a second one.
class TemplateSetupItem < ApplicationRecord
  KINDS = %w[secret integration repository oauth trigger probe board].freeze
  STATUSES = %w[pending done failed dismissed].freeze

  belongs_to :template_install

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :ref, presence: true, uniqueness: { scope: :template_install_id }

  def open? = %w[pending failed].include?(status)
end
