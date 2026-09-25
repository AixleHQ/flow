# frozen_string_literal: true

require "test_helper"

class StoredFileSourcesTest < ActiveSupport::TestCase
  test "outside development and test a stored file loads from the bucket's own host" do
    hosts = StoredFileSources.hosts(env: ActiveSupport::EnvironmentInquirer.new("production"),
                                    bucket: "files-prod", region: "eu-west-1")

    assert_equal [ "https://files-prod.s3.amazonaws.com", "https://files-prod.s3.eu-west-1.amazonaws.com" ], hosts
  end

  test "in development and test stored files come from this origin" do
    %w[development test].each do |env|
      assert_empty StoredFileSources.hosts(env: ActiveSupport::EnvironmentInquirer.new(env), bucket: "files", region: "eu-west-1")
    end
  end
end
