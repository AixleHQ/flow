# frozen_string_literal: true

if Rails.env.local?
  Rails.application.config.session_store(:cookie_store, key: "_aixle_session", same_site: :lax, secure: false)
else
  Rails.application.config.session_store(:cookie_store, key: "_aixle_session", same_site: :none, secure: true)
end
