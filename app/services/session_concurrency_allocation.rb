# frozen_string_literal: true

# The installation limit read as a budget that project limits are drawn from,
# and the one place that turns a refusal into a sentence somebody can act on.
#
# WHY A BUDGET AND NOT A MODE: the installation limit used to select a mode —
# set it and the whole installation shared one queue, leave it unset and every
# project got its own. The two could never apply at once, so an operator who
# wanted a ceiling lost per-project fairness, and one who wanted per-project
# fairness lost the ceiling. Now both apply: a session waits for its project's
# slot AND for the installation's, and this class governs how the first is
# allocated out of the second.
#
# ONLY EXPLICIT LIMITS ARE ALLOCATED. A project with no row of its own runs on
# the default and is bounded at runtime by the installation ceiling like everyone
# else; it holds no reservation. Counting every project at its default instead
# would make the arithmetic honest and the feature unusable — sixteen projects at
# the default of four need a ceiling of sixty-four before the first save is
# allowed.
#
# WHO MAY SEE WHOM: these rows span the installation, so the budget a company
# admin is spending from is partly held by companies they cannot see. The refusal
# message therefore carries numbers only, and #breakdown_for is the one way to
# get names — scoped to one company, with everything else summed into a single
# anonymous line.
class SessionConcurrencyAllocation
  # What other projects' allocations are called when the viewer may not know they
  # exist, let alone what they are named.
  ELSEWHERE = "Other projects"

  # @param excluding [Integer, nil] id of the limit row being changed, so its own
  #   current value is not counted against the change.
  def initialize(excluding: nil)
    @excluding = excluding
  end

  def installation_limit = SessionAdmissionPolicy.current.installation_limit

  # Every explicit project allocation except the one under change.
  def rows
    @rows ||= begin
      scope = SessionConcurrencyLimit.where(scope_type: "Project")
      scope = scope.where.not(id: @excluding) if @excluding
      scope.order(:scope_id).to_a
    end
  end

  def allocated = rows.sum(&:max_sessions)

  # What this project could be set to. Nil means "no ceiling to fit inside".
  def available
    cap = installation_limit
    return nil if cap.nil?

    [ cap - allocated, 0 ].max
  end

  def fits?(max_sessions)
    headroom = available
    headroom.nil? || max_sessions.to_i <= headroom
  end

  # Named for the company's own projects, anonymous for the rest. A company admin
  # gets to see where their own capacity went without learning the shape of
  # anybody else's installation.
  def breakdown_for(company_id)
    mine, theirs = rows.partition { |row| row.scope_record&.company_id == company_id }

    named = mine.map { |row| { name: row.scope_record&.name || "Project ##{row.scope_id}", max_sessions: row.max_sessions } }
    elsewhere = theirs.sum(&:max_sessions)
    named << { name: ELSEWHERE, max_sessions: elsewhere } if elsewhere.positive?
    named
  end

  # The refusal, said the way an operator needs to hear it: what the ceiling is,
  # how much of it is spoken for, and what is left for this project. No names —
  # this sentence is shown to whoever tried to save, and they do not necessarily
  # get to know who else holds the budget.
  def refusal_for(max_sessions)
    cap = installation_limit

    "#{max_sessions} exceeds the installation limit of #{cap} concurrent sessions. " \
      "#{allocated} of #{cap} is already allocated to other projects, " \
      "so this project can be set to at most #{available}."
  end
end
