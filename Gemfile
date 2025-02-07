source "https://rubygems.org"

gem "rails", "8.0.1"

gem "apipie-rails", "1.4.2"
gem "bootsnap", "1.18.4", require: false
# gem "datadog", "2.7.0", require: "datadog/auto_instrument"
gem "hirber", "0.8.5"
gem "jbuilder", "2.12.0"
gem "karafka", "2.4.12"
gem "kredis", "1.7.0"
gem "pg", "1.5.8"
gem "puma", "6.4.2"
gem "thruster", "~> 0.1.10"

gem "concurrent-ruby", "~> 1.2"  # For concurrent operations
gem "connection_pool", "~> 2.4"  # For connection pooling
gem "google-cloud-storage", "~> 1.44"  # For Firebase service account
gem "jwt", "~> 2.7"  # For Firebase authentication
gem "houston", "~> 2.4.0"  # For Apple Push Notifications
gem "http", "~> 5.1"  # For HTTP requests


# For stress testing
group :development, :test do
  gem "brakeman", "6.2.1", require: false
  gem "debug", "1.9.2", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "rubocop-rails-omakase", "1.0.0", require: false
  gem "rspec-rails", "7.1.1"
end