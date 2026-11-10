# frozen_string_literal: true

# The platform's runner pins are a committed file of their own,
# config/runner_release.yml, read as Settings.runners.release
# (docs/design/agent-runtimes/DESIGN.md §14.2). Runners::Release validates them
# once the app is loaded (config/initializers/runner_release.rb).
Settings.add_source!({ "runners" => { "release" => YAML.safe_load_file(Rails.root.join("config/runner_release.yml")) } })
Settings.reload!
