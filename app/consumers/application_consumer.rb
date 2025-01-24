# frozen_string_literal: true

class ApplicationConsumer < Karafka::BaseConsumer
  # Add any shared consumer behavior here
  def process
    messages.each do |message|
      Rails.logger.info("Processing message: #{message.payload}")
      process_message(message)
    end
  rescue StandardError => e
    Rails.logger.error("Error processing message: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise
  end

  private

  def process_message(_message)
    raise NotImplementedError, "#{self.class} must implement #process_message"
  end
end
