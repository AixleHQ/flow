# frozen_string_literal: true

require "test_helper"

# A hand-run image build bakes a short commit SHA as AGENT_IMAGE_TAG, and YAML loads an
# unquoted scalar of a leading zero and octal digits (`0123456`) as an Integer: sessions
# would launch `…:42798`.
class AgentImageTagSettingTest < ActiveSupport::TestCase
  FILES = %w[config/settings.yml config/settings/production.yml config/settings/staging.yml].freeze

  test "every environment reads AGENT_IMAGE_TAG as the string it was given" do
    FILES.each do |file|
      assert_equal "0123456", image_tag_from(file, "0123456"), file
      assert_equal "1.0.0", image_tag_from(file, "1.0.0"), file
    end
  end

  private

  def image_tag_from(file, value)
    saved = ENV.fetch("AGENT_IMAGE_TAG", nil)
    ENV["AGENT_IMAGE_TAG"] = value
    YAML.safe_load(ERB.new(Rails.root.join(file).read).result, aliases: true).dig("agents", "image_tag")
  ensure
    saved.nil? ? ENV.delete("AGENT_IMAGE_TAG") : ENV["AGENT_IMAGE_TAG"] = saved
  end
end
