# frozen_string_literal: true

# SitePrism page object for the operator sign-in screen (Auth/AdminLoginPage),
# which leads to the Administrate back office at /admin.
class AdminLoginPage < SitePrism::Page
  set_url "/admin/login"

  element :email_field, :fillable_field, "Email"
  element :password_field, :fillable_field, "Password"
  element :submit_button, :button, "Sign in"

  def sign_in(email, password)
    email_field.set(email)
    password_field.set(password)
    submit_button.click
  end
end
