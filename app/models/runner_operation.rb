# frozen_string_literal: true

# One op on an environment's queue (docs/design/agent-runtimes/DESIGN.md §2.3,
# §6.4): put there by Runners::Operations.enqueue!, delivered by the runner
# gateway's long-poll (GET /runner/v1/ops) and completed by the runner's result
# (POST /runner/v1/ops/:id/result).
#
# A session op is for one session, which the envelope names as `session_id`, and
# the runner checks it against the container's label (PROTOCOL.md §5.4, §6.3).
# An environment op (`image.ensure`, `env.scrub`, `env.reset`) names none.
#
# `sequence` is monotonic per environment, and the runner acknowledges by it.
# The payload carries what a hosted pod receives through `write_file` today,
# credentials included, so it is encrypted with `runners_key` and nulled once
# the op completes, fails or expires. The result carries command output and
# file contents, which can hold the same credentials, so it is encrypted with
# `runners_key` too.
class RunnerOperation < ApplicationRecord
  include Encryptable
  extend Enumerize

  # The environment ops of §6.4. The controller ops (`provision`, `teardown`,
  # `observe`) come with the controller (§15 task 19).
  OPS = %w[
    exec write_file read_file batch status logs session.start session.stop
    image.ensure container.start container.stop env.scrub env.reset
  ].freeze
  ENVIRONMENT_OPS = %w[image.ensure env.scrub env.reset].freeze
  SESSION_OPS = (OPS - ENVIRONMENT_OPS).freeze
  DELIVERABLE_STATES = %w[pending delivered].freeze
  FINISHED_STATES = %w[completed failed expired].freeze

  encryption_key :runners_key
  encrypted_column :encrypted_payload, :encrypted_result

  enumerize :op, in: OPS
  enumerize :state, in: %i[pending delivered completed failed expired], predicates: true

  belongs_to :runner
  belongs_to :company
  belongs_to :runner_environment
  belongs_to :terminal_session, optional: true

  before_validation do
    self.runner_id ||= runner_environment&.runner_id
    self.company_id ||= runner_environment&.company_id
  end

  validates :sequence, numericality: { only_integer: true, greater_than: 0 }
  validates :op, :state, :deadline_at, presence: true
  validates :terminal_session, presence: { message: "is required for a session op" }, if: :session_op?
  validates :terminal_session, absence: { message: "must be empty for an environment op" }, unless: :session_op?
  validate :session_is_on_the_environment, if: -> { terminal_session && will_save_change_to_terminal_session_id? }

  scope :deliverable, -> { where(state: DELIVERABLE_STATES) }

  def deliverable?
    DELIVERABLE_STATES.include?(state)
  end

  def session_op?
    SESSION_OPS.include?(op)
  end

  # The decrypted payload, a Hash, or nil once the op is over.
  def payload
    plaintext = decrypt_secret(encrypted_payload, column: "encrypted_payload")
    plaintext && JSON.parse(plaintext)
  end

  def payload=(value)
    self.encrypted_payload = value.nil? ? nil : encrypt_secret(value.to_json, column: "encrypted_payload")
  end

  # The decrypted result the runner reported, a Hash, or nil before it has.
  def result
    plaintext = decrypt_secret(encrypted_result, column: "encrypted_result")
    plaintext && JSON.parse(plaintext)
  end

  def result=(value)
    self.encrypted_result = value.nil? ? nil : encrypt_secret(value.to_json, column: "encrypted_result")
  end

  private

  # An op goes to the machine its session runs on, and to no other.
  def session_is_on_the_environment
    return if terminal_session.runner_environment_id == runner_environment_id

    errors.add(:terminal_session, "does not run on this environment")
  end
end
