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

  # `params[:snake_keys]` serializes this resource in Ruby conventions instead.
  # The camelCase above exists for the Inertia/TS frontend; agent-facing
  # surfaces (MCP and workflow tools) speak snake_case like the rest of the
  # app, so a tool payload matches the column and param names an agent reads
  # everywhere else. Only declared attribute names are renamed — opaque value
  # hashes (gate metadata, asset metadata) keep their own keys verbatim.
  def to_h
    result = super
    snake = params[:snake_keys]
    result = snake_keys(result) if snake
    keys = self.class._preserve_keys
    if keys.any?
      result[snake ? "_preserve_keys" : "_preserveKeys"] = snake ? keys.map { |k| k.to_s.underscore } : keys
    end
    result
  end

  private

  def snake_keys(hash)
    names = self.class._attributes.keys.index_by { |name| name.to_s.camelize(:lower) }
    hash.transform_keys { |key| names[key.to_s]&.to_s || key.to_s }
  end
end
