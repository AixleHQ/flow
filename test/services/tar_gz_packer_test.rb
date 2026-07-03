# frozen_string_literal: true

require "test_helper"
require "rubygems/package"
require "zlib"

class TarGzPackerTest < ActiveSupport::TestCase
  test "pack produces valid tar.gz with given files" do
    files = {
      "report.json" => '{"issues": 5}',
      "readme.txt" => "Hello World"
    }

    archive = TarGzPacker.pack(files)
    assert archive.is_a?(String)
    assert archive.bytesize > 0

    extracted = {}
    io = StringIO.new(archive)
    Zlib::GzipReader.wrap(io) do |gz|
      Gem::Package::TarReader.new(gz) do |tar|
        tar.each do |entry|
          extracted[entry.full_name] = entry.read
        end
      end
    end

    assert_equal '{"issues": 5}', extracted["report.json"]
    assert_equal "Hello World", extracted["readme.txt"]
  end

  test "pack with empty files hash produces valid empty archive" do
    archive = TarGzPacker.pack({})
    assert archive.is_a?(String)
    assert archive.bytesize > 0
  end
end
