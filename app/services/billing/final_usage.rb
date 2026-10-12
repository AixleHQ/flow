# frozen_string_literal: true

module Billing
  # What a company cancelling now was offered that Stripe has not counted yet,
  # hour by hour.
  #
  # MEASURED BEFORE THE COMPANY IS STOPPED. The hourly run measures an hour
  # after it closes, against the company as it is then — and a stopped company
  # is offered nothing and billed for none of it. Left to that run, the hour
  # under way at the cancellation, and the one before it if the run had not got
  # to it yet, would never be billed at all.
  #
  # Keyed the way the meter keys an hour, so a send from here and one from the
  # hourly run are the same event to Stripe, and whichever lands second is
  # refused as already recorded rather than billed twice.
  class FinalUsage
    Measurement = Data.define(:billed, :offered, :measured)

    def initialize(company, until_time:)
      @company = company
      @until_time = until_time.utc
    end

    attr_reader :company, :until_time

    # Hour => billed worker-seconds, only the hours with any.
    def billed
      measurements.transform_values(&:billed).select { |_, seconds| seconds.positive? }
    end

    # The hours measured here, into the company's own ledger: the hourly run
    # will not write them once the company is stopped. The hours that came from
    # the meter's ledger were written when it measured them.
    def record!
      measurements.each do |hour, measurement|
        next unless measurement.measured && measurement.offered.positive?

        CompanyCapacityUsage.record!(company_id: company.id, period_start: hour, quantity_seconds: measurement.offered)
      end
    end

    private

    def measurements
      @measurements ||= from_ledger.merge(measured_here)
    end

    def current_hour = until_time.beginning_of_hour

    def last_closed_hour = current_hour - 1.hour

    # Every hour the ledger still holds unsent, and the hour just closed even
    # when it was sent: Stripe takes about a minute to count an event, so one
    # sent seconds before the cancellation is not on the invoice yet either, and
    # the settlement has to wait for it the same way.
    def from_ledger
      reports.each_with_object({}) do |report, hours|
        next unless report.state.in?(%w[pending failed]) || report.period_start == last_closed_hour

        seconds = report.breakdown[company.id.to_s].to_i
        hours[report.period_start.utc] = Measurement.new(billed: seconds, offered: seconds, measured: false)
      end
    end

    def reports
      @reports ||= CapacityMeterReport
                   .where(provider: Meter::Stripe.provider)
                   .where(period_start: (until_time - CapacityMeterReport::REPLAY_WINDOW)...current_hour)
                   .to_a
    end

    def measured_here
      hours = { current_hour => measure(current_hour) }
      hours[last_closed_hour] = measure(last_closed_hour) if reports.none? { |r| r.period_start == last_closed_hour }
      hours
    end

    def measure(hour)
      window = CapacityWindow.for_hour(hour, until_time: until_time, company_ids: [ company.id ])
      Measurement.new(billed: window.per_company[company.id].to_i,
                      offered: window.offered_per_company[company.id].to_i,
                      measured: true)
    end
  end
end
