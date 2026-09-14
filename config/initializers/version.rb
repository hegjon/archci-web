# The front end's own version for the footer: the tag or commit it was
# deployed from (ARCHCI_WEB_VERSION), else what git says of the checkout.
Rails.application.config.x.version = ENV["ARCHCI_WEB_VERSION"].presence ||
  `git -C #{Rails.root.to_s.shellescape} describe --tags --always 2>/dev/null`.strip.presence || "dev"
