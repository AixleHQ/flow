# frozen_string_literal: true

module Usage
  # Every company's p95 queue wait over a range of UTC days, for the dashboard's
  # table (docs/design/tenant-usage-report.md §7.1). The table sums stored hours,
  # and a percentile does not sum, so the page asks for it per period; the
  # sessions counted are the ones Usage::CompanyBreakdown counts.
  class TenantWaits
    def self.call(...) = new(...).call

    def initialize(from:, to:)
      @from = from.to_time(:utc)
      @to = (to + 1).to_time(:utc)
    end

    def call
      sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, { from: @from, to: @to } ])
        SELECT ts.company_id,
               PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM sa.admitted_at - sa.created_at)) AS p95
        FROM session_admissions sa
        JOIN terminal_sessions ts ON ts.id = sa.terminal_session_id
        WHERE ts.project_id IS NOT NULL AND ts.company_id IS NOT NULL
          AND sa.admitted_at >= :from AND sa.admitted_at < :to
        GROUP BY ts.company_id
        ORDER BY ts.company_id
      SQL

      ActiveRecord::Base.connection.select_all(sql).map do |row|
        { company_id: row["company_id"].to_i, p95: row["p95"].to_f.round }
      end
    end
  end
end
