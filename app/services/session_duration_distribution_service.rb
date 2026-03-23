# frozen_string_literal: true

class SessionDurationDistributionService
  PERIOD_DAYS = {
    "7d" => 7,
    "30d" => 30,
    "90d" => 90,
    "1y" => 365
  }.freeze

  # Buckets defined as [label, min_seconds, max_seconds (nil = no upper bound)]
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

  def initialize(project:, user:, scope:, period:)
    @project = project
    @user    = user
    @scope   = scope.to_s
    @since   = PERIOD_DAYS.fetch(period.to_s, 30).days.ago
  end

  def call
    sessions = base_sessions
      .where.not(started_at: nil)
      .where.not(finished_at: nil)
      .pluck(Arel.sql("EXTRACT(EPOCH FROM (finished_at - started_at))::integer AS duration_seconds"))

    bucket_counts = BUCKETS.index_with { 0 }

    sessions.each do |duration|
      bucket = BUCKETS.find do |b|
        duration >= b[:min] && (b[:max].nil? || duration < b[:max])
      end
      bucket_counts[bucket] += 1 if bucket
    end

    rows = BUCKETS.map do |bucket|
      BucketRow.new(range: bucket[:range], count: bucket_counts[bucket])
    end

    Result.new(buckets: rows)
  end

  private

  attr_reader :project, :user, :scope, :since

  def base_sessions
    scope_sessions.where(created_at: since..)
  end

  def scope_sessions
    case scope
    when "user"
      project.terminal_sessions.where(user: user)
    when "company"
      TerminalSession
        .joins(:user)
        .where(users: { company_id: project.company_id })
    else
      project.terminal_sessions
    end
  end
end
