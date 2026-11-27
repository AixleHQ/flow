# frozen_string_literal: true

namespace :templates do
  desc "Validate a templates repository checkout: ROOT=path [BASE=path] [AUTHOR=login] [AUTHOR_IS_MAINTAINER=true]"
  task validate: :environment do
    root = ENV.fetch("ROOT") { abort "ROOT=path/to/flow-templates is required" }
    validator = Templates::RepositoryValidator.new(
      root: root, base_root: ENV["BASE"].presence, author: ENV["AUTHOR"].presence,
      author_is_maintainer: ENV["AUTHOR_IS_MAINTAINER"] == "true"
    )
    errors = validator.call

    # Warnings never fail the task.
    validator.warnings.each do |identifier, messages|
      puts "#{identifier}:"
      messages.each { |message| puts "  - warning: #{message}" }
    end

    if errors.empty?
      puts "All templates are valid."
    else
      errors.each do |identifier, problems|
        puts "#{identifier}:"
        problems.each { |problem| puts "  - #{problem}" }
      end
      abort "#{errors.size} template(s) failed validation."
    end
  end
end
