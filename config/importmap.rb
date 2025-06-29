# Pin npm packages by running ./bin/importmap
pin "application", preload: true
pin "@rails/actioncable", to: "@rails--actioncable.js" # @8.0.200
pin_all_from "app/javascript/channels", under: "channels"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "@rails/ujs", to: "@rails--ujs.js" # @7.1.3
pin "bootstrap" # @5.3.6
pin "@popperjs/core", to: "@popperjs--core.js" # @2.11.8
