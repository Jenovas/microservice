#!/usr/bin/env ruby
require 'optparse'
require 'json'
require 'net/http'
require 'kafka'

class PushTester
  def initialize(token:, platform:, method:)
    @token = token
    @platform = platform
    @method = method
  end

  def test
    case @method
    when 'kafka'
      test_via_kafka
    when 'api'
      test_via_api
    else
      puts "Unknown method: #{@method}"
      exit 1
    end
  end

  private

  def test_via_kafka
    kafka = Kafka.new(
      seed_brokers: ENV.fetch('KAFKA_BROKERS', 'localhost:9092'),
      client_id: "push-tester-#{SecureRandom.hex(4)}"
    )

    campaign = {
      campaign_guid: SecureRandom.uuid,
      push_title: "Test Campaign",
      push_subtitle: "Test Subtitle",
      push_text: "This is a test push notification sent at #{Time.now}",
      push_action: "open_app",
      users_android: @platform == 'android' ? [@token] : [],
      users_ios: @platform == 'ios' ? [@token] : []
    }

    kafka.deliver_message(
      campaign.to_json,
      topic: 'campaigns',
      partition_key: campaign[:campaign_guid]
    )

    puts "Campaign sent to Kafka:"
    puts JSON.pretty_generate(campaign)
    puts "\nCampaign GUID: #{campaign[:campaign_guid]}"
    puts "\nCheck the results with:"
    puts "curl \"http://localhost:3000/api/v1/campaigns/#{campaign[:campaign_guid]}/results\""
  end

  def test_via_api
    uri = URI('http://localhost:3000/api/v1/push_test')
    http = Net::HTTP.new(uri.host, uri.port)
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = {
      token: @token,
      platform: @platform
    }.to_json

    response = http.request(request)
    puts "API Response (#{response.code}):"
    puts JSON.pretty_generate(JSON.parse(response.body))
  end
end

# Parse command line arguments
options = {
  method: 'kafka'
}

OptionParser.new do |opts|
  opts.banner = "Usage: test_push.rb [options]"

  opts.on("-t", "--token TOKEN", "FCM/APNS token") do |t|
    options[:token] = t
  end

  opts.on("-p", "--platform PLATFORM", "Platform (android/ios)") do |p|
    options[:platform] = p
  end

  opts.on("-m", "--method METHOD", "Test method (kafka/api)") do |m|
    options[:method] = m
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Validate options
unless options[:token] && options[:platform]
  puts "Error: token and platform are required"
  exit 1
end

unless %w[android ios].include?(options[:platform])
  puts "Error: platform must be either 'android' or 'ios'"
  exit 1
end

unless %w[kafka api].include?(options[:method])
  puts "Error: method must be either 'kafka' or 'api'"
  exit 1
end

# Run the test
PushTester.new(
  token: options[:token],
  platform: options[:platform],
  method: options[:method]
).test 