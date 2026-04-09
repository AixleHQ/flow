# frozen_string_literal: true

class ApplicationResource
  include Alba::Resource
  include Typelizer::DSL
  include Rails.application.routes.url_helpers

  transform_keys :lower_camel

  class << self
    def preserve_keys(*keys)
      @_preserve_keys = keys.map { |k| k.to_s.camelize(:lower) }
    end

    def _preserve_keys
      @_preserve_keys || []
    end
  end

  def to_h
    result = super
    keys = self.class._preserve_keys
    result["_preserveKeys"] = keys if keys.any?
    result
  end
end
