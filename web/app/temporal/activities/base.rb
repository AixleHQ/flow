require "temporalio/activity"

class Activities::Base < Temporalio::Activity::Definition
  class << self
    def inherited(subclass)
      super
      activity_name = subclass.name.split("::")[1..-1].join("_").underscore
      subclass.activity_name(activity_name) unless subclass.instance_variable_get(:@activity_name)
    end
  end

  def name
    self.class.instance_variable_get(:@activity_name)
  end

  def execute(input = nil)
    log(:info, "[#{name}] activity execution started")
    hashie_input = input.is_a?(Hash) ? Hashie::Mash.new(input) : input
    result = run(hashie_input)
    log(:info, "[#{name}] activity execution completed")
    result
  rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid => e
    log(:error, "[#{name}] activity execution failed: #{e.message}")
    log(:error, e.backtrace.join("\n"))
    raise TemporalExceptions.wrap(e, retryable: false)
  end

  def log(level, message)
    Rails.logger.send(level, "[#{name}] #{message}") unless Rails.env.test?
  end

  def serialize_model(model)
    return nil if model.blank?

    ModelDefinitionSerializer.new(model).as_json
  end
end
