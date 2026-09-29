# frozen_string_literal: true

# One passkey belonging to a user (AD-18).
#
# The credential lives on the person's own device and works across every company
# they belong to, so it is theirs: only they register, rename and delete it. A
# company may stop ACCEPTING passkeys for entry, which never touches this row.
class WebauthnCredential < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :public_key, presence: true

  def touch_used!(new_sign_count)
    update!(last_used_at: Time.current, sign_count: new_sign_count)
  end

  def display_name
    nickname.presence || "Passkey added #{created_at.to_date.to_fs(:long)}"
  end
end
