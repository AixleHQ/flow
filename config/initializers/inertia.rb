# frozen_string_literal: true

InertiaRails.configure do |config|
  config.ssr_enabled = false
  config.default_render = false
  config.always_include_errors_hash = true
  config.use_script_element_for_initial_page = true

  # Props reach the page from more than resources (bare hashes, lambdas), so the
  # camelization runs here too; over a resource payload, which now camelizes its
  # own nested keys, it is a no-op.
  config.prop_transformer = lambda { |props:|
    DeepKeyCamelizer.call(props)
  }
end
