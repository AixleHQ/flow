# frozen_string_literal: true

module Trackers
  # A file on an issue (docs/design/tracker-attachments.md §6.2).
  #
  # `origin` is :attached for a file in the tracker's attachment list and
  # :embedded for one that exists only as a URL in the issue's text.
  # `location` says where an embedded file is referenced:
  # { "kind" => "description" | "comment", "id" => comment id }.
  # `restricted` is a file fewer people can see than the issue; it is listed
  # and never fetched. `available` is false for a file no API token can fetch.
  # `url` is for a person's browser, never a signed or credential-bearing URL.
  Attachment = Data.define(:id, :issue_id, :name, :size, :content_type, :created_at, :origin, :location,
                           :restricted, :available, :url) do
    include Value

    def initialize(id:, issue_id:, name:, size: nil, content_type: nil, created_at: nil, origin: :attached,
                   location: nil, restricted: false, available: true, url: nil)
      super
    end

    def image?
      content_type.to_s.start_with?("image/") || name.to_s.match?(/\.(png|jpe?g|gif|webp|svg|bmp)\z/i)
    end
  end
end
