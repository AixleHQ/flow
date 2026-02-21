# frozen_string_literal: true

# Fix for Rails 8 compatibility with Administrate
# In Rails 8, ActiveSupport::Deprecation.warn became a private class method
# and should be called on Rails.deprecator instead
if Rails.version >= "7.1"
  module ActiveSupport
    class Deprecation
      class << self
        public :warn
        public :warn
      end
    end
  end
end
