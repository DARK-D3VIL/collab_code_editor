# Pin npm packages by running ./bin/importmap
pin "application"
pin "@rails/actioncable", to: "@rails--actioncable.js" # @8.0.200
pin_all_from "app/javascript/channels", under: "channels"
pin "@rails/ujs", to: "@rails--ujs.js" # @7.1.3
