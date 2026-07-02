# frozen_string_literal: true

# Code-first tool registry lifecycle.
#
# The registry memo holds frozen Definition POROs built from InternalTools::*
# classes; it must be dropped on every code reload so definitions never go
# stale in development (to_prepare runs on boot and after each reload, and may
# run twice — reset is idempotent).
Rails.application.config.to_prepare do
  Tools::Registry.reset!
end

# Boot-time self-heal: project the registry into shadow rows so a forgotten
# deploy-time `platform_tools:seed` can never strand a new platform tool.
# Guarded by a try-advisory-lock (one process reconciles, the rest of a
# rolling restart no-op), a pending-migrations check, a column-existence check
# (pre-migration boots), and rescue-log (a drifted registry must not become a
# crash-looping deploy). Kill switch: AIXLE_TOOLS_RECONCILE_ON_BOOT=0.
Rails.application.config.after_initialize do
  next if Rails.env.test?
  next if ENV["AIXLE_TOOLS_RECONCILE_ON_BOOT"] == "0"
  next if defined?(Rails::Console) || File.basename($PROGRAM_NAME) == "rake"

  Tools::Reconciler.run_if_needed!
end
