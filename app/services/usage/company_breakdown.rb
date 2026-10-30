# frozen_string_literal: true

module Usage
  # One company's queue over a range of UTC days, for the dashboard's detail view
  # (docs/design/tenant-usage-report.md §7). The table sums stored hours, which
  # cannot give a percentile or a queue position, so this reads the admissions
  # themselves and leaves every aggregate to Postgres: a long range of a busy
  # company is hundreds of thousands of rows, and none of them reach Ruby.
  class CompanyBreakdown
    # A session that waited less than this was granted on the first drain after
    # it joined; anything longer stood behind someone.
    WAITED = 30

    PERCENTILES = { p50: 0.5, p90: 0.9, p95: 0.95, p99: 0.99 }.freeze

    def initialize(company, from:, to:)
      @company = company
      @from = from.to_time(:utc)
      @to = (to + 1).to_time(:utc)
    end

    def to_h
      sessions = session_groups
      {
        company_id: @company.id,
        worker_limit: Billing::EffectiveCapacity.for_companies[@company.id],
        project_default: SessionAdmissionPolicy.scope_default("Project"),
        capacity: capacity,
        waits: sessions.fetch(:all, empty_waits),
        runs: runs,
        projects: projects(sessions.fetch(:projects, {})),
        days: sessions.fetch(:days, {}).sort.map { |day, waits| { day: day, **waits.slice(:sessions, :waited, :p95) } }
      }
    end

    private

    def binds = { company_id: @company.id, from: @from, to: @to, waited: WAITED }

    def select_all(sql) = ActiveRecord::Base.connection.select_all(ActiveRecord::Base.sanitize_sql_array([ sql, binds ]))

    # Every session admitted in the range, with how long it waited and how many
    # of the company's sessions — and of its project's — were already waiting
    # when it joined. Those counts come from a running sum over join and leave
    # events, so the admissions that could have been waiting then are loaded
    # too: everything that left the queue after the earliest of them joined.
    # Leaving sorts before joining at the same instant, and simultaneous joins
    # go by id, the order the drain grants them in.
    def measured_sql
      <<~SQL
        WITH admissions AS (
          SELECT sa.id, ts.id AS session_id, ts.project_id, sa.created_at, sa.admitted_at,
                 COALESCE(sa.admitted_at, sa.released_at) AS left_at
          FROM session_admissions sa
          JOIN terminal_sessions ts ON ts.id = sa.terminal_session_id
          WHERE ts.company_id = :company_id AND ts.project_id IS NOT NULL AND sa.created_at < :to
        ),
        window_admissions AS (
          SELECT * FROM admissions
          WHERE left_at IS NULL OR left_at >= (
            SELECT MIN(created_at) FROM admissions WHERE admitted_at >= :from AND admitted_at < :to
          )
        ),
        events AS (
          SELECT id, project_id, created_at AS at, 1 AS joining,
                 CASE WHEN left_at IS NULL OR left_at > created_at THEN 1 ELSE 0 END AS change
          FROM window_admissions
          UNION ALL
          SELECT id, project_id, left_at, 0, -1 FROM window_admissions WHERE left_at > created_at
        ),
        ahead AS (
          SELECT id, joining,
                 SUM(change) OVER (ORDER BY at, joining, id ROWS UNBOUNDED PRECEDING) - change AS in_company,
                 SUM(change) OVER (PARTITION BY project_id ORDER BY at, joining, id ROWS UNBOUNDED PRECEDING) - change
                   AS in_project
          FROM events
        ),
        measured AS (
          SELECT a.session_id, a.project_id, a.admitted_at::date AS day,
                 EXTRACT(EPOCH FROM a.admitted_at - a.created_at) AS wait_seconds,
                 q.in_company, q.in_project
          FROM window_admissions a
          JOIN ahead q ON q.id = a.id AND q.joining = 1
          WHERE a.admitted_at >= :from AND a.admitted_at < :to
        )
      SQL
    end

    def wait_aggregates(column = "wait_seconds")
      <<~SQL
        COUNT(*) AS sessions,
        COUNT(*) FILTER (WHERE #{column} > :waited) AS waited,
        AVG(#{column}) AS average,
        PERCENTILE_CONT(ARRAY[#{PERCENTILES.values.join(', ')}]) WITHIN GROUP (ORDER BY #{column}) AS percentiles,
        MAX(#{column}) AS max,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY #{column}) FILTER (WHERE #{column} > :waited) AS p95_of_waited
      SQL
    end

    # Overall, per project and per day, in one pass.
    def session_groups
      rows = select_all(<<~SQL)
        #{measured_sql}
        SELECT GROUPING(project_id, day) AS grouping, project_id, day,
               #{wait_aggregates},
               AVG(in_company) AS ahead_average,
               PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY in_company) AS ahead_p95,
               MAX(in_company) AS ahead_max,
               MAX(in_project) AS ahead_in_project_max
        FROM measured
        GROUP BY GROUPING SETS ((), (project_id), (day))
      SQL

      rows.each_with_object({}) do |row, groups|
        waits = waits_of(row)
        case row["grouping"].to_i
        when 3 then groups[:all] = waits.merge(ahead_of(row))
        when 1 then (groups[:projects] ||= {})[row["project_id"].to_i] = waits.merge(ahead_max: row["ahead_in_project_max"].to_i)
        when 2 then (groups[:days] ||= {})[row["day"].to_s] = waits
        end
      end
    end

    # A workflow run queues once per step, each time at the back of the line;
    # what the run waited is the sum.
    def runs
      row = select_all(<<~SQL).first
        #{measured_sql},
        per_run AS (
          SELECT sr.workflow_run_id, COUNT(*) AS steps, SUM(m.wait_seconds) AS run_wait
          FROM measured m
          JOIN step_runs sr ON sr.terminal_session_id = m.session_id
          GROUP BY sr.workflow_run_id
        )
        SELECT COUNT(*) AS runs, AVG(steps) AS average_steps, #{wait_aggregates('run_wait')}
        FROM per_run
      SQL
      return empty_runs if row.nil? || row["runs"].to_i.zero?

      { runs: row["runs"].to_i, average_steps: row["average_steps"].to_f.round(1), **waits_of(row).except(:sessions) }
    end

    # How much of the time the company had workers all of them were busy at
    # once, and how many of the waits began then. Utilization averages a burst
    # with the idle night around it; this is the share of the time a session
    # joining the queue could not start. A sweep over admit and release events
    # counts the workers held over each stretch between two events, and every
    # hour's start is an event too, so no stretch spans two hours' limits. The
    # limit is the hour's offered workers, as the ledger measured them.
    def capacity
      row = select_all(<<~SQL).first
        WITH admissions AS (
          SELECT sa.created_at, sa.admitted_at, sa.released_at
          FROM session_admissions sa
          JOIN terminal_sessions ts ON ts.id = sa.terminal_session_id
          WHERE ts.company_id = :company_id AND ts.project_id IS NOT NULL
            AND sa.admitted_at IS NOT NULL AND sa.admitted_at < :to
            AND (sa.released_at IS NULL OR sa.released_at > :from)
        ),
        events AS (
          SELECT GREATEST(admitted_at, :from) AS at, 1 AS change, 0 AS waited FROM admissions
          UNION ALL
          SELECT released_at, -1, 0 FROM admissions WHERE released_at < :to
          UNION ALL
          SELECT GREATEST(created_at, :from), 0, 1 FROM admissions
          WHERE admitted_at >= :from AND admitted_at - created_at > :waited * INTERVAL '1 second'
          UNION ALL
          SELECT generate_series(CAST(:from AS timestamp), CAST(:to AS timestamp) - INTERVAL '1 hour', INTERVAL '1 hour'), 0, 0
        ),
        swept AS (
          SELECT at, waited, SUM(change) OVER sweep AS held, LEAD(at, 1, CAST(:to AS timestamp)) OVER sweep AS until
          FROM events
          WINDOW sweep AS (ORDER BY at, change, waited ROWS UNBOUNDED PRECEDING)
        ),
        timed AS (
          SELECT s.waited, EXTRACT(EPOCH FROM s.until - s.at) AS seconds, s.held * 3600 >= h.offered_seconds AS at_capacity
          FROM swept s
          JOIN company_usage_hours h ON h.company_id = :company_id AND h.period_start = date_trunc('hour', s.at)
          WHERE h.offered_seconds > 0
        )
        SELECT SUM(seconds) FILTER (WHERE at_capacity) AS at_capacity_seconds,
               COUNT(*) FILTER (WHERE waited = 1) AS waited,
               COUNT(*) FILTER (WHERE waited = 1 AND at_capacity) AS waited_at_capacity,
               (SELECT COUNT(*) FROM company_usage_hours
                WHERE company_id = :company_id AND period_start >= :from AND period_start < :to AND offered_seconds > 0)
                 AS offered_hours
        FROM timed
      SQL

      hours = row["offered_hours"].to_i
      {
        offered_hours: hours,
        time_at_capacity: hours.positive? ? (row["at_capacity_seconds"].to_f / (hours * 3600)).round(4) : nil,
        waited: row["waited"].to_i,
        waited_at_capacity: row["waited_at_capacity"].to_i
      }
    end

    def projects(stats)
      return [] if stats.empty?

      names = Project.where(id: stats.keys).pluck(:id, :name).to_h
      reserved = SessionConcurrencyLimit.for_projects.where(scope_id: stats.keys).pluck(:scope_id, :max_sessions).to_h
      default = SessionAdmissionPolicy.scope_default("Project")
      stats.map do |id, waits|
        { id: id, name: names.fetch(id, "Project ##{id}"), limit: reserved.fetch(id, default), reserved: reserved.key?(id),
          **waits.slice(:sessions, :waited, :p95, :max, :ahead_max) }
      end.sort_by { |project| [ -project[:waited], -project[:sessions] ] }
    end

    def waits_of(row)
      percentiles = PERCENTILES.keys.zip(decode_floats(row["percentiles"])).to_h
      {
        sessions: row["sessions"].to_i,
        waited: row["waited"].to_i,
        average: seconds(row["average"]),
        **percentiles.transform_values { |value| seconds(value) },
        max: seconds(row["max"]),
        p95_of_waited: seconds(row["p95_of_waited"])
      }
    end

    def ahead_of(row)
      { ahead_average: row["ahead_average"]&.to_f&.round(2), ahead_p95: row["ahead_p95"]&.to_f&.round(1),
        ahead_max: row["ahead_max"]&.to_i }
    end

    # select_all leaves a float8[] as its text form.
    def decode_floats(value)
      return Array.new(PERCENTILES.size) if value.nil?
      return value if value.is_a?(Array)

      value.delete("{}").split(",").map(&:to_f)
    end

    def seconds(value) = value&.to_f&.round

    def empty_waits
      { sessions: 0, waited: 0, average: nil, **PERCENTILES.keys.index_with(nil), max: nil, p95_of_waited: nil,
        ahead_average: nil, ahead_p95: nil, ahead_max: nil }
    end

    def empty_runs
      { runs: 0, average_steps: nil, waited: 0, average: nil, **PERCENTILES.keys.index_with(nil), max: nil,
        p95_of_waited: nil }
    end
  end
end
