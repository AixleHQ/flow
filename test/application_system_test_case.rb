require "test_helper"
require "capybara/cuprite"
require "site_prism"

# Load SitePrism page objects.
Dir[File.expand_path("system/pages/**/*.rb", __dir__)].sort.each { |f| require f }

# System (end-to-end) tests drive the real Rails + Inertia + React stack through a
# headless Chromium via Cuprite (Ferrum/CDP — no chromedriver). Page objects live
# in test/system/pages (SitePrism). See docs/testing.md §1 (E2E layer).
#
# Registered under a distinct name (:cuprite_alpine) so this config — not cuprite's
# permissive default :cuprite driver — is the one Rails uses. --no-sandbox is
# mandatory running as root in the container; --disable-dev-shm-usage avoids the
# tiny /dev/shm in Docker; the Alpine chromium binary path is explicit.
Capybara.register_driver(:cuprite_alpine) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1400, 1400 ],
    browser_path: ENV.fetch("CHROMIUM_PATH", "/usr/bin/chromium"),
    browser_options: {
      "no-sandbox" => nil,
      "disable-gpu" => nil,
      "disable-dev-shm-usage" => nil,
      "disable-software-rasterizer" => nil
    },
    process_timeout: 60,
    timeout: 30,
    headless: "new"
  )
end

Capybara.server = :puma, { Silent: true }

# Implicit wait for find/assert_selector/have_* before failing. Default is 2s;
# raised to 5 so the Inertia+React stack has time to hydrate and settle async
# updates on slower/loaded CI without resorting to explicit sleeps.
Capybara.default_max_wait_time = 5

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite_alpine
end
