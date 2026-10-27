# frozen_string_literal: true

module Runners
  # Creates or updates a runner through its type's adapter: a type without one
  # is refused, the adapter's config rules join the model's validations, and
  # the capabilities the adapter derives are stored with the row (§4, §5.1).
  #
  #   Runners::Save.call(runner)  # => true, or false with runner.errors set
  class Save
    def self.call(runner) = new(runner).call

    def initialize(runner)
      @runner = runner
    end

    def call
      adapter = Adapter.for(runner)
      runner.capabilities = adapter.capabilities(runner).to_h
      runner.validate
      adapter.validate_config(runner).each { |message| runner.errors.add(:config, message) } if runner.errors[:config].empty?
      runner.errors.empty? && runner.save(validate: false)
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
