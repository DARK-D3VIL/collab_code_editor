// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
// import { createConsumer } from "@rails/actioncable"
// window.ActionCable = { createConsumer }
import "./channels"
import Rails from "@rails/ujs"
Rails.start()
