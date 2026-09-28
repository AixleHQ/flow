# frozen_string_literal: true

# Domains where an address proves a mailbox and nothing else.
#
# Signing a workspace up proves control of one address, and a workspace then
# claims the whole domain: every later sign-in from it joins that workspace, and
# nobody else may claim it. That bargain only holds where the address and the
# domain belong to the same organisation. At a public mail service they do not —
# the first person to sign up with a Gmail address would take Gmail, funnel every
# later Gmail visitor into their workspace, and lock the domain away for good.
#
# THIS IS A FLOOR, NOT A FENCE. The list is the common services, not every one
# that exists, and a determined squatter registers a domain rather than looking
# for the provider we missed. What actually settles who owns a domain is proving
# it over DNS; until that exists this keeps the broadest and likeliest case from
# happening by accident.
class PublicEmailDomains
  DOMAINS = %w[
    aol.com
    att.net
    bell.net
    bk.ru
    bluewin.ch
    bol.com.br
    btinternet.com
    charter.net
    comcast.net
    cox.net
    daum.net
    disroot.org
    earthlink.net
    fastmail.com
    free.fr
    freenet.de
    gmail.com
    gmx.com
    gmx.de
    gmx.net
    googlemail.com
    hanmail.net
    hey.com
    hotmail.co.uk
    hotmail.com
    hushmail.com
    icloud.com
    inbox.ru
    interia.pl
    internet.ru
    juno.com
    laposte.net
    libero.it
    list.ru
    live.com
    mac.com
    mail.com
    mail.ru
    mailfence.com
    me.com
    msn.com
    naver.com
    o2.pl
    optonline.net
    orange.fr
    outlook.com
    pm.me
    posteo.de
    proton.me
    protonmail.com
    qq.com
    rambler.ru
    riseup.net
    rogers.com
    runbox.com
    sapo.pt
    sbcglobal.net
    seznam.cz
    shaw.ca
    sky.com
    t-online.de
    telenet.be
    terra.com.br
    tiscali.it
    tuta.io
    tutanota.com
    uol.com.br
    verizon.net
    virgilio.it
    web.de
    wp.pl
    ya.ru
    yahoo.com
    yandex.com
    yandex.ru
    ymail.com
    ziggo.nl
    zoho.com
    zoho.eu
    126.com
    163.com
  ].to_set.freeze

  def self.include?(domain)
    DOMAINS.include?(domain.to_s.strip.downcase)
  end
end
