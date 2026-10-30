# frozen_string_literal: true

module Billing
  # The free trial a company that signs itself up runs on before anyone has
  # paid: one worker, for TRIAL_DAYS, and then it stops.
  #
  # COUNTED IN HOURS, SHOWN IN DAYS. The trial is an allowance of worker-hours,
  # spent from the same usage log the meter writes. A trialing company is held to
  # one worker (`ceiling_for`), and capacity is counted for every hour it is
  # offered, busy or not, so an hour of the allowance is an hour on the clock:
  # thirty days is 720 worker-hours, and what is left divides into the days a
  # person is shown. The two part only while the company is suspended, which
  # offers nothing and so spends nothing.
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

    # What a trialing company runs at once, whatever limit it set. Its own limit
    # applies once it pays.
    WORKERS = 1

    def days = Settings.trial.days.to_i

    def default_hours = days * 24

    # A trial that starts now ends with the last of its days, today counted as
    # the first — the same day's end an operator's last day has.
    def new_trial_hours(now: Time.current)
      hours_ending_on(now.to_date + days - 1, spent_seconds: 0, from: now)
    end

    # The length of the trial the company is on, kept on the company so a new
    # default changes no trial already under way. A trial from before lengths
    # were kept has none and follows the default.
    def allowance_seconds(company) = (company.trial_hours || default_hours) * 3600

    def applies?(company)
      Deployment.saas? && company.billing_trialing?
    end

    # On the trial or stopped at its end: nobody has paid, so the company has no
    # number of workers to choose yet.
    def workers_fixed?(company)
      Deployment.saas? && company.billing_status.in?(%w[trialing allowance])
    end

    def used_seconds(company) = trial_usage(company).sum(:quantity_seconds)

    # Counted from the start of the trial the company is on: an operator can
    # start a new one (Admin::CompaniesController#update), and only what is spent
    # after that counts against it. The meter records whole hours, so that is
    # from the hour the trial began in.
    def trial_usage(company)
      usage = CompanyCapacityUsage.where(company_id: company.id)
      company.trial_started_at ? usage.since(company.trial_started_at.beginning_of_hour) : usage
    end

    def started_at(company) = company.trial_started_at || company.created_at

    # How far the meter has counted: the end of the last hour it recorded, or the
    # start before it has recorded one. What is left runs on from there, not from
    # now — the hour under way has not been counted yet.
    def measured_until(company)
      last_hour = trial_usage(company).maximum(:period_start)
      last_hour ? last_hour + 1.hour : started_at(company)
    end

    def remaining_seconds(company)
      [ allowance_seconds(company) - used_seconds(company), 0 ].max
    end

    def exhausted?(company)
      used_seconds(company) >= allowance_seconds(company)
    end

    # At one worker what is left is also how long it lasts.
    def last_day(company) = (measured_until(company) + remaining_seconds(company)).to_date

    # Calendar days, the first and the last both counted.
    def length_in_days(company) = (last_day(company) - started_at(company).to_date).to_i + 1

    # Calendar days to the last one, today counted.
    def days_left(company, today: Date.current)
      return 0 if remaining_seconds(company).zero?

      [ (last_day(company) - today).to_i + 1, 0 ].max
    end

    # The length, in worker-hours, of a trial that ends with `last_day`: what it
    # has spent by `from` plus the hours from then to that day's end. Rounded
    # down, so the trial never reaches into the day after.
    def hours_ending_on(last_day, spent_seconds:, from:)
      ((spent_seconds + (last_day.end_of_day - from)) / 3600).floor
    end

    # The ceiling a company's own limit is clamped to, or nil where nothing
    # clamps it. Read by both admission and the meter, which have to agree: a
    # ceiling one honours and the other does not either bills for capacity that
    # cannot be used, or lets capacity run that nobody is billed for.
    def ceiling_for(billing_state)
      case billing_state
      when "trialing" then WORKERS
      when "blocked" then 0
      end
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
          "[Billing::Trial] company #{company.id} spent its #{allowance_seconds(company) / 3600} " \
          "free worker-hours at #{now.utc.iso8601}"
        )
        company.id
      end
    end
  end
end
