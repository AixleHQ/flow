# frozen_string_literal: true

namespace :ts do
  routes_file = "app/frontend/shared/routes.ts"

  desc "Generate #{routes_file}"
  task routes: :environment do
    Rails.logger.info("Generating #{routes_file}")

    # Get all named routes from Rails
    routes = Rails.application.routes.routes.select do |route|
      route.name.present? # Include all named routes
    end

    puts "Found #{routes.size} named routes"

    # Print all route names for debugging
    puts "Route names:"
    routes.each do |route|
      puts "  - #{route.name}"
    end

    # Generate TypeScript routes with all routes included
    source = TsRoutes.generate(
      # No exclusions - include all named routes
      include: [ /.*/ ],
      # Still exclude any internal Rails routes you don't need
      exclude: [ /rails_/ ]
    )

    # Ensure directory exists
    FileUtils.mkdir_p(File.dirname(routes_file))
    File.write(routes_file, source)
    puts "Successfully generated TypeScript route helpers at #{routes_file}"

    # Notify about the wrapper
    puts "These routes are now available via the Routes.backend namespace in 'shared/routes.ts'"
  end
end
