# frozen_string_literal: true

class CompanySessionDurationDistributionService
  PERIOD_DAYS = {
    "7d" => 7,
    "30d" => 30,
    "90d" => 90,
    "1y" => 365
  }.freeze

  BUCKETS = [
    { range: "0–1 min",   min: 0,    max: 60 },
    { range: "1–5 min",   min: 60,   max: 300 },
    { range: "5–15 min",  min: 300,  max: 900 },
    { range: "15–30 min", min: 900,  max: 1800 },
    { range: "30–60 min", min: 1800, max: 3600 },
    { range: "60+ min",   min: 3600, max: nil }
  ].freeze

  BucketRow = Struct.new(:range, :count, keyword_init: true)
  Result = Struct.new(:buckets, keyword_init: true)

  def initialize(company:, user:, scope:, period:)
    @company = company
    @user    = user
    @scope   = scope.to_s
    @since   = PERIOD_DAYS.fetch(period.to_s, 30).days.ago
  end

  def call
    bucket_sql = Arel.sql(<<~SQL.squish)
      CASE
        WHEN EXTRACT(EPOCH FROM (finished_at - started_at)) < 60    THEN '0\u20131 min'
        WHEN EXTRACT(EPOCH FROM (finished_at - started_at)) < 300   THEN '1\u20135 min'
        WHEN EXTRACT(EPOCH FROM (finished_at - started_at)) < 900   THEN '5\u201315 min'
        WHEN EXTRACT(EPOCH FROM (finished_at - started_at)) < 1800  THEN '15\u201330 min'
        WHEN EXTRACT(EPOCH FROM (finished_at - started_at)) < 3600  THEN '30\u201360 min'
        ELSE '60+ min'
      END
    SQL

    counts = base_sessions
      .where.not(started_at: nil)
      .where.not(finished_at: nil)
      .group(bucket_sql)
      .count

    rows = BUCKETS.map do |bucket|
      BucketRow.new(range: bucket[:range], count: counts.fetch(bucket[:range], 0))
    end

    Result.new(buckets: rows)
  end

  private

  attr_reader :company, :user, :scope, :since

  def base_sessions
    scope_sessions.where(created_at: since..)
  end

  def scope_sessions
    base = TerminalSession.joins(:project).where(projects: { company_id: company.id })
    scope == "user" ? base.where(user:) : base
  end
end
