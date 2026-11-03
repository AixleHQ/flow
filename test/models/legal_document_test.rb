# frozen_string_literal: true

require "test_helper"

class LegalDocumentTest < ActiveSupport::TestCase
  # The version each document is published at, and the SHA-256 of the text
  # published with it. Editing a document's view fails this test until somebody
  # decides what the edit is (see the failure message), so a new text cannot
  # ship under the version people already accepted.
  PUBLISHED = {
    "terms_of_service" => [ "2026-10-31", "76f9ff59850acf13533c89412f30b9df2244b3fc9c8cd669d08094bf2305b0db" ],
    "terms_of_use" => [ "2026-10-30", "7635db8e9ae15d316a82b0b42d2fe618cdf464906c789f8f8c5eea1d715b26e8" ],
    "privacy_policy" => [ "2026-11-03", "98b9af7dd217b81cded86a2f7ff98a1c05d03616722ecbcf80a9c02373b0f797" ]
  }.freeze

  test "every document's text is published under the version recorded for it" do
    assert_equal PUBLISHED.keys.sort, LegalDocument::ALL.map(&:key).sort

    LegalDocument::ALL.each do |document|
      view = "app/views/web/legal/#{document.key}.html.erb"
      digest = Digest::SHA256.file(Rails.root.join(view)).hexdigest

      assert_equal PUBLISHED[document.key], [ document.version, digest ], <<~MESSAGE
        The #{document.title} (#{view}) is not the text recorded for its version.
        If the change is to what the document says, set its version in LegalDocument::ALL
        to the date it is published: everyone who accepts it is asked to accept again.
        If it is not (a typo, markup), keep the version.
        Either way, record the version and the new digest in #{self.class.name}::PUBLISHED:
          #{document.key}: #{digest}
      MESSAGE
    end
  end
end
