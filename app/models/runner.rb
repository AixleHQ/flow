# frozen_string_literal: true

# A machine pool that agent sessions can run on instead of the hosted runtime
# (docs/design/agent-runtimes/DESIGN.md §2.1). A null project makes it a company
# runner, visible to every project of the company.
class Runner < ApplicationRecord
  extend Enumerize
  include RunnerStateMachine

  # §2.7, §7.1. `reuse`: a scrub after every session. `reset`: a reset after
  # every session, on the same machine. `fresh`: a new machine or workspace per
  # session. `manual` takes the first two, `kubernetes` `fresh` only, and
  # `coder` all three (container mode only for `reset`, §6.8) once it can be
  # created (task 17).
  # kubernetes has a fresh pod per session and nothing else.
  DEFAULT_REUSE_POLICY = { "manual" => "reuse", "coder" => "reuse", "kubernetes" => "fresh" }.freeze

  enumerize :runner_type, in: %i[manual coder kubernetes], predicates: true
  enumerize :reuse_policy, in: %i[reuse reset fresh]

  belongs_to :company
  belongs_to :project, optional: true
  belongs_to :integration, optional: true
  # Null only once its creator has been permanently deleted.
  belongs_to :created_by, class_name: "User", optional: true

  # A runner leaves only with its project or company (its own delete is soft,
  # §2.5), and the project's runners go before its workflows and runs, so the
  # references are cleared here rather than blocking that delete.
  has_many :workflows, dependent: :nullify
  has_many :workflow_runs, dependent: :nullify
  has_many :terminal_sessions, dependent: :nullify
  # Removed with the runner by their foreign keys' ON DELETE CASCADE.
  has_many :environments, class_name: "RunnerEnvironment", inverse_of: :runner
  has_many :credentials, class_name: "RunnerCredential", inverse_of: :runner

  before_validation :default_reuse_policy
  # §9.3: a revoke (and so a soft delete) revokes every credential of the
  # runner in its own transaction, after the status UPDATE has locked the
  # runner's row. Issuers lock that row first (Runners::Credentials.lock_live_runner!),
  # so no pair issued concurrently survives the revocation.
  after_save :revoke_credentials, if: -> { saved_change_to_status?(to: "revoked") }
  # §9.3: and its sessions end once that has committed, since failing a session
  # takes locks of its own and wakes workflows.
  after_save :end_sessions, if: -> { saved_change_to_status?(to: "revoked") }

  validates :created_by, presence: true, on: :create
  validates :name, presence: true
  validates :runner_type, presence: true
  validates :reuse_policy, presence: true
  validates :max_concurrency, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :max_environments, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :max_environments, absence: true, if: :manual?
  validates :reuse_policy, inclusion: { in: %w[fresh], message: "must be fresh on a kubernetes runner" }, if: :kubernetes?
  validates :reuse_policy, inclusion: { in: %w[reuse reset], message: "must be reuse or reset on a manual runner" }, if: :manual?
  validates :integration, presence: true, if: :coder?
  validates :integration, absence: true, unless: :coder?
  validate :name_unique_in_scope, if: -> { name.present? && company_id.present? && deleted_at.nil? }
  validate :project_belongs_to_same_company, if: -> { project_id.present? }
  validate :integration_usable, if: -> { coder? && integration.present? }
  # Only when config or the type changes: a stored config that a later, tighter
  # schema refuses must not block its runner's revoke or delete, which save
  # with whiny_persistence.
  validate :config_matches_schema, if: -> { runner_type.present? && (new_record? || config_or_type_changing?) }

  scope :not_deleted, -> { where(deleted_at: nil) }
  # The company's own runners, visible to every project: not a project's.
  scope :company_level, -> { where(project_id: nil) }
  # Not disabled, revoked or deleted: the runners whose health is checked
  # (Runners::HealthCheck).
  scope :live, -> { not_deleted.where(status: RunnerStateMachine::HEALTH_STATES.map(&:to_s)) }
  # Never seen, or last seen before `time`.
  scope :not_seen_since, ->(time) { where(last_seen_at: nil).or(where(arel_table[:last_seen_at].lt(time))) }
  # What a picker offers: the company's runners and the project's own, live
  # ones only. What a reference may name, deleted ones included, is
  # TenantScope.owned(Runner, project:).
  scope :visible_for_project, ->(project) {
    where(company_id: project.company_id, project_id: nil).or(where(project_id: project.id)).not_deleted
  }

  # Who runs the machines a session's credential goes to (§3.2, §11).
  def operated_by
    project ? "#{company.name}/#{project.name}" : company.name
  end

  private

  def revoke_credentials
    now = Time.current
    credentials.unrevoked.update_all(revoked_at: now, updated_at: now)
  end

  def end_sessions
    ActiveRecord.after_all_transactions_commit { Runners::Revocation.end_sessions!(self) }
  end

  def default_reuse_policy
    self.reuse_policy ||= DEFAULT_REUSE_POLICY[runner_type.to_s]
  end

  # The unique index compares lower(name) within (company, project or none),
  # among rows that are not deleted.
  def name_unique_in_scope
    taken = Runner.not_deleted.where(company_id: company_id, project_id: project_id)
                  .where("lower(name) = ?", name.downcase)
    taken = taken.where.not(id: id) if persisted?
    errors.add(:name, :taken) if taken.exists?
  end

  def project_belongs_to_same_company
    return if project.blank? || company.blank?
    return if project.company_id == company_id

    errors.add(:project, "must belong to the same company")
  end

  # §2.6: a company runner may use only a company-wide Coder integration; a
  # project runner, a company-wide one or one of its own project's.
  def integration_usable
    return errors.add(:integration, "must be a Coder integration") unless integration.coder?
    return errors.add(:integration, "must belong to the same company") if integration.company_id != company_id
    return if integration.project_id.nil? || integration.project_id == project_id

    errors.add(:integration, project_id ? "must be company-wide or this project's" : "must be company-wide")
  end

  def config_or_type_changing?
    will_save_change_to_config? || will_save_change_to_runner_type?
  end

  # The schema and the type's rules (Runners::ConfigSchema), pure checks of
  # the config hash: a model validation does no IO and calls no service.
  def config_matches_schema
    Runners::ConfigSchema.errors(config, runner_type).each { |message| errors.add(:config, message) }
  end
end
