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
      states = opening_states
      seconds = Hash.new(0)
      payable = Hash.new(0)
      peak = offered_total(limits, states)
      cursor = period_start

      events_during_window.each do |occurred_at, company_id, kind, value|
        accrue(seconds, payable, limits, states, from: cursor, to: occurred_at)
        cursor = occurred_at
        kind == :limit ? limits[company_id] = value.to_i : states[company_id] = value
        total = offered_total(limits, states)
        peak = total if total > peak
      end
      accrue(seconds, payable, limits, states, from: cursor, to: period_end)

      offered = seconds.reject { |_, value| value.zero? }
      billed = payable.slice(*billable_company_ids).reject { |_, value| value.zero? }

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

    # Two totals from one pass. `seconds` is everything the company was offered,
    # which is what a free allowance is spent from; `payable` is the part its
    # current payer owes, which is everything except the time before that payer
    # took over.
    def accrue(seconds, payable, limits, states, from:, to:)
      elapsed = (to - from).round
      return if elapsed <= 0

      limits.each do |company_id, limit|
        state = states[company_id]
        rate = offered(limit, state)
        seconds[company_id] += rate * elapsed
        payable[company_id] += rate * owed_elapsed(company_id, from, to) if owed?(state)
      end
    end

    # Only an active workspace owes for what it was offered. A trialing one is
    # spending a free allowance, and a blocked one was offered nothing anyway.
    #
    # Read from the state it was IN at that moment, which is the whole reason
    # the log exists. Decided here rather than by filtering the live row
    # afterwards: that filter asked what the company is at five past the next
    # hour, so a trial that took a card in those five minutes had its free hour
    # charged, and a workspace stopped by a cancellation lost the minutes it ran
    # before it.
    def owed?(state) = !Deployment.saas? || state == "active"

    # A company that changed payer inside this hour is billed by the new one
    # only from the moment it took over. The time before belonged to the old
    # payer: free where the workspace was trialing, and already on the old
    # payer's final invoice where it was paying -- Billing::FinalUsage measures
    # up to the switch and settles it. Without this the new payer is sent the
    # whole hour and that earlier part is charged twice.
    def owed_elapsed(company_id, from, to)
      since = payer_since[company_id]
      return (to - from).round if since.nil?

      (to - [ from, since ].max).round.clamp(0, (to - from).round)
    end

    # Every switch from the start of this window onwards. One from before it
    # means the payer owned the whole hour, so it is absent and `owed_elapsed`
    # charges for all of it.
    #
    # One from *after* the window matters as much as one inside it, which is
    # what the upper bound used to miss. The hour is measured at five past the
    # next one, and `per_company` is delivered to whichever payer the company
    # has at that moment -- so a switch made in those five minutes left the hour
    # owed in full by a payer who did not hold it for any of it, while the payer
    # who did had already invoiced it. `owed_elapsed` clamps such a switch to
    # zero. What the earlier payer owes is settled elsewhere in every direction:
    # Stripe's FinalUsage going out, the final meter coming back, and free trial
    # time either way.
    def payer_since
      @payer_since ||= Company.where(id: measured_company_ids)
                              .where(billing_provider_since: period_start..)
                              .pluck(:id, :billing_provider_since).to_h
    end

    def offered_total(limits, states)
      limits.sum { |company_id, limit| offered(limit, states[company_id]) }
    end

    # What the company could actually run, which is what it may be charged for.
    # A zero here is a company offered nothing — stopped, or unbounded and
    # therefore unbillable — and the two are told apart by the ceiling, not by
    # the number.
    #
    # Takes the state it was in at the moment being measured, not the state it
    # is in now. A workspace stopped until :47 offered nothing until :47,
    # whatever it has become by the time the hour is measured at five past the
    # next one.
    def offered(configured, state)
      ceiling = ceiling_for(state)
      return configured.to_i if ceiling.nil?

      configured.to_i.zero? ? ceiling : [ configured.to_i, ceiling ].min
    end

    # Nothing clamps anybody outside the hosted product: nobody is on a free
    # allowance there and nothing stops a company that owes us nothing.
    def ceiling_for(state)
      return nil unless Deployment.saas?

      Trial.ceiling_for(state)
    end

    # What every company's billing state was as the hour opened, read the same
    # way as its capacity.
    #
    # The fallback to the live row is a safety net and not the normal path: a
    # migration seeded one entry per company when the log shipped, so a company
    # the log knows nothing about is one created since — and a company created
    # mid-hour is logged on creation, which this reads before the walk applies
    # it. Trusting the live row for a company whose first entry lands *inside*
    # the hour is what the net cannot do correctly, because nothing records what
    # that entry replaced; the seed is what makes that case not arise.
    def opening_states
      logged = CompanyBillingStateChange.state_at(period_start)
      live = Company.where(id: measured_company_ids).pluck(:id, :billing_state).to_h

      measured_company_ids.index_with { |company_id| logged[company_id] || live[company_id] }
    end

    # Capacity and billing state on one timeline, because an hour can hold both
    # and the order between them decides what was offered in between.
    def events_during_window
      limits = changes_during_window.map { |id, max, at| [ at, id, :limit, max ] }
      states = CompanyBillingStateChange
               .during(period_start...period_end)
               .where(company_id: measured_company_ids)
               .pluck(:company_id, :billing_state, :occurred_at)
               .map { |id, state, at| [ at, id, :state, state ] }

      (limits + states).sort_by { |at, id, kind, _| [ at, id, kind.to_s ] }
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
    # What is left to read from the live row, now that the billing state is read
    # from the log instead: a company Aixle carries, which is a standing
    # arrangement and not a thing an hour can change.
    def billable_company_ids
      @billable_company_ids ||= begin
        scope = Company.active
        scope = scope.where(managed_by_aixle: false) if Deployment.saas?
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
