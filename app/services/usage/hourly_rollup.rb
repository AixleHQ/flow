# frozen_string_literal: true

module Usage
  # Measures closed UTC hours for every company into company_usage_hours
  # (docs/design/tenant-usage-report.md §5). Pure over the database: measuring an
  # hour again rewrites the same row, so the schedule recomputes the last few
  # hours on every run and a backfill is the same call over a longer range.
  #
  # A worker is an admitted session in a PROJECT pool, which is exactly what a
  # company's limit governs. Agent logins queue per user, outside every company's
  # budget, and are not counted.
  class HourlyRollup
    # Hours the scheduled run revisits. The meter writes the ledger row an hour
    # copies five minutes after the hour closes, and a transition can commit after
    # its hour has; the next runs pick both up.
    TRAILING_HOURS = 3

    OUTCOMES = { "finished" => :sessions_succeeded, "failed" => :sessions_failed }.freeze

    Admission = Struct.new(:company_id, :created_at, :admitted_at, :released_at)

    def self.call(...) = new(...).call

    # Only closed hours are measured: a `to` in the future stops at the hour
    # under way.
    def initialize(from: nil, to: nil, now: Time.current)
      closed = now.utc.beginning_of_hour
      @to = [ to&.utc&.beginning_of_hour || closed, closed ].min
      @from = from&.utc&.beginning_of_hour || (@to - TRAILING_HOURS.hours)
      @mode = Deployment.mode
    end

    attr_reader :from, :to

    # A day at a time, so a backfill over months holds one day of admissions in
    # memory rather than all of them.
    def call
      written = 0
      slice_start = from
      while slice_start < to
        slice_end = [ slice_start + 1.day, to ].min
        written += measure(slice_start, slice_end)
        slice_start = slice_end
      end
      { from: from.iso8601, to: to.iso8601, rows: written }
    end

    private

    def measure(slice_start, slice_end)
      admissions = admissions_between(slice_start, slice_end).group_by(&:company_id)
      outcomes = outcomes_between(slice_start, slice_end)
      offered = offered_between(slice_start, slice_end)
      opening = opening_limits(slice_start)
      changes = limit_changes_between(slice_start, slice_end)
      companies = companies_for(admissions.keys + outcomes.keys.map(&:first))
      computed_at = Time.current

      rows = hours(slice_start, slice_end).flat_map do |hour|
        companies.filter_map do |company|
          limits = limit_stats(opening.call(company.id), changes.fetch(company.id, []), hour)
          row = {
            company_id: company.id,
            period_start: hour,
            offered_seconds: offered.fetch([ company.id, hour.to_i ], 0),
            **limits,
            **occupancy(admissions.fetch(company.id, []), hour),
            **queue(admissions.fetch(company.id, []), hour),
            **OUTCOMES.values.index_with(0),
            **outcomes.fetch([ company.id, hour.to_i ], {})
          }
          next unless company.active? || used?(row)

          row.merge(billing_class: billing_class(company, limits), computed_at: computed_at)
        end
      end
      return 0 if rows.empty?

      CompanyUsageHour.upsert_all(rows, unique_by: %i[company_id period_start], record_timestamps: false)
      rows.size
    end

    def hours(slice_start, slice_end)
      (0...((slice_end - slice_start) / 3600).round).map { |index| slice_start + index.hours }
    end

    # Every active company gets a row each hour, used or not — an idle hour of a
    # paying company is still an hour it was billed for. A suspended or archived
    # one appears only for an hour in which something of it still ran.
    def companies_for(ids_with_activity)
      Company.active.or(Company.where(id: ids_with_activity.uniq))
             .select(:id, :state, :billing_state, :managed_by_aixle, :stripe_customer_id)
             .to_a
    end

    def used?(row)
      row.values_at(:offered_seconds, :occupied_seconds, :sessions_queued, :sessions_admitted,
                    *OUTCOMES.values).any?(&:positive?)
    end

    # Held during the window, or waiting in it: created before it ends, and not
    # released before it began.
    def admissions_between(slice_start, slice_end)
      SessionAdmission.joins(:terminal_session)
                      .where.not(terminal_sessions: { project_id: nil })
                      .where(session_admissions: { created_at: ...slice_end })
                      .where("session_admissions.released_at IS NULL OR session_admissions.released_at >= ?", slice_start)
                      .pluck("terminal_sessions.company_id", "session_admissions.created_at",
                             "session_admissions.admitted_at", "session_admissions.released_at")
                      .map { |values| Admission.new(*values) }
    end

    def outcomes_between(slice_start, slice_end)
      TerminalSession.where(finished_at: slice_start...slice_end, state: OUTCOMES.keys,
                            session_type: AnalyticsPeriod::USAGE_SESSION_TYPES)
                     .where.not(company_id: nil)
                     .pluck(:company_id, :state, :finished_at)
                     .each_with_object({}) do |(company_id, state, finished_at), counts|
                       per_hour = counts[[ company_id, finished_at.utc.beginning_of_hour.to_i ]] ||= Hash.new(0)
                       per_hour[OUTCOMES.fetch(state)] += 1
                     end
    end

    def offered_between(slice_start, slice_end)
      CompanyCapacityUsage.where(period_start: slice_start...slice_end)
                          .pluck(:company_id, :period_start, :quantity_seconds)
                          .to_h { |company_id, period_start, seconds| [ [ company_id, period_start.to_i ], seconds ] }
    end

    # The limit as the window opens, on the meter's terms (Billing::CapacityWindow):
    # the change log where a company has an entry, its live row where it has none.
    def opening_limits(slice_start)
      logged = CompanyCapacityChange.state_at(slice_start)
      live = SessionConcurrencyLimit.for_companies.pluck(:scope_id, :max_sessions).to_h
      ->(company_id) { logged.key?(company_id) ? logged[company_id] : live[company_id] }
    end

    def limit_changes_between(slice_start, slice_end)
      CompanyCapacityChange.during(slice_start...slice_end)
                           .order(:occurred_at, :id)
                           .pluck(:company_id, :occurred_at, :max_sessions)
                           .group_by(&:first)
                           .transform_values { |rows| rows.map { |_, at, max_sessions| [ at, max_sessions ] } }
    end

    # The smallest and largest limit the hour had, over the seconds it had one,
    # and how long it had none.
    def limit_stats(opening, changes, hour)
      hour_end = hour + 1.hour
      earlier = changes.reverse_each.find { |at, _| at < hour }
      current = earlier ? earlier.last : opening
      cursor = hour
      segments = []
      changes.each do |at, max_sessions|
        next unless at >= hour && at < hour_end

        segments << [ current, at - cursor ]
        cursor = at
        current = max_sessions
      end
      segments << [ current, hour_end - cursor ]

      bounded = segments.filter_map { |limit, seconds| limit if limit.to_i.positive? && seconds.positive? }
      unlimited = segments.sum { |limit, seconds| limit.to_i.positive? ? 0 : seconds }
      { limit_min: bounded.min, limit_max: bounded.max, unlimited_seconds: unlimited.round }
    end

    # Worker-seconds held during the hour, and the most held at one moment. A
    # release and an admission at the same instant are a hand-over, not two
    # workers, so releases are counted first.
    def occupancy(admissions, hour)
      hour_end = hour + 1.hour
      seconds = 0.0
      held = 0
      events = []
      admissions.each do |admission|
        admitted = admission.admitted_at
        released = admission.released_at
        next if admitted.nil? || admitted >= hour_end || (released && released <= hour)

        seconds += [ [ released || hour_end, hour_end ].min - [ admitted, hour ].max, 0 ].max
        if admitted <= hour
          held += 1
        else
          events << [ admitted, 1 ]
        end
        events << [ released, -1 ] if released && released < hour_end
      end

      peak = held
      events.sort_by { |at, delta| [ at, delta ] }.each do |_, delta|
        held += delta
        peak = held if held > peak
      end
      { occupied_seconds: seconds.round, peak_workers: peak }
    end

    def queue(admissions, hour)
      range = hour...(hour + 1.hour)
      waits = admissions.filter_map do |admission|
        next unless admission.admitted_at && range.cover?(admission.admitted_at)

        [ (admission.admitted_at - admission.created_at).round, 0 ].max
      end
      {
        sessions_queued: admissions.count { |admission| range.cover?(admission.created_at) },
        sessions_admitted: waits.size,
        wait_seconds_total: waits.sum,
        wait_seconds_max: waits.max || 0
      }
    end

    def billing_class(company, limits)
      return "not_metered" if @mode == Deployment::SELF_HOSTED
      return "inactive" unless company.active?
      return "paying" if @mode == Deployment::AWS_MARKETPLACE
      return "managed" if company.managed_by_aixle?
      return "blocked" if company.billing_blocked?
      return "trial" if company.billing_trialing?
      return "unlimited" if limits[:limit_max].nil?
      return "no_customer" if company.stripe_customer_id.blank?

      "paying"
    end
  end
end
