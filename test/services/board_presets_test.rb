# frozen_string_literal: true

require "test_helper"

class BoardPresetsTest < ActiveSupport::TestCase
  test ".all returns three presets" do
    presets = BoardPresets.all
    assert_equal 3, presets.size
    keys = presets.map { |p| p[:key] }
    assert_includes keys, :simple_kanban
    assert_includes keys, :dev_team
    assert_includes keys, :full_sdlc
  end

  test ".find returns preset by key" do
    preset = BoardPresets.find(:dev_team)
    assert_equal "Dev Team", preset[:display_name]
    assert_equal 5, preset[:columns].size
  end

  test ".find returns nil for unknown key" do
    assert_nil BoardPresets.find(:nonexistent)
  end

  test ".find works with string keys" do
    preset = BoardPresets.find("simple_kanban")
    assert_equal "Simple Kanban", preset[:display_name]
  end

  test ".valid? returns true for known key" do
    assert BoardPresets.valid?(:full_sdlc)
    assert BoardPresets.valid?("dev_team")
  end

  test ".valid? returns false for unknown key" do
    refute BoardPresets.valid?(:nonexistent)
  end

  test "each preset has columns with name, position, and purpose" do
    BoardPresets::PRESETS.each do |key, preset|
      preset[:columns].each do |col|
        assert col[:name].present?, "Column in #{key} missing name"
        assert col[:position].present?, "Column in #{key} missing position"
        assert col[:purpose].present?, "Column in #{key} missing purpose"
      end
    end
  end

  test "simple_kanban has 3 columns" do
    preset = BoardPresets.find(:simple_kanban)
    assert_equal 3, preset[:columns].size
  end

  test "dev_team has 5 columns" do
    preset = BoardPresets.find(:dev_team)
    assert_equal 5, preset[:columns].size
  end

  test "full_sdlc has 7 columns" do
    preset = BoardPresets.find(:full_sdlc)
    assert_equal 7, preset[:columns].size
  end
end
