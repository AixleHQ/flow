# frozen_string_literal: true

# One place a runner executes sessions (docs/design/agent-runtimes/DESIGN.md
# §2.2). In v1 so far the only entry path is a `manual` machine registering
# through the runner gateway (§5.2), which creates the row `registered`;
# unregistering marks it `gone`. The rest of the §5.2 state machine arrives with
# Runners::Allocator.
class RunnerEnvironment < ApplicationRecord
  extend Enumerize

  # Prefixed: origin and state share the value `registered`.
  enumerize :origin, in: %i[registered], predicates: { prefix: true }
  enumerize :state, in: %i[registered gone], predicates: true

  belongs_to :runner
  belongs_to :company
  has_many :credentials, class_name: "RunnerCredential", inverse_of: :runner_environment

  before_validation { self.company_id ||= runner&.company_id }

  validates :key, presence: true
  validates :origin, presence: true
  validates :state, presence: true
  # `aixle-runner configure --name`, the hostname by default (§2.2).
  validates :display_name, presence: true, if: :origin_registered?
  validates :display_name, :os, :arch, :runner_version, :protocol_version, length: { maximum: 255 }
  validate :facts_is_an_object
  # Reserved for an ephemeral registration (§6.3), which v1 refuses.
  validates :ephemeral, inclusion: { in: [ false ] }
  validate :company_matches_runner, if: -> { runner && company_id }

  private

  def facts_is_an_object
    errors.add(:facts, "must be an object") unless facts.is_a?(Hash)
  end

  def company_matches_runner
    errors.add(:company, "must be the runner's company") if company_id != runner.company_id
  end
end
