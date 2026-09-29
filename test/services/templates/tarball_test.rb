# frozen_string_literal: true

require "test_helper"

class Templates::TarballTest < ActiveSupport::TestCase
  test "strips the top-level directory and keeps regular files only" do
    archive = FakeTemplatesRepository.gzip_tar(
      "flow-templates-abc/templates/x/template.yaml" => "slug: x",
      "flow-templates-abc/templates/x/link" => { symlink: "/etc/passwd" },
      "flow-templates-abc/../escape.txt" => "nope"
    )

    assert_equal({ "templates/x/template.yaml" => "slug: x" }, Templates::Tarball.extract(archive))
  end

  test "drops a file above the per-file cap" do
    archive = FakeTemplatesRepository.gzip_tar("root/big.bin" => "a" * (Templates::Tarball::MAX_FILE_BYTES + 1),
                                               "root/small.txt" => "ok")

    assert_equal [ "small.txt" ], Templates::Tarball.extract(archive).keys
  end
end
