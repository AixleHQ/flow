# frozen_string_literal: true

# A 404 with the app's not-found page (app/views/errors/not_found.html.erb) when a
# browser asked for a page, and an empty one otherwise, so an API client or a
# fetch gets no HTML it did not ask for.
module NotFoundPage
  extend ActiveSupport::Concern

  private

  def render_not_found
    return head(:not_found) unless request.format.html?

    render "errors/not_found", layout: false, status: :not_found, formats: :html
  end
end
