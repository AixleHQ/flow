# frozen_string_literal: true

module Billing
  # What the installation offered during one hour, integrated over time.
  #
  # TIME-WEIGHTED, NOT PEAK. Half an hour at one and half at three is two
  # queue-hours, not three: the customer had three for thirty minutes and one for
  # thirty, and that is what they are charged for. Billing the peak was the
  # earlier design, justified by capacity reserved being capacity denied to
  # everyone else — which stopped being true when the deployment-wide ceiling was
  # removed. A company's limit now takes nothing from anybody, so there is
  # nothing to charge for beyond the time it was actually offered.
  #
  # EXACT, IN SECONDS. Every change lands on a whole second, so the integral is a
  # whole number and nothing is rounded here. A provider that cannot accept a
  # fraction rounds at its own edge; the others get the exact figure.
  #
  # The peak is measured too, and is not billed. It is what an operator reads to
  # size a cluster, and what makes a bill explicable — "you were charged for 90
  # queue-minutes and never had more than three at once".
  #
  # A company with no limit is unbounded and contributes nothing to a metered
  # quantity, because "unlimited" has no encoding in a metering record. It is
  # counted separately so a deployment that must not have any can say so.
  class CapacityWindow
    Result = Struct.new(:period_start, :quantity_seconds, :peak_concurrent, :per_company,
                        :unbounded_companies, keyword_init: true) do
      def quantity_minutes = (BigDecimal(quantity_seconds) / 60).round(4)
    end

    def self.for_hour(period_start)
      new(period_start).call
    end

    def initialize(period_start)
      @period_start = period_start.utc.beginning_of_hour
    end

    attr_reader :period_start

    def period_end = period_start + 1.hour

    def call
      limits = opening_limits
      seconds = Hash.new(0)
      peak = limits.values.sum
      cursor = period_start

      changes_during_window.each do |company_id, max_sessions, occurred_at|
        accrue(seconds, limits, from: cursor, to: occurred_at)
        cursor = occurred_at
        limits[company_id] = max_sessions.to_i
        total = limits.values.sum
        peak = total if total > peak
      end
      accrue(seconds, limits, from: cursor, to: period_end)

      Result.new(
        period_start: period_start,
        quantity_seconds: seconds.values.sum,
        peak_concurrent: peak,
        per_company: seconds.reject { |_, value| value.zero? },
        unbounded_companies: limits.count { |_, value| value.to_i.zero? }
      )
    end

    private

    def accrue(seconds, limits, from:, to:)
      elapsed = (to - from).round
      return if elapsed <= 0

      limits.each { |company_id, limit| seconds[company_id] += limit.to_i * elapsed }
    end

    # What every company's limit was as the hour opened. The log is the source
    # once a company has ever been written; a company whose limit predates the
    # log falls back to its live row, which is correct while nothing has changed
    # and is the only thing available for capacity set before this shipped.
    def opening_limits
      logged = CompanyCapacityChange.state_at(period_start)
      live = SessionConcurrencyLimit.for_companies.pluck(:scope_id, :max_sessions).to_h

      billable_company_ids.index_with do |company_id|
        logged.key?(company_id) ? logged[company_id].to_i : live[company_id].to_i
      end
    end

    def changes_during_window
      CompanyCapacityChange
        .during(period_start...period_end)
        .where(company_id: billable_company_ids)
        .order(:occurred_at, :id)
        .pluck(:company_id, :max_sessions, :occurred_at)
    end

    # EVERY company, whatever its state. Admission does not look at company state
    # — a suspended organisation's projects still get slots — so metering must
    # not either, or suspending one becomes a way to keep the capacity and stop
    # paying for it. Metering has to measure what admission honours.
    #
    # The day admission starts refusing a suspended company, this filters by the
    # same rule, and the two stay in step.
    def billable_company_ids
      @billable_company_ids ||= Company.pluck(:id)
    end
  end
end
