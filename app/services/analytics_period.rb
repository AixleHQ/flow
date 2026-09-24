# frozen_string_literal: true

# The periods every analytics view offers and how a time series buckets each one,
# defined once for every analytics service.
module AnalyticsPeriod
  DAYS = { "7d" => 7, "30d" => 30, "90d" => 90, "1y" => 365 }.freeze
  DEFAULT = "30d"
  BUCKETS = { "7d" => "day", "30d" => "day", "90d" => "week", "1y" => "month" }.freeze

  # The sessions that do work, and so count toward usage and session totals: a
  # login (auth_setup) or a tool setup is neither.
  USAGE_SESSION_TYPES = %w[agent_session workflow_step].freeze

  module_function

  def days(period)
    DAYS.fetch(period.to_s, DAYS.fetch(DEFAULT))
  end

  def since(period)
    days(period).days.ago
  end

  def bucket(period)
    BUCKETS.fetch(period.to_s, "day")
  end

  # DATE_TRUNC('<the period's bucket>', <attribute>) as an Arel node, for
  # group/order/pluck — built, not interpolated.
  def date_trunc(period, attribute)
    Arel::Nodes::NamedFunction.new("DATE_TRUNC", [ Arel::Nodes.build_quoted(bucket(period)), attribute ])
  end
end
