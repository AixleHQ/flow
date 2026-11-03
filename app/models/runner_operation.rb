# frozen_string_literal: true

# One op on an environment's queue (docs/design/agent-runtimes/DESIGN.md §2.3,
# §6.4): put there by Runners::Operations.enqueue!, delivered by the runner
# gateway's long-poll (GET /runner/v1/ops) and completed by the runner's result
# (POST /runner/v1/ops/:id/result).
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
  DELIVERABLE_STATES = %w[pending delivered].freeze

  encryption_key :runners_key
  encrypted_column :encrypted_payload, :encrypted_result

  enumerize :op, in: OPS
  enumerize :state, in: %i[pending delivered completed failed expired], predicates: true

  belongs_to :runner
  belongs_to :company
  belongs_to :runner_environment

  before_validation do
    self.runner_id ||= runner_environment&.runner_id
    self.company_id ||= runner_environment&.company_id
  end

  validates :sequence, numericality: { only_integer: true, greater_than: 0 }
  validates :op, :state, :deadline_at, presence: true

  scope :deliverable, -> { where(state: DELIVERABLE_STATES) }

  def deliverable?
    DELIVERABLE_STATES.include?(state)
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
end
