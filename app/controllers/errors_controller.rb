# frozen_string_literal: true

# The exceptions app (config/application.rb): a page a browser asked for that
# does not exist, a route or a record, gets the app's not-found page; every other
# error, and any 404 for a client that did not ask for HTML, keeps Rails' static
# answer from public/. A bare ActionController::Base, so an error page runs none
# of the app's sign-in, workspace or browser gates.
class ErrorsController < ActionController::Base
  include NotFoundPage

  STATIC = ActionDispatch::PublicExceptions.new(Rails.public_path)

  # A POST to a path that does not exist reaches here as a POST, with no token
  # this page could check.
  skip_forgery_protection

  def self.call(env)
    request = ActionDispatch::Request.new(env)
    return STATIC.call(env) unless request.path_info == "/404" && page_wanted?(request)

    action(:not_found).call(env)
  end

  def self.page_wanted?(request)
    request.formats.first&.html?
  rescue ActionDispatch::Http::MimeNegotiation::InvalidType
    false
  end
  private_class_method :page_wanted?

  def not_found = render_not_found
end
