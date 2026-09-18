# frozen_string_literal: true

class SessionConcurrencyLimit < ApplicationRecord
  # Two scopes, one above the other. A Company row is what the installation sells
  # and bills for; a Project row is a reservation drawn from the company that owns
  # the project.
  #
  # A User scope existed for sessions launched outside a project, which in
  # practice meant agent logins — those are exempt from admission altogether
  # (SessionAdmissionService#enqueue!), so nothing was left for it to govern.
  SCOPE_TYPES = %w[Project Company].freeze

  validates :scope_type, inclusion: { in: SCOPE_TYPES }
  validates :max_sessions, numericality: { only_integer: true, greater_than: 0 }
  validates :scope_id, uniqueness: { scope: :scope_type }
  validate :scope_must_exist
  validate :fits_within_company_limit

  # Every write path — admin, console, a project's own settings — has to move the
  # policy revision so pools recompute their cap, and wake the queue so a raised
  # cap takes effect now instead of at the next reconciliation. Putting that here
  # rather than in one caller is what keeps every form honest.
  after_commit :publish_change

  scope :for_projects, -> { where(scope_type: "Project") }
  scope :for_companies, -> { where(scope_type: "Company") }

  def self.set!(scope:, max_sessions:)
    find_or_initialize_by(scope_type: scope.class.base_class.name, scope_id: scope.id)
      .update!(max_sessions: max_sessions)
  end

  # The company limit, or nil when the company has no row. NIL MEANS UNLIMITED
  # AND UNBILLED, which is deliberate: it is how an internal organisation is
  # exempted without a special case, exactly as a missing installation ceiling
  # has always meant "no ceiling". The hosted product allows it; a Marketplace
  # deployment must not, because "unlimited" has no encoding in a metering record.
  def self.for_company(company_id)
    return nil if company_id.blank?

    find_by(scope_type: "Company", scope_id: company_id)&.max_sessions
  end

  # Companies whose project reservations promise more than the company itself
  # has. Lowering a company below its own reservations is allowed on purpose —
  # a downgrade of what a customer pays for must not be blocked by how they
  # divided it among projects — so the drain honours the company number and the
  # reservations compete. That is a promise being broken, and QueueHealthCheck
  # is what makes sure somebody is told.
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

  # The id of the company whose budget this row is drawn from. A company row is
  # its own budget holder; a project row belongs to the company that owns it.
  def company_id
    case scope_type
    when "Company" then scope_id
    when "Project" then scope_record&.company_id
    end
  end

  # What this project could be raised to right now, and who else in the company is
  # holding the rest. The screens need the same arithmetic the validation uses, so
  # it lives in one object and both ask it.
  def allocation
    SessionConcurrencyAllocation.new(company_id: company_id, excluding: id)
  end

  private

  # A project limit is a reservation drawn from its company's limit, so the
  # reservations inside one company may not add up to more than that company has.
  # Enforced here rather than in a controller because several places write these
  # rows — the admin dashboard, the console and a project's own settings — and a
  # rule that lives in one of them is a rule the other two do not have.
  #
  # A COMPANY ROW IS NOT VALIDATED UPWARD. Nothing above it is a budget any more:
  # the installation ceiling is a physical clamp on what the cluster can run, not
  # capacity anyone bought, and a downgrade of what a customer pays for must not
  # be blocked by how they happened to divide it among projects. Lowering a
  # company below its own reservations is allowed, the drain honours the company
  # number, and QueueHealthCheck reports the over-commitment.
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
end
