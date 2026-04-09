# frozen_string_literal: true

module InertiaPropsCamelizer
  PRESERVE_MARKER = "_preserveKeys"

  def self.call(obj, preserve: false)
    case obj
    when Hash
      preserved = Set.new(obj[PRESERVE_MARKER] || [])

      obj.each_with_object({}) do |(k, v), result|
        next if k == PRESERVE_MARKER

        new_key = preserve ? k : k.to_s.camelize(:lower)
        skip_children = preserved.include?(new_key)
        result[new_key] = call(v, preserve: skip_children)
      end
    when Array
      obj.map { |item| call(item, preserve: preserve) }
    else
      obj
    end
  end
end

InertiaRails.configure do |config|
  config.ssr_enabled = false
  config.default_render = false
  config.always_include_errors_hash = true
  config.use_script_element_for_initial_page = true

  config.prop_transformer = lambda { |props:|
    InertiaPropsCamelizer.call(props)
  }
end
