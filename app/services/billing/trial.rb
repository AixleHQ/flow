# frozen_string_literal: true

module Billing
  # The free allowance a company that signs itself up runs on before anyone has
  # paid: TRIAL_QUEUE_HOURS of capacity, one session at a time, and then it
  # stops.
  #
  # THE ALLOWANCE IS A QUANTITY, NOT A PERIOD, and the customer sets the rate at
  # which it burns. Capacity is billed by the hour it is offered, so a workspace
  # running ten sessions at once spends ten queue-hours an hour and the same
  # hundred hours that would last one workspace four days last that one ten. That
  # is the deal on purpose: the limit is the admin's to choose, and choosing a
  # big one buys a short trial rather than a large gift.
  #
  # The consequence is that the overshoot is bounded only by the metering
  # interval. Nothing is checked between hourly runs, so a workspace that sets a
  # very high limit can spend well past the allowance before the next run stops
  # it. Capping what a trialing workspace may set is the lever if that ever
  # matters; today it is deliberately not capped.
  #
  # THE SPEND IS A SUM, NOT A COUNTER. CompanyCapacityUsage already records every
  # hour a company was offered anything, so what it has used is a question, not a
  # number to keep up to date. A counter beside the log is a counter that drifts
  # from it.
  #
  # Hosted only: a self-hosted operator pays nobody, and a Marketplace customer
  # bought their capacity from AWS before they ever reached us.
  module Trial
    module_function

    def queue_hours = Settings.trial&.queue_hours.to_i

    def seconds = queue_hours * 3600

    def applies?(company)
      Deployment.saas? && company.billing_trialing?
    end

    def used_seconds(company)
      CompanyCapacityUsage.total_seconds_for(company.id)
    end

    def remaining_seconds(company)
      [ seconds - used_seconds(company), 0 ].max
    end

    def used_hours(company)
      (BigDecimal(used_seconds(company)) / 3600).round(1)
    end

    def remaining_hours(company)
      (BigDecimal(remaining_seconds(company)) / 3600).round(1)
    end

    def exhausted?(company)
      used_seconds(company) >= seconds
    end

    # The ceiling a company's own limit is clamped to, or nil where nothing
    # clamps it. Read by both admission and the meter, which have to agree: a
    # ceiling one honours and the other does not either bills for capacity that
    # cannot be used, or lets capacity run that nobody is billed for.
    #
    # Only a company that has spent the allowance has one. While it lasts the
    # limit is whatever the admin set — the allowance is spent faster, not the
    # workspace made smaller.
    def ceiling_for(billing_state)
      0 if billing_state == "blocked"
    end

    # How long what is left lasts at the rate the workspace is running, which is
    # the number an admin actually wants: "40 queue-hours" means four days at one
    # session and four hours at ten. Nil where the rate is unknown, which is a
    # workspace with no limit set at all.
    def hours_left_at(company, max_sessions)
      return nil if max_sessions.nil? || max_sessions.to_i <= 0

      (remaining_hours(company) / max_sessions.to_i).round(1)
    end

    # Run after an hour is measured, which is the only moment the answer can
    # change. Blocking here rather than on the way into a session keeps the check
    # off the admission path entirely: the drain reads a column.
    def enforce!(now: Time.current)
      return [] unless Deployment.saas?

      Company.where(billing_state: "trialing").find_each.filter_map do |company|
        next unless exhausted?(company)

        company.update!(billing_state: "blocked", billing_block_reason: "allowance")
        Rails.logger.info(
          "[Billing::Trial] company #{company.id} spent its #{queue_hours} free queue-hours at #{now.utc.iso8601}"
        )
        company.id
      end
    end
  end
end
