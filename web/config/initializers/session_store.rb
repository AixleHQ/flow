# frozen_string_literal: true

if Rails.env.local?
  Rails.application.config.session_store(:cookie_store, key: "_palad_session", same_site: :lax, secure: false, expire_after: 7.days)
else
  Rails.application.config.session_store(:cookie_store, key: "_palad_session", same_site: :none, secure: true, expire_after: 7.days)
end
