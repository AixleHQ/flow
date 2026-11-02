# frozen_string_literal: true

# What a reader could recover of a secret from a log, measured independently of the
# masking under test: the longest run of the secret in the raw text, in the text with
# escape sequences stripped (what get_session_log returns), and in its printable
# characters in order (what a value split by colour codes and a line wrap reads as).
module SecretLeakAssertions
  # Recordings of a real session: Claude Code 2.1.310 in its agent image, driven by a
  # scripted model that put RECORDED_SECRET into a Write, a long curl, a wrapped shell
  # line, a Python file and an Edit diff. The value is fake.
  MASKING_RECORDINGS = Rails.root.join("test/fixtures/files/secret_masking")
  RECORDED_SECRET = "pxk_live_7Hq2ZtR9mWb4Nc8VxL1aPe6Ks3Dy5Fg0Ju"
  # Pieces this short occur by chance; the maskers remove every piece of 8 or more.
  LEAK_LENGTH = 8

  ESCAPES = /\e\[[0-9;?<>=]*[ -\/]*[@-~]|\e\][^\a\e]*(?:\a|\e\\)|\e[()][0-9A-Za-z]|\e[@-Z\\-_]/

  def recording(name)
    File.binread(MASKING_RECORDINGS.join(name))
  end

  def recovered(text, secret = RECORDED_SECRET)
    str = text.to_s.dup.force_encoding(Encoding::UTF_8).scrub
    stripped = str.gsub(ESCAPES, "")
    [ str, stripped, stripped.gsub(/[[:space:][:cntrl:]]+/, "") ].map { |view| longest_piece(view, secret) }.max
  end

  def assert_no_secret(text, secret = RECORDED_SECRET)
    found = recovered(text, secret)
    assert_operator found, :<, LEAK_LENGTH, "#{found} consecutive characters of the secret are recoverable"
  end

  private

  def longest_piece(text, secret)
    best = 0
    secret.length.times do |i|
      best += 1 while i + best < secret.length && text.include?(secret[i, best + 1])
    end
    best
  end
end
