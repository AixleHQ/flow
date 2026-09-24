# frozen_string_literal: true

namespace :templates do
  desc "Validate a templates repository checkout: ROOT=path [BASE=path-to-base-branch-checkout]"
  task validate: :environment do
    root = ENV.fetch("ROOT") { abort "ROOT=path/to/flow-templates is required" }
    errors = Templates::RepositoryValidator.call(root: root, base_root: ENV["BASE"].presence)

    if errors.empty?
      puts "All templates are valid."
    else
      errors.each do |slug, problems|
        puts "#{slug}:"
        problems.each { |problem| puts "  - #{problem}" }
      end
      abort "#{errors.size} template(s) failed validation."
    end
  end
end
