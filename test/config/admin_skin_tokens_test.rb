# frozen_string_literal: true

require "test_helper"

# The admin renders no MantineProvider to inject the --app-* tokens, so its skin
# (app/frontend/entrypoints/admin.css) declares them itself, for the light scheme
# and the dark. Each must be the theme's own value, or the admin drifts into a
# second palette.
class AdminSkinTokensTest < ActiveSupport::TestCase
  THEME = Rails.root.join("app/frontend/shared/theme/mantineTheme.ts").read
  SKIN = Rails.root.join("app/frontend/entrypoints/admin.css").read

  DARK = "[data-mantine-color-scheme='dark']"

  def theme_tokens(scheme)
    constants = THEME.scan(/^const ([A-Z_]+) = '([^']+)';$/).to_h
    variables = THEME[/^  variables: \{(.*?)^  \},/m, 1]
    colors = THEME[/^  #{scheme}: \{(.*?)^  \},/m, 1]
    "#{variables}#{colors}".scan(/'(--app-[a-z0-9-]+)': (?:'([^']+)'|([A-Z_]+))/)
                           .to_h { |name, literal, constant| [ name, literal || constants.fetch(constant) ] }
  end

  def skin_tokens(scheme)
    block = scheme == "dark" ? SKIN[/^:root#{Regexp.escape(DARK)} \{(.*?)^\}/m, 1] : SKIN[/^:root \{(.*?)^\}/m, 1]
    block.scan(/^\s*(--app-[a-z0-9-]+):\s*([^;]+);/).to_h
  end

  def normalize(value) = value.strip.tr('"', "'")

  # The dashboard island on the admin home and the admin's own views draw on the
  # same declarations.
  test "the skin declares every token the admin uses, in both schemes" do
    dashboard = Rails.root.join("app/frontend/pages/Admin/Dashboard/Dashboard.module.css").read
    views = Rails.root.glob("app/views/{admin,administrate,fields}/**/*.erb").map(&:read).join
    used = "#{SKIN}#{dashboard}#{views}".scan(/var\((--app-[a-z0-9-]+)\)/).flatten.uniq

    assert_empty used - skin_tokens("light").keys
    assert_empty used - skin_tokens("dark").keys - %w[--app-font-body --app-font-heading --app-font-mono-label],
                 "the dark scheme repeats every color the light one declares"
  end

  %w[light dark].each do |scheme|
    test "every #{scheme} token the skin declares is the theme's value" do
      theme = theme_tokens(scheme)

      assert_operator skin_tokens(scheme).size, :>, 10
      skin_tokens(scheme).each do |name, value|
        assert theme.key?(name), "#{name} is not a #{scheme} theme token"
        assert_equal normalize(theme[name]), normalize(value), "#{scheme} #{name}"
      end
    end
  end
end
