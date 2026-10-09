# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Deny powerful browser features the app never uses, so a compromised page cannot
# reach for them.
#
# We set the modern `Permissions-Policy` header directly rather than through
# `config.permissions_policy`, whose middleware still emits the superseded
# `Feature-Policy` header (with the old `camera 'none'` syntax) that current
# browsers ignore.
#
# Only features with no in-app caller are denied: the frontend uses the Clipboard
# API (terminal/docs/task copy) and Fullscreen (the IDE frame), so those are left
# at the browser default rather than listed here.
Rails.application.config.action_dispatch.default_headers.merge!(
  "Permissions-Policy" => "camera=(), microphone=(), geolocation=()"
)
