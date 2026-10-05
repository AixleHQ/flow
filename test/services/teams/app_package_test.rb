# frozen_string_literal: true

require "test_helper"

class Teams::AppPackageTest < ActiveSupport::TestCase
  setup { with_teams_enabled }

  # The local file headers of a zip, inflated: what Teams reads on upload.
  def entries(zip)
    files = {}
    offset = 0
    while zip.byteslice(offset, 4).unpack1("V") == 0x04034b50
      _sig, _version, _flags, method, _time, _date, crc, packed, size, name_length, extra_length =
        zip.byteslice(offset, 30).unpack("VvvvvvVVVvv")
      name = zip.byteslice(offset + 30, name_length)
      data = zip.byteslice(offset + 30 + name_length + extra_length, packed)
      content = method == 8 ? Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(data) : data
      assert_equal [ size, crc ], [ content.bytesize, Zlib.crc32(content) ], name
      files[name] = content
      offset += 30 + name_length + extra_length + packed
    end
    files
  end

  test "the package holds a manifest naming this deployment's bot and both icons" do
    files = entries(Teams::AppPackage.zip)

    assert_equal %w[color.png manifest.json outline.png], files.keys.sort
    assert_equal File.binread(Teams::AppPackage::COLOR_ICON), files["color.png"]
    manifest = JSON.parse(files["manifest.json"])
    assert_equal TEAMS_APP_ID, manifest.dig("bots", 0, "botId")
    assert_equal TEAMS_APP_ID, manifest.dig("webApplicationInfo", "id")
    assert_equal %w[ChannelMessage.Read.Group ChatMessage.Read.Chat],
                 manifest.dig("authorization", "permissions", "resourceSpecific").pluck("name")
  end

  test "the Teams app id follows the bot, so a reinstall updates the same app" do
    first = Teams::AppPackage.manifest_id

    assert_equal first, Teams::AppPackage.manifest_id
    Settings.teams.app_id = "11111111-0000-4000-8000-000000000000"
    assert_not_equal first, Teams::AppPackage.manifest_id
  end
end
