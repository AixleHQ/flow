# frozen_string_literal: true

# The drain's per-pass arithmetic. Two tiers bound a grant: the pool's own cap,
# and the company's limit, where an absent company limit means unbounded.
#
# A reserved project — one with an explicit row — draws on its own cap alone,
# while the rest of the company shares what the reservations leave. Pooling the
# reserved capacity instead would lend a reserved project's idle slots to
# whoever asked first, which is the one thing a reservation promises it cannot.
#
# Built once per pass inside the writer lock. Every headroom handed out must be
# returned through #spend!, or two pools drained in the same pass are each told
# the whole remainder is free.
class SessionAdmissionBudget
  POOL_KEY = /\Aproject:(\d+)\z/

  # @param pool_keys [Array<String>] the pools this pass will visit, so their
  #   companies resolve in one query rather than one per pool
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

  def reserved?(pool_key)
    project_id = project_id_for(pool_key)
    project_id.present? && @project_reservations.key?(project_id)
  end

  # A nil headroom means that tier does not bound this pool at all.
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

  # Nil for the legacy installation pools, whose key names no project. Their own
  # cap is all that bounds them.
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

  # A company with no limit row gets no entry, and a missing entry is what
  # "unbounded" means everywhere else in this class.
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
