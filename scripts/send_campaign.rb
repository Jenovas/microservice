#!/usr/bin/env ruby
require 'kafka'
require 'json'
require 'securerandom'
require 'logger'

puts "Initializing Kafka producer..."

begin
  # Configure logger to show only important messages
  logger = Logger.new(STDOUT)
  logger.level = Logger::INFO  # Only show INFO and above
  logger.formatter = proc do |severity, datetime, progname, msg|
    if msg.include?('rdkafka')
      nil  # Skip rdkafka debug messages
    else
      "[#{datetime}] #{severity}: #{msg}\n"
    end
  end

  # Kafka configuration
  kafka = Kafka.new(
    seed_brokers: [ 'localhost:9092' ],
    client_id: "campaign-producer-#{SecureRandom.hex(4)}",
    logger: logger
  )

  # Test broker connection
  puts "Testing broker connection..."
  kafka.topics

  # Sample campaign message
  campaign = {
    campaign_guid: SecureRandom.uuid,
    push_title: "Test Campaign",
    push_subtitle: "Subtitle",
    push_text: "Hello, this is a test push notification!",
    push_rich_media: "https://example.com/image.jpg",
    push_action: "open_app",
    users_android: Array.new(5) { SecureRandom.hex(16) },  # 5 random FCM tokens
    users_ios: []      # 5 random APNS tokens
  }

  puts "Sending campaign to Kafka..."
  puts "Campaign GUID: #{campaign[:campaign_guid]}"
  puts "Message payload: #{campaign.to_json}"

  # Send message to Kafka
  kafka.deliver_message(
    campaign.to_json,
    topic: 'campaigns',
    partition_key: campaign[:campaign_guid]
  )

  puts "Campaign sent successfully!"
rescue Kafka::Error => e
  puts "Kafka error occurred: #{e.class} - #{e.message}"
  exit 1
rescue StandardError => e
  puts "Error occurred: #{e.class} - #{e.message}"
  exit 1
end
