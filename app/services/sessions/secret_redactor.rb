# frozen_string_literal: true

require "strscan"

module Sessions
  # Masks known secret values before a log is stored or served.
  #
  # A value handed to an agent through `get_config_item` necessarily enters the
  # model's context, and from there the provider request body — which the MITM
  # logger captures in full (`docker/base/logger/mitm_logger.py`). It also lands
  # in `/tmp/terminal_output.log` the moment the agent echoes it. "In context but
  # not in logs" is therefore only achievable as value-level redaction at each
  # sink, never as "do not log this tool".
  #
  # The set is KNOWN and enumerable — the `secret` config items attached to the
  # session — so this is not a heuristic scan for secret-looking text.
  #
  # The matching is the container's (docker/base/logger/aixle_redact.py), because
  # it has to find the same things: a terminal draws a value between colour codes
  # and wraps it onto the next row behind an indent, so a text is projected onto its
  # significant characters (escape sequences, whitespace, control and box-drawing
  # characters dropped) and searched there; a secret of FRAGMENT_FLOOR characters or
  # more is also masked in every FRAGMENT-character piece that mixes letter cases or
  # letters and digits, which catches one split by a partial repaint or cut by a size
  # limit without masking every `https://` in a log whose secret is a URL.
  #
  # WHAT THIS DOES NOT COVER: the live terminal (ttyd attaches to tmux, not to any
  # log), a value the agent transforms before printing it, and — for logs read back
  # later — a secret whose value has since been rotated, since only current values
  # are known. See docs/implementation-artifacts/spec-session-config-item-access.md.
  class SecretRedactor
    FRAGMENT = 8
    FRAGMENT_FLOOR = 16
    MASK = "*"

    # One escape sequence. An OSC/DCS/APC counts only with its terminator and within
    # MAX_ESCAPE characters: matched lazily up to the end of the text instead, one stray
    # `\e]` hid everything after it from the masking.
    MAX_ESCAPE = 4096
    ESCAPE = /\e(?:\[[\x20-\x3f]*[\x40-\x7e]?|[\]PX^_](?:[^\a\e]|\e(?!\\)){0,#{MAX_ESCAPE}}(?:\a|\e\\)|[()*+\-.\/#%].?|.?)/
    IGNORABLE = /[[:space:]\p{Cc}\u2500-\u259f&&[^\e]]+/
    NOISE = Regexp.union(ESCAPE, IGNORABLE)
    SIGNIFICANT = /[^[:space:]\p{Cc}\u2500-\u259f]+/
    WIDE = /[\u1100-\u115f\u2e80-\ua4cf\uac00-\ud7a3\uf900-\ufaff\ufe30-\ufe4f\uff00-\uff60\uffe0-\uffe6]/
    # How many of a secret's pieces #candidate? checks; see there.
    PROBES_PER_SECRET = 64

    # No length floor. ContextLog::MIN_REDACT_LEN exists because that path
    # registers every MCP header/env value, including non-secrets like "json"
    # and "true", whose masking would only obscure the log. Here every value is
    # a config item somebody marked `secret` — a four-character one is still a
    # secret, and a floor would silently exempt it.
    def self.for_session(session)
      new(secret_values_for(session))
    end

    def self.secret_values_for(session)
      return [] if session.nil?

      ids = SessionConfigResolver.new(session).resolve_config_item_ids
      return [] if ids.blank?

      # One unreadable item is not a reason to redact nothing: it cannot have been
      # handed out either, so it is simply not on the list.
      ConfigItem.where(id: ids).with_item_type(:secret).filter_map do |item|
        item.decrypted_value
      rescue Encryptable::DecryptionError
        nil
      end
    rescue StandardError => e
      # A redactor that raises would take the whole log-collection step with it
      # and lose the log entirely. Failing closed here means "no redaction", so
      # say so loudly rather than silently storing raw bytes.
      Rails.logger.error("[SecretRedactor] Failed to resolve session secrets: #{e.message}")
      []
    end

    def initialize(values)
      @secrets = Array(values).map { |v| utf8(v.to_s) }.reject(&:blank?).uniq
      @needles, @probes = build_needles
    end

    def any?
      @needles.any?
    end

    # `text` with each run of secret characters replaced by a fingerprint. Returned
    # unchanged — byte for byte, invalid UTF-8 included — when there is nothing to redact.
    def call(text)
      return text if text.blank? || @needles.empty?

      str = utf8(text.to_s)
      return text unless candidate?(str)

      _sig, at, owners = scan(str)
      return text if owners.compact.empty?

      rebuild(str) do |out, emit|
        runs(owners).each do |first, last|
          emit.call(at[first], at[last] + char_size(str, at[last]))
          out << fingerprint(@secrets[owners[first]])
        end
      end
    end

    # A terminal stream with every secret character replaced in place by MASK. The
    # CLIs paint with absolute cursor moves, so a replacement of any other width
    # would shift everything painted after it on the row.
    def terminal(text)
      return text if text.blank? || @needles.empty?

      str = utf8(text.to_s)
      return text unless candidate?(str)

      _sig, at, owners = scan(str)
      return text if owners.compact.empty?

      rebuild(str) do |out, emit|
        owners.each_with_index do |owner, k|
          next unless owner

          size = char_size(str, at[k])
          emit.call(at[k], at[k] + size)
          out << (str.byteslice(at[k], size).match?(WIDE) ? MASK * 2 : MASK)
        end
      end
    end

    private

    # [needles, probes]. Needles are [needle, index of the secret it belongs to], longest
    # first: each secret whole and every piece of it. A JSON-escaped form is looked for too:
    # a CLI's transcript stores a value carrying a quote or a backslash only in that form.
    def build_needles
      needles = []
      probes = []
      @secrets.each_with_index do |secret, owner|
        [ secret, secret.to_json[1..-2] ].uniq.each do |form|
          sig = form.scan(SIGNIFICANT).join
          next if sig.empty?

          pieces = fragments(sig)
          needles << [ sig, owner ]
          needles.concat(pieces.map { |piece| [ piece, owner ] })
          probes << sig
          probes.concat(pieces.each_slice((pieces.size / PROBES_PER_SECRET.to_f).ceil.clamp(1..)).map(&:first))
        end
      end
      [ needles.uniq.sort_by { |needle, _| -needle.length }, probes.uniq ]
    end

    # Whether `str` can hold anything to mask, decided without building the projection's
    # index: the common case — nothing to mask — then costs one gsub. A long secret (a PEM
    # key, a service-account JSON) has hundreds of pieces, so only an evenly spread sample
    # of them is checked here; a piece that falls between two samples is found only when it
    # is longer than the gap.
    def candidate?(str)
      sig = str.gsub(NOISE, "")
      @probes.any? { |probe| sig.include?(probe) }
    end

    # A short secret is only masked whole — and without the punctuation at its ends, when
    # enough is left: a password like `Summer2024!` reaches a log with its `!` escaped as
    # often as not, and eleven of its twelve characters are the secret all the same.
    def fragments(sig)
      chars = sig.chars
      if chars.size < FRAGMENT_FLOOR
        core = sig.gsub(/\A[\W_]+|[\W_]+\z/, "")
        return core != sig && core.length >= FRAGMENT ? [ core ] : []
      end

      (0..(chars.size - FRAGMENT)).map { |i| chars[i, FRAGMENT].join }.select do |piece|
        [ /\p{Ll}/, /\p{Lu}/, /\p{Nd}/ ].count { |kind| piece.match?(kind) } >= 2
      end
    end

    # The projection: significant characters, the byte offset in `str` of each,
    # and which secret (if any) covers it.
    def scan(str)
      sig = +""
      at = []
      sig_at = []
      ss = StringScanner.new(str)
      until ss.eos?
        next if ss.skip(ESCAPE) || ss.skip(IGNORABLE)

        start = ss.pos
        run = ss.scan(SIGNIFICANT)
        unless run
          ss.getch
          next
        end
        if run.ascii_only?
          at.concat((start...(start + run.bytesize)).to_a)
          sig_at.concat((sig.bytesize...(sig.bytesize + run.bytesize)).to_a)
        else
          offset = sig.bytesize
          run.each_char do |ch|
            at << start
            sig_at << offset
            start += ch.bytesize
            offset += ch.bytesize
          end
        end
        sig << run
      end
      [ sig, at, cover(sig, sig_at) ]
    end

    def cover(sig, sig_at)
      owners = Array.new(sig_at.size)
      @needles.each do |needle, owner|
        size = needle.length
        found = sig.byteindex(needle)
        while found
          first = sig_at.bsearch_index { |offset| offset >= found }
          (first...(first + size)).each { |k| owners[k] ||= owner }
          found = sig.byteindex(needle, found + char_size(sig, found))
        end
      end
      owners
    end

    # One forward pass: the block names each byte range to drop (in order) and appends
    # its replacement; everything between ranges is copied as it was.
    def rebuild(str)
      out = String.new(capacity: str.bytesize, encoding: Encoding::UTF_8)
      copied = 0
      emit = lambda do |from, to|
        out << str.byteslice(copied, from - copied)
        copied = to
      end
      yield out, emit
      out << str.byteslice(copied, str.bytesize - copied)
    end

    # [first, last] index pairs of consecutive covered characters.
    def runs(owners)
      result = []
      owners.each_with_index do |owner, k|
        next unless owner

        if result.any? && result.last[1] == k - 1
          result.last[1] = k
        else
          result << [ k, k ]
        end
      end
      result
    end

    def char_size(str, offset)
      byte = str.getbyte(offset)
      return 1 if byte.nil? || byte < 0xC0
      return 2 if byte < 0xE0
      return 3 if byte < 0xF0

      4
    end

    def utf8(str)
      str = str.dup.force_encoding(Encoding::UTF_8)
      str.valid_encoding? ? str : str.scrub
    end

    # Same shape ContextLog has used since the OAuth work, so one grep finds
    # every redaction in a collected artifact regardless of which sink wrote it.
    def fingerprint(value)
      "«redacted:sha256:#{Digest::SHA256.hexdigest(value)[0, 8]}»"
    end
  end
end
