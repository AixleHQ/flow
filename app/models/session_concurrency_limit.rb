# frozen_string_literal: true

class SessionConcurrencyLimit < ApplicationRecord
  include TenantColumns

  # A Company row is what the installation sells and bills for; a Project row is
  # a reservation drawn from the company that owns the project.
  SCOPE_TYPES = %w[Project Company].freeze

  validates :scope_type, inclusion: { in: SCOPE_TYPES }
  validates :max_sessions, numericality: { only_integer: true, greater_than: 0 }
  validates :scope_id, uniqueness: { scope: :scope_type }
  validate :scope_must_exist
  validate :fits_within_company_limit

  # Here rather than in a caller: three places write these rows, and a raised cap
  # has to reach the pools now rather than at the next reconciliation.
  after_commit :publish_change
  after_commit :record_capacity_change, if: :company_scope?
  before_destroy :refuse_to_unbound_a_metered_company, if: :company_scope?

  scope :for_projects, -> { where(scope_type: "Project") }
  scope :for_companies, -> { where(scope_type: "Company") }

  def self.set!(scope:, max_sessions:)
    find_or_initialize_by(scope_type: scope.class.base_class.name, scope_id: scope.id)
      .update!(max_sessions: max_sessions)
  end

  # Nil means unbounded AND unbilled — how an internal organisation is exempted
  # without a special case. A Marketplace deployment must forbid it, because
  # "unlimited" has no encoding in a metering record.
  def self.for_company(company_id)
    return nil if company_id.blank?

    find_by(scope_type: "Company", scope_id: company_id)&.max_sessions
  end

  # Lowering a company below its own reservations is allowed (see
  # #fits_within_company_limit), so the drain honours the company and the
  # reservations are the promise being broken. QueueHealthCheck reports these.
  def self.overcommitted_companies
    limits = for_companies.pluck(:scope_id, :max_sessions).to_h
    return [] if limits.empty?

    reservations = for_projects.pluck(:scope_id, :max_sessions).to_h
    return [] if reservations.empty?

    companies = Project.where(id: reservations.keys).pluck(:id, :company_id).to_h
    totals = Hash.new(0)
    reservations.each { |project_id, max| (cid = companies[project_id]) && totals[cid] += max }

    limits.filter_map do |company_id, limit|
      reserved = totals[company_id]
      next if reserved <= limit

      { company_id: company_id, limit: limit, reserved: reserved }
    end
  end

  def scope_record
    scope_type&.safe_constantize&.find_by(id: scope_id)
  end

  # The screens need the same arithmetic the validation uses, so both ask this.
  def allocation
    SessionConcurrencyAllocation.new(company_id: company_id, excluding: id)
  end

  private

  # In the model rather than a controller because three places write these rows.
  #
  # A company row is deliberately not validated upward: nothing above it is a
  # budget, and a downgrade of what a customer pays for must not be blocked by
  # how they happened to divide it among projects.
  def fits_within_company_limit
    return unless scope_type == "Project"
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

  def company_scope? = scope_type == "Company"

  # Every path that clears a limit lands here — the company's own settings page,
  # the admin form, the console — so the rule lives here rather than in each.
  def refuse_to_unbound_a_metered_company
    return unless Deployment.requires_bounded_companies?

    errors.add(:base, "This installation meters its capacity to AWS Marketplace, so a company cannot be left unlimited")
    throw :abort
  end

  # The metered quantity is the peak the installation offered during the hour,
  # which an hourly sample of the live rows cannot see. Recording the change
  # itself is what makes a limit raised for ten minutes billable.
  #
  # Skipped when the company is already gone: the row is an orphan of a destroyed
  # company (nothing cascades these), and the log's foreign key would refuse it.
  def record_capacity_change
    return unless Company.exists?(id: scope_id)

    CompanyCapacityChange.record!(company_id: scope_id, max_sessions: destroyed? ? nil : max_sessions)
  end
end
