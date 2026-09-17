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
  #
  # Saving is a second, asynchronous round trip — one POST to the create endpoint per file — and
  # it is that POST, not the upload above, which creates the Asset rows. The modal closes only
  # once at least one of them has come back created, so waiting it out here is what makes `upload`
  # return with the assets persisted. Without that wait the modal is still on screen listing the
  # names it is about to save, and those names are what a caller asserting on the file name would
  # match — passing while the rows it then looks up do not exist yet.
  def upload(path, folder: nil)
    open_upload_modal
    file_input.attach_file(path)
    has_save_button?(wait: 15)
    folder_field.set(folder) if folder
    save_button.click
    return if has_no_save_button?(wait: 15)

    raise Capybara::ExpectationNotMet, "the upload modal never closed: nothing was saved"
  end

  # The default Assets view is folder-first (#564): a file uploaded into a folder sits inside
  # it, not at the root the table starts on, so a test asserting on that file has to navigate in.
  def open_folder(name)
    find("p", text: name, exact_text: true, wait: 15).click
  end
end
