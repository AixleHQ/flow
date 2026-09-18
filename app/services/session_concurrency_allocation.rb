# frozen_string_literal: true

# A company's limit read as a budget that its project limits are drawn from, and
# the one place that turns a refusal into a sentence somebody can act on.
#
# WHY THE COMPANY AND NOT THE INSTALLATION: the budget used to be the
# installation ceiling — one number for the whole deployment, read from the
# environment. That made every company's headroom depend on every other
# company's spending, which is wrong twice over. It is wrong for the operator,
# because a customer running several organisations in one installation could not
# give each of them its own capacity. And it is wrong commercially, because the
# number a customer is charged for has to be the number they were sold, not a
# share of a deployment-wide pool they cannot see.
#
# So the budget is the company's own, and nothing survives above it: the
# deployment-wide variable is gone rather than demoted.
#
# NIL MEANS UNLIMITED. A company with no row of its own is not bounded here at
# all, and neither are its projects. That is what makes an internal organisation
# free by construction rather than by a special case.
#
# ONLY EXPLICIT LIMITS ARE ALLOCATED. A project with no row runs on the default
# and is bounded at runtime by its company and the cluster like everyone else; it
# holds no reservation. Counting every project at its default instead would make
# the arithmetic honest and the feature unusable — sixteen projects at the
# default of four would need a company limit of sixty-four before the first save
# was allowed.
class SessionConcurrencyAllocation
  # @param company_id [Integer, nil] the company whose budget is being spent.
  #   Nil — an orphaned project — has no budget and refuses nothing.
  # @param excluding [Integer, nil] id of the limit row being changed, so its own
  #   current value is not counted against the change.
  def initialize(company_id:, excluding: nil)
    @company_id = company_id
    @excluding = excluding
  end

  attr_reader :company_id

  def company_limit = SessionConcurrencyLimit.for_company(company_id)

  # Every explicit project reservation inside this company except the one under
  # change.
  def rows
    @rows ||= load_rows
  end

  def allocated = rows.sum(&:max_sessions)

  # What this project could be set to. Nil means "no budget to fit inside".
  def available
    cap = company_limit
    return nil if cap.nil?

    [ cap - allocated, 0 ].max
  end

  def fits?(max_sessions)
    headroom = available
    headroom.nil? || max_sessions.to_i <= headroom
  end

  # Where this company's capacity has gone, by project name. Every row here
  # belongs to the company doing the asking, so unlike the installation-wide
  # budget this replaced, there is nothing to anonymise.
  def breakdown
    rows.map do |row|
      { name: row.scope_record&.name || "Project ##{row.scope_id}", max_sessions: row.max_sessions }
    end
  end

  # The refusal, said the way an admin needs to hear it: what the company has,
  # how much of it is spoken for, and what is left for this project.
  def refusal_for(max_sessions)
    cap = company_limit

    "#{max_sessions} exceeds the company limit of #{cap} concurrent sessions. " \
      "#{allocated} of #{cap} is already reserved by other projects, " \
      "so this project can be set to at most #{available}."
  end

  private

  def load_rows
    return [] if company_id.blank?

    scope = SessionConcurrencyLimit.for_projects
                                   .where(scope_id: Project.where(company_id: company_id).select(:id))
    scope = scope.where.not(id: @excluding) if @excluding
    scope.order(:scope_id).to_a
  end
end
