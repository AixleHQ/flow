# frozen_string_literal: true

# The mailer layout paints a dark background and leaves text colour to each template.
# Text without an inline colour on itself or an ancestor gets the client's default —
# near-black in Gmail — and cannot be read against that background.
module MailerAssertions
  INVISIBLE = /\A[[:space:]‌ ]*\z/

  def assert_every_text_coloured(mail)
    html = Nokogiri::HTML((mail.html_part || mail).decoded)
    uncoloured = html.css("body").xpath(".//text()").filter_map do |node|
      next if node.text.match?(INVISIBLE)

      ancestors = node.ancestors.take_while { |el| el.name != "body" }
      next if ancestors.any? { |el| el["style"].to_s.match?(/display:\s*none/) }
      next if ancestors.any? { |el| el["style"].to_s.match?(/(?:\A|[;\s])color:/) }

      node.text.squish
    end

    assert_empty uncoloured, "text with no explicit colour renders in the client's default colour"
  end
end
