# frozen_string_literal: true

# Flag lifecycle (docs/architecture/feature-flags.md). Neither task runs on its
# own: audit is read in the ops review, prune is a manual post-rollout step.
namespace :feature_flags do
  desc "List flags due for removal: release flags past remove_by, flags the same for every company for 30+ days, " \
       "orphaned rows and FEATURE_* variables for undeclared keys. Changes nothing."
  task audit: :environment do
    puts FeatureFlags::Lifecycle.describe(FeatureFlags::Lifecycle.new.report)
  end

  desc "Delete the rows of keys config/feature_flags.yml no longer declares, with a feature_flag.pruned audit per key. " \
       "Idempotent. Run only once the rollout has replaced every pod running the previous code."
  task prune: :environment do
    pruned = FeatureFlags::Lifecycle.new.prune
    if pruned.empty?
      puts "[feature_flags:prune] no orphaned rows"
    else
      pruned.each { |key| puts "[feature_flags:prune] deleted the rows of #{key}" }
      puts "[feature_flags:prune] pruned #{pruned.size} key(s)"
    end
  end
end
