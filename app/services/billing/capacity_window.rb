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
                        :offered_per_company, :unbounded_companies, keyword_init: true) do
      def quantity_minutes = (BigDecimal(quantity_seconds) / 60).round(4)
    end

    def self.for_hour(period_start, until_time: nil, company_ids: nil)
      new(period_start, until_time: until_time, company_ids: company_ids).call
    end

    # `until_time` cuts the hour short — a company cancelling at 14:20 is billed
    # 14:00–14:20 and nothing after. `company_ids` narrows the measurement to
    # them; everyone else is left out, not counted as zero.
    def initialize(period_start, until_time: nil, company_ids: nil)
      @period_start = period_start.utc.beginning_of_hour
      @period_end = [ @period_start + 1.hour, until_time&.utc ].compact.min
      @company_ids = company_ids
    end

    attr_reader :period_start, :period_end

    def call
      limits = opening_limits
      seconds = Hash.new(0)
      peak = offered_total(limits)
      cursor = period_start

      changes_during_window.each do |company_id, max_sessions, occurred_at|
        accrue(seconds, limits, from: cursor, to: occurred_at)
        cursor = occurred_at
        limits[company_id] = max_sessions.to_i
        total = offered_total(limits)
        peak = total if total > peak
      end
      accrue(seconds, limits, from: cursor, to: period_end)

      offered = seconds.reject { |_, value| value.zero? }
      billed = offered.slice(*billable_company_ids)

      Result.new(
        period_start: period_start,
        quantity_seconds: billed.values.sum,
        peak_concurrent: peak,
        per_company: billed,
        offered_per_company: offered,
        unbounded_companies: limits.count { |_, value| value.to_i.zero? }
      )
    end

    private

    def accrue(seconds, limits, from:, to:)
      elapsed = (to - from).round
      return if elapsed <= 0

      limits.each { |company_id, limit| seconds[company_id] += offered(company_id, limit) * elapsed }
    end

    def offered_total(limits)
      limits.sum { |company_id, limit| offered(company_id, limit) }
    end

    # What the company could actually run, which is what it may be charged for.
    # A zero here is a company offered nothing — blocked, or unbounded and
    # therefore unbillable — and the two are told apart by `ceilings`, not by the
    # number.
    def offered(company_id, configured)
      ceiling = ceilings[company_id]
      return configured.to_i if ceiling.nil?

      configured.to_i.zero? ? ceiling : [ configured.to_i, ceiling ].min
    end

    def ceilings
      @ceilings ||= Billing::EffectiveCapacity.ceilings
    end

    # What every company's limit was as the hour opened. The log is the source
    # for every company that appears in it at all; one that does not falls back
    # to its live row, which is the only thing available for capacity set before
    # the log shipped.
    #
    # The fallback is read narrowly on purpose. A company whose first entry lands
    # *during* this hour is in the log, so it opened the hour at nothing — taking
    # its live row instead would read today's capacity back to the top of the
    # hour and bill a customer who signed up at 04:26 for the whole of 04:00.
    # That is every new customer's first hour, so the narrow reading costs at
    # most one under-billed hour for a pre-log company whose first change happens
    # to land between the hour ending and this running, and saves an overcharge
    # that would otherwise happen every time.
    def opening_limits
      logged = CompanyCapacityChange.state_at(period_start)
      live = SessionConcurrencyLimit.for_companies.pluck(:scope_id, :max_sessions).to_h

      measured_company_ids.each_with_object({}) do |company_id, limits|
        if logged.key?(company_id)
          limits[company_id] = logged[company_id].to_i
        elsif ever_logged.exclude?(company_id)
          limits[company_id] = live[company_id].to_i
        end
      end
    end

    # Companies the log knows anything about, whenever it was written. One of
    # these missing from `logged` is left out of the opening entirely rather
    # than opened at zero, because a zero here means "no limit set", which
    # `offered` answers with the company's ceiling. It enters the window when
    # its first change does.
    def ever_logged
      @ever_logged ||= CompanyCapacityChange.where(company_id: measured_company_ids)
                                            .distinct.pluck(:company_id).to_set
    end

    def changes_during_window
      CompanyCapacityChange
        .during(period_start...period_end)
        .where(company_id: measured_company_ids)
        .order(:occurred_at, :id)
        .pluck(:company_id, :max_sessions, :occurred_at)
    end

    # Active companies only, which is honest because admission refuses every other
    # kind (SessionService#preflight_company_active!). The two rules have to agree:
    # billing for capacity that cannot be occupied overcharges, and metering a
    # company that can still run would make suspending one a way to keep the
    # capacity and stop paying for it.
    def billable_company_ids
      @billable_company_ids ||= begin
        scope = Company.active
        # A company spending its free allowance, or stopped for having spent it,
        # is offered capacity and invoiced for none of it. The usage is still
        # recorded — that is what the allowance is counted from — but it is not
        # what a provider is sent.
        scope = scope.billing_billable if Deployment.saas?
        scope.pluck(:id)
      end
    end

    # Everyone whose capacity is measured, billable or not.
    def measured_company_ids
      @measured_company_ids ||= begin
        scope = Company.active
        scope = scope.where(id: @company_ids) if @company_ids
        scope.pluck(:id)
      end
    end
  end
end
