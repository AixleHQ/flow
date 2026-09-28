# frozen_string_literal: true

module Billing
  # The free allowance a company that signs itself up runs on before anyone has
  # paid: TRIAL_QUEUE_HOURS of capacity, one session at a time, and then it
  # stops.
  #
  # THE ALLOWANCE IS A QUANTITY, NOT A PERIOD, and the customer sets the rate at
  # which it burns. That is why the cap exists: capacity is billed by the hour it
  # is offered, so a trial measured in days would be priced by whoever set the
  # limit — ten queues for a fortnight is $16,800 of free capacity, chosen by the
  # person receiving it. Capped at one session, the allowance is the same gift to
  # everyone, and a hundred hours of it lasts about four days.
  #
  # THE SPEND IS A SUM, NOT A COUNTER. CompanyCapacityUsage already records every
  # hour a company was offered anything, so what it has used is a question, not a
  # number to keep up to date. A counter beside the log is a counter that drifts
  # from it.
  #
  # Hosted only: a self-hosted operator pays nobody, and a Marketplace customer
  # bought their capacity from AWS before they ever reached us.
  module Trial
    # One session at a time while the allowance lasts. Not a setting: it is what
    # makes the allowance the same gift to everyone rather than a length of time
    # the recipient chooses.
    MAX_SESSIONS = 1

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
    def ceiling_for(billing_state)
      case billing_state
      when "blocked" then 0
      when "trialing" then MAX_SESSIONS
      end
    end

    # Run after an hour is measured, which is the only moment the answer can
    # change. Blocking here rather than on the way into a session keeps the check
    # off the admission path entirely: the drain reads a column.
    def enforce!(now: Time.current)
      return [] unless Deployment.saas?

      Company.where(billing_state: "trialing").find_each.filter_map do |company|
        next unless exhausted?(company)

        company.update!(billing_state: "blocked")
        Rails.logger.info(
          "[Billing::Trial] company #{company.id} spent its #{queue_hours} free queue-hours at #{now.utc.iso8601}"
        )
        company.id
      end
    end
  end
end
