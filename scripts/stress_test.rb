#!/usr/bin/env ruby
require 'optparse'
require 'json'
require 'net/http'
require 'ruby-kafka'
require 'connection_pool'
require 'concurrent'
require 'securerandom'

class StressTest
  def initialize(rps:, duration:, num_threads:)
    @rps = rps
    @duration = duration
    @num_threads = num_threads
    @kafka_pool = ConnectionPool.new(size: num_threads, timeout: 5) do
      kafka = Kafka.new(
        seed_brokers: ['localhost:9092'],
        client_id: "stress-test-#{SecureRandom.hex(4)}",
        logger: Logger.new(STDOUT)  # Enable logging temporarily for debugging
      )
      
      # Verify connection
      begin
        kafka.topics
        puts "Successfully connected to Kafka"
      rescue => e
        puts "Failed to connect to Kafka: #{e.message}"
        raise
      end
      
      kafka
    end
    
    @start_time = Time.now
    @sent_messages = Concurrent::AtomicFixnum.new(0)
    @failed_messages = Concurrent::AtomicFixnum.new(0)
  end

  def run
    puts "Starting stress test with #{@rps} RPS using #{@num_threads} threads..."
    puts "Test will run for #{@duration} seconds"
    puts "Press Ctrl+C to stop"
    
    # Calculate delay between messages to achieve desired RPS
    delay = 1.0 / (@rps.to_f / @num_threads)
    
    threads = @num_threads.times.map do
      Thread.new do
        until Time.now - @start_time > @duration
          send_campaign
          sleep delay
        end
      end
    end

    # Start monitoring thread
    monitor_thread = Thread.new do
      while Time.now - @start_time <= @duration
        sleep 1
        current_rps = @sent_messages.value / (Time.now - @start_time)
        puts "[#{Time.now.strftime('%H:%M:%S')}] Sent: #{@sent_messages.value}, Failed: #{@failed_messages.value}, Current RPS: #{current_rps.round(2)}"
      end
    end

    threads.each(&:join)
    monitor_thread.join

    print_results
  end

  private

  def send_campaign
    campaign = generate_campaign
    
    @kafka_pool.with do |kafka|
      kafka.deliver_message(
        campaign.to_json,
        topic: 'campaigns',
        partition_key: campaign[:campaign_guid]
      )
      @sent_messages.increment
    end
  rescue StandardError => e
    @failed_messages.increment
    puts "Error sending message: #{e.message}" if ENV['DEBUG']
  end

  def generate_campaign
    {
      campaign_guid: SecureRandom.uuid,
      push_title: "Stress Test Campaign",
      push_subtitle: "Subtitle",
      push_text: "This is a stress test notification #{SecureRandom.hex(4)}",
      push_rich_media: "https://example.com/image.jpg",
      push_action: "open_app",
      push_action_destination: "myapp://products/#{SecureRandom.hex(8)}",
      users_android: Array.new(5) { SecureRandom.hex(16) },
      users_ios: Array.new(5) { SecureRandom.hex(16) }
    }
  end

  def print_results
    total_time = Time.now - @start_time
    total_sent = @sent_messages.value
    total_failed = @failed_messages.value
    actual_rps = total_sent / total_time

    puts "\nTest Results:"
    puts "============="
    puts "Duration: #{total_time.round(2)} seconds"
    puts "Total Messages Sent: #{total_sent}"
    puts "Total Messages Failed: #{total_failed}"
    puts "Average RPS: #{actual_rps.round(2)}"
    puts "Success Rate: #{((total_sent - total_failed).to_f / total_sent * 100).round(2)}%"
  end
end

# Parse command line arguments
options = {
  rps: 100,
  duration: 60,
  threads: 8
}

OptionParser.new do |opts|
  opts.banner = "Usage: stress_test.rb [options]"

  opts.on("-r", "--rps RPS", Integer, "Requests per second (default: 100)") do |r|
    options[:rps] = r
  end

  opts.on("-d", "--duration SECONDS", Integer, "Test duration in seconds (default: 60)") do |d|
    options[:duration] = d
  end

  opts.on("-t", "--threads NUM", Integer, "Number of threads (default: 8)") do |t|
    options[:threads] = t
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Run the stress test
StressTest.new(
  rps: options[:rps],
  duration: options[:duration],
  num_threads: options[:threads]
).run 