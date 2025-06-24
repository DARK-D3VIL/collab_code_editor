// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "./channels"
import 'bootstrap'
import Rails from "@rails/ujs"
import "@hotwired/turbo-rails"
import "./controllers"
import "turbo"
import "stimulus"
import * as ActionCable from "@rails/actioncable"
window.ActionCable = ActionCable
Rails.start()