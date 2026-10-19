# frozen_string_literal: true

require "test_helper"

# The admin renders no MantineProvider to inject the --app-* tokens, so its skin
# (app/frontend/entrypoints/admin.css) declares the light-scheme ones itself.
# Each must be the theme's own value, or the admin drifts into a second palette.
class AdminSkinTokensTest < ActiveSupport::TestCase
  THEME = Rails.root.join("app/frontend/shared/theme/mantineTheme.ts").read
  SKIN = Rails.root.join("app/frontend/entrypoints/admin.css").read

  def theme_tokens
    variables = THEME[/^  variables: \{(.*?)^  \},/m, 1]
    light = THEME[/^  light: \{(.*?)^  \},/m, 1]
    "#{variables}#{light}".scan(/'(--app-[a-z0-9-]+)': '([^']+)'/).to_h
  end

  def skin_tokens
    SKIN.scan(/^\s*(--app-[a-z0-9-]+):\s*([^;]+);/).to_h
  end

  def normalize(value) = value.strip.tr('"', "'")

  # The dashboard island on the admin home draws on the same declarations.
  test "the skin declares every token the admin uses" do
    dashboard = Rails.root.join("app/frontend/pages/Admin/Dashboard/Dashboard.module.css").read
    used = "#{SKIN}#{dashboard}".scan(/var\((--app-[a-z0-9-]+)\)/).flatten.uniq

    assert_empty used - skin_tokens.keys
  end

  test "every token the skin declares is the light scheme's value" do
    theme = theme_tokens

    assert_operator skin_tokens.size, :>, 10
    skin_tokens.each do |name, value|
      assert theme.key?(name), "#{name} is not a theme token"
      assert_equal normalize(theme[name]), normalize(value), name
    end
  end
end
