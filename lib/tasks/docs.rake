# frozen_string_literal: true

namespace :docs do
  desc "Refresh the in-app docs portal's copy of the configuration reference"
  task :sync_config_reference do
    reference = Rails.root.join("docs/reference/configuration.md")
    portal_copy = Rails.root.join("app/frontend/pages/Docs/data/pages/config-schema.md")

    # The portal bundles its pages as raw markdown at build time, so it needs a
    # file inside app/frontend. One source of truth, one copy, and
    # test/config/configuration_reference_test.rb fails when they diverge.
    portal_copy.write(reference.read)
    puts "Wrote #{portal_copy.relative_path_from(Rails.root)} from #{reference.relative_path_from(Rails.root)}"
  end
end
