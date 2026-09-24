# frozen_string_literal: true

# Staging runs production's configuration. Anything it must do differently goes in
# a Rails.application.configure block here, and nothing else: every override is a
# way staging stops testing production.
require_relative "production"
