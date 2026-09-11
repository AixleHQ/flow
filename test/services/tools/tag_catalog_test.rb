# frozen_string_literal: true

require "test_helper"

class Tools::TagCatalogTest < ActiveSupport::TestCase
  test "the picker-facing tags are visible with their labels" do
    { board: "Board management", slack: "Slack", coder: "Coder",
      assets: "Assets", session_supervision: "Session supervision" }.each do |tag, label|
      assert Tools::TagCatalog.ui_visible?(tag), "#{tag} must be offered in the picker"
      assert_equal label, Tools::TagCatalog.label(tag)
    end
  end

  test "service tags and the messaging umbrella stay out of the picker" do
    # :messaging would double up on the Slack tools, which carry both tags.
    %i[messaging workflow_control async_results session_lifecycle repositories builder].each do |tag|
      assert_not Tools::TagCatalog.ui_visible?(tag), "#{tag} must stay out of the picker"
    end
  end

  test "unknown tags default to hidden with a humanized label" do
    assert_not Tools::TagCatalog.ui_visible?(:nope)
    assert_equal "Nope", Tools::TagCatalog.label(:nope)
  end

  test "ui_entries lists only visible tags, in picker order" do
    assert_equal %i[board slack coder assets session_supervision], Tools::TagCatalog.ui_entries.map(&:tag)
  end
end
