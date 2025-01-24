# frozen_string_literal: true

class KarafkaApp < Karafka::App
  setup do |config|
    config.client_id = 'microservice'

    # Optimize for 8 cores / 16 threads
    config.concurrency = 8
    config.max_messages = 1000
    config.max_wait_time = 500
    config.shutdown_timeout = 60_000

    # Enable parallel processing
    config.consumer_persistence = true

    # Optimize network settings
    config.kafka = {
      'bootstrap.servers': ENV.fetch('KAFKA_BROKERS', 'localhost:9092'),
      'socket.keepalive.enable': true,
      'max.poll.interval.ms': 300_000,
      'session.timeout.ms': 60_000,
      'max.partition.fetch.bytes': 1048576, # 1MB per partition
      'fetch.min.bytes': 1,
      'fetch.max.bytes': 5_242_880, # 5MB
      'fetch.wait.max.ms': 500,
      'heartbeat.interval.ms': 20_000,
      'metadata.max.age.ms': 300_000,
      'reconnect.backoff.ms': 1000,
      'request.timeout.ms': 30_000
    }

    # Configure logging level
    config.logger.level = ::Logger::INFO
  end
end

# Initialize the Karafka app
KarafkaApp.initialize!

Karafka.monitor.subscribe(Karafka::Instrumentation::LoggerListener.new)
Karafka.monitor.subscribe(Karafka::Instrumentation::ProctitleListener.new)

Rails.logger.info("[Karafka] Setting up consumer groups...")

# Register topics for consumption
KarafkaApp.consumer_groups.draw do
  consumer_group :microservice do
    topic :campaigns do
      consumer CampaignsConsumer
      max_messages 1000
      max_wait_time 500
    end
  end
end

Rails.logger.info("[Karafka] Consumer groups set up. Topics registered: campaigns")
