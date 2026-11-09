# frozen_string_literal: true

# An invalid config/runner_release.yml fails boot here, not on the first runner
# request that reads it. After initialization because Runners::Release lives in
# app/ and is not autoloadable from an initializer.
Rails.application.config.after_initialize do
  Runners::Release.pins
end
