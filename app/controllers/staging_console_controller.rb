# frozen_string_literal: true

# Opens a web-console session for the QA agent that seeds data on staging, for the
# signed-in super admin only. The page itself is empty: the session id comes back
# in the `x-web-console-session-id` header, and code is evaluated by
# `PUT /__web_console/repl_sessions/:id`, which web-console serves in its own
# middleware before the router, so a controller cannot guard it. The id is a random
# 128-bit value that only this action hands out; keeping it secret is the guard.
# Sessions live in one process's memory, so staging has to run a single Puma process.
class StagingConsoleController < ActionController::Base
  include AuthConcern

  # web-console never evicts sessions, so every call would pin a binding in memory
  # until the process restarts.
  MAX_STORED_SESSIONS = 50

  before_action :require_super_admin

  def show
    storage = WebConsole::Session.inmemory_storage
    storage.shift while storage.size >= MAX_STORED_SESSIONS

    console(TOPLEVEL_BINDING.eval("binding"))
    render html: "<!DOCTYPE html><html><body>staging console</body></html>".html_safe
  end

  private

  # An impersonated request has the impersonated user as current_user, so a super admin
  # acting as someone else is refused too.
  def require_super_admin
    head :not_found unless current_user&.super_admin?
  end
end
