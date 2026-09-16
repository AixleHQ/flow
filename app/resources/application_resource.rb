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
  #
  # Alba's `transform_keys` only renames the attribute names it knows about, so a
  # hash built inside an `attribute` block (a gate, a child task) used to keep its
  # Ruby keys. That was invisible for Inertia, whose prop transformer camelizes the
  # whole tree, and wrong for every JSON endpoint rendering the same resource: the
  # frontend read `gateType` off a payload that said `gate_type`. Camelizing the
  # nested keys here makes one shape for both transports; `preserve_keys` opts an
  # opaque value hash out, as it already did for props.
  # A resource used as a `many` association target (e.g. `many :tool_files, resource:
  # ToolFileResource`) has `to_h` invoked directly on the whole collection, not just
  # per record — Alba's `Association#to_h_with_constantize_resource` instantiates the
  # resource with the association's collection as `@object` and calls `.to_h` once.
  # `super` (`Alba::Resource#serializable_hash`) then returns an Array of per-record
  # hashes rather than a single Hash, so this must camelize/snake each element instead
  # of treating the whole result as one record's attribute hash.
  def to_h
    result = super
    result.is_a?(Array) ? result.map { |item| transform_record(item) } : transform_record(result)
  end

  private

  def transform_record(hash)
    snake = params[:snake_keys]
    keys = self.class._preserve_keys
    result = snake ? snake_keys(hash) : camelize_nested(hash, keys)
    if keys.any?
      result[snake ? "_preserve_keys" : "_preserveKeys"] = snake ? keys.map { |k| k.to_s.underscore } : keys
    end
    result
  end

  # Top-level names are Alba's job (`transform_keys :lower_camel`); this walks the
  # values under them.
  def camelize_nested(hash, preserve_keys)
    hash.each_with_object({}) do |(key, value), result|
      result[key] = preserve_keys.include?(key.to_s) ? value : DeepKeyCamelizer.call(value)
    end
  end

  def snake_keys(hash)
    names = self.class._attributes.keys.index_by { |name| name.to_s.camelize(:lower) }
    hash.transform_keys { |key| names[key.to_s]&.to_s || key.to_s }
  end
end
