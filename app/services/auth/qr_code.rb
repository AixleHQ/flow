# frozen_string_literal: true

module Auth
  # Renders a string as a scannable QR image (CAP-4).
  #
  # Returned as a data: URI holding SVG, so the page shows it with a plain `img`
  # tag: no QR library in the bundle, and no server-built markup injected into
  # the document. The payload is an otpauth:// URI carrying the TOTP secret, so
  # it is as sensitive as the secret itself and belongs only in a response that
  # already carries it.
  class QrCode
    # Level M tolerates ~15% damage. Higher correction makes a denser image for
    # no benefit here — the code is displayed on screen, not printed.
    ERROR_CORRECTION = :m

    MODULE_SIZE = 4

    # A QR is read as dark-on-light, and a scanner needs the light. Left
    # transparent the code inherits whatever is behind it — on a dark theme that
    # is dark-on-dark and unscannable — so the image carries its own white
    # ground. `offset` is the quiet zone the format requires: four modules of
    # clear margin, without which readers miss the finder patterns.
    #
    # Without a viewBox the SVG carries fixed pixel dimensions and ignores the
    # size the page gives it.
    SVG_OPTIONS = {
      module_size: MODULE_SIZE,
      offset: MODULE_SIZE * 4,
      color: "000000",
      fill: "ffffff",
      use_path: true,
      viewbox: true,
      standalone: true
    }.freeze

    def self.data_uri(text)
      return nil if text.blank?

      svg = RQRCode::QRCode.new(text, level: ERROR_CORRECTION).as_svg(**SVG_OPTIONS)
      "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}"
    end
  end
end
