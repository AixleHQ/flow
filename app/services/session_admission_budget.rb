# frozen_string_literal: true

# The drain's arithmetic, for one pass, held outside SessionAdmissionService so
# that adding the company tier did not turn #drain! into something nobody can
# read. SessionConcurrencyAllocation is the same idea at configuration time; this
# is the runtime half.
#
# TWO THINGS BOUND A GRANT:
#
#   1. The project's own pool cap — a reservation when the project has an
#      explicit row, the deployment default when it does not.
#   2. The company's limit — what the customer bought. Absent means unlimited,
#      and unbilled.
#
# There is no third, installation-wide tier. SESSION_CONCURRENCY_LIMIT was one
# number for a whole deployment and nothing reads it any more: it could not
# express an installation running several organisations, and it was never a
# number anybody was sold.
#
# WHY RESERVED PROJECTS ARE HELD APART: an explicit project limit is a promise
# that the project can always reach its number. Honouring it means nothing else
# may occupy it, so reserved projects draw on their own cap alone while everyone
# else in the company shares what the reservations leave. Counting the reserved
# capacity as shared would hand a reserved project's idle slots to whoever asked
# first, and the reservation would be a number on a screen rather than capacity
# anybody can count on.
#
# Built once per pass, inside the writer lock, from a bounded set of queries.
# Every headroom it hands out is spent through #spend!, so two pools drained in
# the same pass can never each be told the whole remainder is free.
class SessionAdmissionBudget
  POOL_KEY = /\Aproject:(\d+)\z/

  # @param pool_keys [Array<String>] keys of the pools this pass will visit, so
  #   their companies are resolved in one query rather than one query each
  def initialize(pool_keys = [])
    @project_reservations = SessionConcurrencyLimit.for_projects.pluck(:scope_id, :max_sessions).to_h
    @company_limits = SessionConcurrencyLimit.for_companies.pluck(:scope_id, :max_sessions).to_h
    @occupied_by_key = SessionAdmission.occupied.joins(:session_admission_pool)
                                       .group("session_admission_pools.key").count
    @project_company = resolve_companies(pool_keys)

    @company_headroom = {}
    @free_headroom = {}
    @company_limits.each_key { |company_id| compute_company_headroom(company_id) }
  end

  # Whether this pool holds a reservation of its own.
  def reserved?(pool_key)
    project_id = project_id_for(pool_key)
    project_id.present? && @project_reservations.key?(project_id)
  end

  # Narrows what the pool's own cap allows down to what the tiers above it still
  # have. A nil headroom at any tier means that tier does not bound this pool.
  def clamp(available, pool_key)
    company_id = company_for(pool_key)

    unless reserved?(pool_key)
      free = @free_headroom[company_id]
      available = [ available, free ].min if free
    end

    company = @company_headroom[company_id]
    available = [ available, company ].min if company
    [ available, 0 ].max
  end

  # One granted session, charged to every tier that bounds this pool.
  def spend!(pool_key)
    company_id = company_for(pool_key)

    if !reserved?(pool_key) && @free_headroom[company_id]
      @free_headroom[company_id] -= 1
    end
    @company_headroom[company_id] -= 1 if @company_headroom[company_id]
  end

  private

  def project_id_for(pool_key)
    match = POOL_KEY.match(pool_key.to_s)
    match && match[1].to_i
  end

  # Nil for a pool whose project has no company, and for the installation pools
  # left over from when the ceiling selected which pool a session belonged to.
  # Neither is bounded by a company; the pool's own cap is all they have.
  def company_for(pool_key)
    project_id = project_id_for(pool_key)
    project_id && @project_company[project_id]
  end

  def resolve_companies(pool_keys)
    ids = @project_reservations.keys.to_set
    @occupied_by_key.each_key { |key| (id = project_id_for(key)) && ids << id }
    pool_keys.each { |key| (id = project_id_for(key)) && ids << id }
    return {} if ids.empty?

    Project.where(id: ids.to_a).pluck(:id, :company_id).to_h
  end

  # A company's own occupancy and reservations, read once. Companies without a
  # limit row never get an entry, and a missing entry is what "unlimited" looks
  # like everywhere this class is asked a question.
  def compute_company_headroom(company_id)
    limit = @company_limits[company_id]
    project_ids = @project_company.select { |_, cid| cid == company_id }.keys

    occupied = 0
    unreserved_occupied = 0
    reserved_total = 0
    project_ids.each do |project_id|
      count = @occupied_by_key.fetch("project:#{project_id}", 0)
      occupied += count
      reservation = @project_reservations[project_id]
      if reservation
        reserved_total += reservation
      else
        unreserved_occupied += count
      end
    end

    @company_headroom[company_id] = [ limit - occupied, 0 ].max
    @free_headroom[company_id] = [ limit - reserved_total - unreserved_occupied, 0 ].max
  end
end
