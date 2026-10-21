# frozen_string_literal: true

namespace :feature_flags do
  desc "Generate app/frontend/types/generated/featureFlags.ts from config/feature_flags.yml"
  task typescript: :environment do
    path = FeatureFlags::Typescript.write
    puts "Generated #{Pathname(path).relative_path_from(Rails.root)}"
  end
end

# The flag names are generated types like the Typelizer ones, so the same step
# writes both. `refresh` empties the output directory first, which would
# otherwise delete featureFlags.ts.
%w[typelizer:generate typelizer:generate:refresh].each do |name|
  next unless Rake::Task.task_defined?(name)

  Rake::Task[name].enhance do
    Rake::Task["feature_flags:typescript"].reenable
    Rake::Task["feature_flags:typescript"].invoke
  end
end
