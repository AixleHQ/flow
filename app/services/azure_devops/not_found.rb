# frozen_string_literal: true

module AzureDevops
  # Azure has no such entity, or this identity cannot see it. The two are
  # deliberately one code — distinguishing them would confirm that a hidden
  # entity exists.
  class NotFound < Error
    def initialize(message = nil, details: nil)
      super(message, code: "not_found_or_inaccessible", status: 404, details: details)
    end
  end
end
