# frozen_string_literal: true

# SitePrism page object for the company Assets index (Company/Assets/Index) and its
# "Upload Assets" modal, both rendered by shared/resources/assets/AssetsContent.
class CompanyAssetsPage < SitePrism::Page
  set_url "/company/assets"

  # The index shows a header "Upload" button and, when empty, an "Upload your first file"
  # CTA — both open the same modal.
  element :header_upload_button, :button, text: "Upload", exact_text: true
  element :empty_state_upload_button, :button, text: "Upload your first file", exact_text: true

  # Upload modal. The file input is display:none — the dropzone above it is what a user
  # clicks — so it has to be attached to directly.
  element :file_input, "input[type='file']", visible: false
  element :folder_field, :fillable_field, "Folder (optional)"
  element :save_button, :button, text: /\ASave \d+ file/

  def open_upload_modal
    button = has_empty_state_upload_button?(wait: 1) ? empty_state_upload_button : header_upload_button
    button.scroll_to(button)
    button.click
    has_file_input?(wait: 5)
  end

  # Drives the real upload: Uppy presigns through /api/v1/assets/presign and PUTs the bytes,
  # and the modal only offers a Save button once that round trip has completed.
  def upload(path, folder: nil)
    open_upload_modal
    file_input.attach_file(path)
    has_save_button?(wait: 15)
    folder_field.set(folder) if folder
    save_button.click
  end
end
