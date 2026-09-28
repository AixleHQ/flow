# frozen_string_literal: true

module Billing
  # How many sessions a company may actually run at once.
  #
  # ONE NUMBER, TWO CONSUMERS. The drain hands out slots against it and the meter
  # bills for it, and they must be the same number. A company capped to one
  # session while trialing has to be metered at one too, or the first invoice is
  # for capacity that was never available.
  #
  # Its own limit is the ceiling it asked for; this is the ceiling it gets.
  # Outside the hosted product the two are always the same — nobody is on a free
  # allowance, and nothing blocks a company that owes us nothing.
  module EffectiveCapacity
    module_function

    # company_id => the ceiling their configured limit is clamped to. A company
    # absent from the hash is clamped by nothing.
    def ceilings
      return {} unless Deployment.saas?

      Company.where.not(billing_state: "active")
             .pluck(:id, :billing_state)
             .to_h { |company_id, state| [ company_id, Trial.ceiling_for(state) ] }
             .compact
    end

    # company_id => sessions at once. A company absent from the hash is
    # unbounded, which is what a missing SessionConcurrencyLimit row means
    # everywhere else.
    def for_companies
      configured = SessionConcurrencyLimit.for_companies.pluck(:scope_id, :max_sessions).to_h
      ceilings.each do |company_id, ceiling|
        configured[company_id] = clamp(configured[company_id], ceiling)
      end
      configured
    end

    # An unbounded company under a ceiling is bounded by it: "no limit set" is not
    # a way past one.
    def clamp(configured, ceiling)
      return configured if ceiling.nil?
      return ceiling if configured.nil?

      [ configured, ceiling ].min
    end
  end
end
