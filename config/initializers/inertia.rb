# frozen_string_literal: true

InertiaRails.configure do |config|
  config.ssr_enabled = false
  config.default_render = false
  config.always_include_errors_hash = true
  config.use_script_element_for_initial_page = true

  # A tab still on the previous deploy's bundle is answered 409 on its next visit
  # and reloads, instead of lazy-loading chunks the new deploy no longer serves.
  # Off in test: the gem's own helpers (inertia_reload_only and friends) send no
  # X-Inertia-Version, so every partial reload in the suite would get a 409.
  config.version = ViteRuby.digest unless Rails.env.test?

  # Props reach the page from more than resources (bare hashes, lambdas), so the
  # camelization runs here too; over a resource payload, which now camelizes its
  # own nested keys, it is a no-op.
  config.prop_transformer = lambda { |props:|
    DeepKeyCamelizer.call(props)
  }
end
