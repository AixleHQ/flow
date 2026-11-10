# frozen_string_literal: true

# An invalid `runners.release` block of config/settings.yml (the platform's
# runner pins) fails boot here, not on the first runner request that reads it. After initialization because Runners::Release lives in
# app/ and is not autoloadable from an initializer.
Rails.application.config.after_initialize do
  Runners::Release.pins
end
