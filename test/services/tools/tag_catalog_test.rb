# frozen_string_literal: true

require "test_helper"

class Tools::TagCatalogTest < ActiveSupport::TestCase
  test "board is a visible group; service and provider tags are hidden" do
    assert Tools::TagCatalog.ui_visible?(:board)
    assert Tools::TagCatalog.group?(:board)
    assert_equal "Board management", Tools::TagCatalog.label(:board)

    %i[workflow_control async_results session_lifecycle builder slack coder].each do |tag|
      assert_not Tools::TagCatalog.ui_visible?(tag), "#{tag} must stay out of the picker"
    end
  end

  test "messaging is visible but individual, not a group" do
    assert Tools::TagCatalog.ui_visible?(:messaging)
    assert_not Tools::TagCatalog.group?(:messaging)
  end

  test "unknown tags default to hidden with a humanized label" do
    assert_not Tools::TagCatalog.ui_visible?(:nope)
    assert_equal "Nope", Tools::TagCatalog.label(:nope)
  end

  test "ui_entries lists only visible tags" do
    assert_equal %i[board messaging], Tools::TagCatalog.ui_entries.map(&:tag)
  end
end
