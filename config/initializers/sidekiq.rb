# config/initializers/sidekiq.rb
require "sidekiq"
require "sidekiq/web" # This is included in the main sidekiq gem

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1") }

  # Configure recurring jobs if using sidekiq-cron
  if defined?(Sidekiq::Cron::Job)
    # Clean up expired email verifications every hour
    Sidekiq::Cron::Job.load_from_hash({
      "EmailVerificationCleanup" => {
        "cron" => "0 * * * *", # Every hour
        "class" => "EmailVerificationCleanupJob"
      }
    })
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1") }
end

# Configure Sidekiq Web UI authentication
Sidekiq::Web.use(Rack::Auth::Basic) do |user, password|
  # In production, use environment variables
  [ user, password ] == [ ENV["SIDEKIQ_USERNAME"] || "admin", ENV["SIDEKIQ_PASSWORD"] || "password" ]
end
