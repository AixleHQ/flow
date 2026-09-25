# frozen_string_literal: true

module Billing
  # Measures the hours the installation has closed and hands each one to the
  # provider its deployment mode bills through.
  #
  # ONE ATTEMPT PER HOUR, NOT ONE RETRY LOOP. AWS Marketplace enforces its
  # once-per-hour rule per EKS pod, so a retry that lands on a different replica
  # finds an unused budget and bills the customer twice — `DuplicateRequestException`
  # never fires. Recovery is therefore the next run replaying the ledger, not a
  # retry inside this one, and the six-hour replay window is the same number that
  # bounds what AWS will still accept.
  class CapacityMeter
    ADAPTERS = {
      Deployment::SELF_HOSTED => Meter::Null,
      Deployment::SAAS => Meter::Stripe,
      Deployment::AWS_MARKETPLACE => Meter::AwsMarketplace
    }.freeze

    def self.adapter_for(mode = Deployment.mode)
      ADAPTERS.fetch(mode, Meter::Null).new
    end

    def initialize(adapter: self.class.adapter_for, now: Time.current)
      @adapter = adapter
      @now = now.utc
    end

    attr_reader :adapter, :now

    # Records the hour that has just closed, then sends everything still unsent
    # inside the replay window — including the hour just recorded.
    def call
      measure!(now.beginning_of_hour - 1.hour)
      deliver_pending
    end

    # Claims the row for an hour, or returns the existing one. Measuring is
    # separate from sending so a provider outage never loses the measurement.
    def measure!(period_start)
      window = CapacityWindow.for_hour(period_start)
      report = CapacityMeterReport.find_or_initialize_by(provider: adapter.provider, period_start: window.period_start)
      return report if report.persisted?

      report.update!(
        quantity_seconds: window.quantity_seconds,
        peak_concurrent: window.peak_concurrent,
        breakdown: window.per_company,
        unbounded_companies: window.unbounded_companies,
        state: "pending"
      )
      report
    rescue ActiveRecord::RecordNotUnique
      CapacityMeterReport.find_by!(provider: adapter.provider, period_start: window.period_start)
    end

    def deliver_pending
      sent = []
      failed = []

      CapacityMeterReport.replayable(now).where(provider: adapter.provider).order(:period_start).each do |report|
        begin
          report.reported!(adapter.deliver(report))
          sent << report.period_start
        rescue StandardError => e
          report.failed!(e.message)
          failed << report.period_start
        end
      end

      abandon_expired
      { provider: adapter.provider, sent: sent.size, failed: failed.size }
    end

    private

    # Past the replay window AWS will not accept the record whatever we do, so
    # leaving it "failed" forever would make the ledger a list nobody can act on.
    def abandon_expired
      CapacityMeterReport
        .unsent
        .where(provider: adapter.provider)
        .where(period_start: ...(now - CapacityMeterReport::REPLAY_WINDOW))
        .find_each { |report| report.update!(state: "skipped") }
    end
  end
end
