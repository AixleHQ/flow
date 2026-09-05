# frozen_string_literal: true

class SessionAdmissionPool < ApplicationRecord
  has_many :session_admissions
end
