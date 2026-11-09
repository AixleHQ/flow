# frozen_string_literal: true

module Runners
  # Creates or updates a runner through its type's adapter: a type without one
  # is refused, the capabilities the adapter derives are stored with the row
  # (§4, §5.1), and the unique-name race becomes an error. The config checks
  # are the model's own validations (Runner, Runners::ConfigSchema), which the
  # plain `save` runs.
  #
  #   Runners::Save.call(runner)  # => true, or false with runner.errors set
  class Save
    def self.call(runner) = new(runner).call

    def initialize(runner)
      @runner = runner
    end

    def call
      runner.capabilities = Adapter.for(runner).capabilities(runner).to_h
      runner.save
    rescue Adapter::UnavailableType
      runner.validate
      runner.errors.add(:runner_type, "is not available yet") if runner.runner_type.present?
      false
    rescue ActiveRecord::RecordNotUnique
      # The unique name index sees the double submit the validation cannot.
      runner.errors.add(:name, :taken)
      false
    end

    private

    attr_reader :runner
  end
end
