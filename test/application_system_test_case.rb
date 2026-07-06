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

# CI runners (2-4 vCPU, CPU-throttled) parse+execute the ~720KB app bundle and mount React
# far slower than bare metal — the FIRST page's mount routinely takes several seconds, past
# Capybara's 2s default element wait, so the first `find`/`set` flakes "Unable to find field".
# Give slow runners generous headroom (same signal vitest.config.ts uses: CI or inside Docker —
# and system tests ALWAYS run in the container). The wait is only an upper bound: a fast mount
# returns immediately, so this never slows a passing test — it only stops the cold-start flake.
Capybara.default_max_wait_time =
  ENV.fetch("CAPYBARA_MAX_WAIT") { ENV["CI"] || File.exist?("/.dockerenv") ? 20 : 2 }.to_f

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite_alpine

  # TEMP CI diagnostic: on a failing system test, dump enough to see WHY the SPA didn't render
  # on the runner (empty #app vs 404'd JS vs console error). Runs BEFORE super (Rails resets the
  # Capybara session in after_teardown, so the browser must be inspected first). Silent on green.
  # Remove once the CI system-test flake is understood.
  def after_teardown
    dump_system_diag unless passed?
    super
  end

  def dump_system_diag
    puts "\n===== SYSDIAG #{name} ====="
    html = page.html.to_s
    puts "URL: #{current_url}"
    puts "HTML_LEN: #{html.length}  APP_EMPTY: #{html.include?('<div id="app"></div>')}"
    puts "HAS_EMAIL_LABEL: #{html.include?(">Email<")}  HAS_INPUT: #{html.include?("<input")}"
    traffic = begin
      page.driver.browser.network.traffic
    rescue StandardError
      []
    end
    vite = traffic.select { |e| (e.request&.url).to_s.include?("/vite-") }
    puts "VITE_REQUESTS(#{vite.size}):"
    vite.first(20).each { |e| puts "  #{(e.response&.status) || 'PENDING'} #{e.request&.url}" }
    console = begin
      Array(page.driver.browser.options.logger&.instance_variable_get(:@messages))
    rescue StandardError
      []
    end
    fails = traffic.select { |e| s = e.response&.status; s.nil? || s.to_i >= 400 }
    puts "NET_FAILURES(#{fails.size}):"
    fails.first(20).each { |e| puts "  #{(e.response&.status) || 'nil'} #{e.request&.url}" }
    puts "CONSOLE(#{console.size}): #{console.first(10).join(' | ')}" unless console.empty?
  rescue StandardError => e
    puts "SYSDIAG_ERR: #{e.class} #{e.message}"
  ensure
    puts "===== END SYSDIAG ====="
  end
end
