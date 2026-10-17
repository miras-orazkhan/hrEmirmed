ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

if (ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development") == "development"
  require "dotenv"
  Dotenv.load(File.expand_path("../.env", __dir__))
end

require "bootsnap/setup" # Speed up boot time by caching expensive operations.
