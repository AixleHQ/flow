# frozen_string_literal: true

require "test_helper"

# The fonts are served from public/fonts/v1/ (#353): nothing may point back at
# Google, and every file the stylesheet and the preload name must exist.
class SelfHostedFontFilesTest < ActiveSupport::TestCase
  FONTS_DIR = Rails.public_path.join("fonts/v1")
  STATIC_PAGES = %w[400.html 406-unsupported-browser.html 422.html 500.html].freeze

  test "no view, frontend file or static page loads a font from Google" do
    files = Dir[Rails.root.join("{app/views,app/frontend}/**/*").to_s] + Dir[Rails.public_path.join("*.html").to_s]
    offenders = files.select { |path| File.file?(path) && File.read(path).match?(/fonts\.(googleapis|gstatic)\.com/) }

    assert_empty offenders.map { |path| Pathname(path).relative_path_from(Rails.root).to_s }
  end

  test "every font the stylesheet and the preload name is a file that exists" do
    urls = FONTS_DIR.join("fonts.css").read.scan(/url\(\.\/([^)]+)\)/).flatten
    preload = Rails.root.join("app/views/shared/_web_fonts.html.erb").read[%r{rel="preload" href="/fonts/v1/([^"]+)"}, 1]

    assert_equal 15, urls.size
    assert preload, "the partial preloads no font"
    (urls + [ preload ]).each { |file| assert FONTS_DIR.join(file).file?, "public/fonts/v1/#{file} is missing" }
  end

  test "the stylesheet keeps the family names the frontend theme uses and the Inter fallback" do
    families = FONTS_DIR.join("fonts.css").read.scan(/font-family:"([^"]+)"/).flatten.uniq

    assert_equal [ "Inter Fallback", "Inter", "JetBrains Mono", "Spline Sans Mono" ], families
  end

  test "each static error page links the self-hosted stylesheet" do
    STATIC_PAGES.each do |page|
      assert_includes Rails.public_path.join(page).read, %(<link rel="stylesheet" href="/fonts/v1/fonts.css">), page
    end
  end
end
