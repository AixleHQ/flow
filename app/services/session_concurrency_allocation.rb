# frozen_string_literal: true

# A company's limit read as a budget its project limits are drawn from, and the
# one place that turns a refusal into a sentence somebody can act on.
#
# The budget used to be a deployment-wide ceiling, which made every company's
# headroom depend on what other companies had spent — unusable for an
# installation running several organisations, and not the number a customer is
# sold. A company with no limit of its own is unbounded, and unbilled.
#
# Only explicit project limits are counted. Charging every project its default
# instead would be arithmetically honest and leave the feature unusable: sixteen
# projects on a default of four would need a company limit of sixty-four before
# the first save was allowed.
class SessionConcurrencyAllocation
  # @param company_id [Integer, nil] nil — an orphaned project — refuses nothing
  # @param excluding [Integer, nil] the row being changed, so its own current
  #   value is not counted against the change
  def initialize(company_id:, excluding: nil)
    @company_id = company_id
    @excluding = excluding
  end

  attr_reader :company_id

  def company_limit = SessionConcurrencyLimit.for_company(company_id)

  def rows
    @rows ||= load_rows
  end

  def allocated = rows.sum(&:max_sessions)

  # Nil means there is no budget to fit inside.
  def available
    cap = company_limit
    return nil if cap.nil?

    [ cap - allocated, 0 ].max
  end

  def fits?(max_sessions)
    headroom = available
    headroom.nil? || max_sessions.to_i <= headroom
  end

  # Every row belongs to the company doing the asking, so unlike the
  # deployment-wide budget this replaced, there is nothing to anonymise.
  def breakdown
    rows.map do |row|
      { name: row.scope_record&.name || "Project ##{row.scope_id}", max_sessions: row.max_sessions }
    end
  end

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
