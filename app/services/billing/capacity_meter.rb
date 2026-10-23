# frozen_string_literal: true

module Billing
  # Measures the hours the installation has closed and hands each one to every
  # provider that bills someone on it.
  #
  # More than one can, and that is the whole reason this takes a list: the hosted
  # product invoices some companies through Stripe and AWS invoices others, on
  # the same installation and in the same hour. The hour is measured once —
  # capacity offered is not a per-provider fact — and each provider claims its own
  # ledger row for it, which is what `capacity_meter_reports` was already keyed
  # for.
  #
  # ONE ATTEMPT PER HOUR, NOT ONE RETRY LOOP. AWS Marketplace enforces its
  # once-per-hour rule per EKS pod, so a retry that lands on a different replica
  # finds an unused budget and bills the customer twice — `DuplicateRequestException`
  # never fires. Recovery is therefore the next run replaying the ledger, not a
  # retry inside this one, and the six-hour replay window is the same number that
  # bounds what AWS will still accept.
  class CapacityMeter
    ADAPTERS = {
      Deployment::SELF_HOSTED => [ Meter::Null ],
      Deployment::SAAS => [ Meter::Stripe, Meter::AwsMarketplaceSaas ],
      Deployment::AWS_MARKETPLACE => [ Meter::AwsMarketplace ]
    }.freeze

    def self.adapters_for(mode = Deployment.mode)
      ADAPTERS.fetch(mode, [ Meter::Null ]).map(&:new).select(&:enabled?)
    end

    def initialize(adapters: self.class.adapters_for, now: Time.current)
      @adapters = adapters
      @now = now.utc
    end

    attr_reader :adapters, :now

    # Records the hour that has just closed, then sends everything still unsent
    # inside the replay window — including the hour just recorded.
    def call
      measure!(now.beginning_of_hour - 1.hour)
      # After the hour is recorded and before anything is sent: the hour that
      # spends the last of a company's free allowance is the hour that stops it,
      # and this is the only moment the answer can change.
      Trial.enforce!(now: now)
      deliver_pending
    end

    # Measures once and claims one row per provider. Measuring is separate from
    # sending so a provider outage never loses the measurement.
    def measure!(period_start)
      window = CapacityWindow.for_hour(period_start)
      # Ours, and written for everyone — including the companies no provider is
      # sent. It is what the free allowance is counted from and what anyone asks
      # when they want to know what a single company had.
      record_usage(window)

      adapters.map { |adapter| claim(adapter, window) }
    end

    def record_usage(window)
      window.offered_per_company.each do |company_id, quantity_seconds|
        CompanyCapacityUsage.record!(
          company_id: company_id, period_start: window.period_start, quantity_seconds: quantity_seconds
        )
      end
    end

    # Summed across providers, so a caller still reads one number for "hours sent
    # this run", with the per-provider detail beside it.
    def deliver_pending
      per_provider = adapters.map { |adapter| deliver_for(adapter) }

      {
        sent: per_provider.sum { |result| result[:sent] },
        failed: per_provider.sum { |result| result[:failed] },
        providers: per_provider
      }
    end

    private

    def claim(adapter, window)
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

    def deliver_for(adapter)
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

      abandon_expired(adapter)
      { provider: adapter.provider, sent: sent.size, failed: failed.size }
    end

    # Past the replay window AWS will not accept the record whatever we do, so
    # leaving it "failed" forever would make the ledger a list nobody can act on.
    def abandon_expired(adapter)
      CapacityMeterReport
        .unsent
        .where(provider: adapter.provider)
        .where(period_start: ...(now - CapacityMeterReport::REPLAY_WINDOW))
        .find_each { |report| report.update!(state: "skipped") }
    end
  end
end
