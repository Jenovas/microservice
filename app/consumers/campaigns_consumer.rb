class CampaignsConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      Rails.logger.info("[Campaign Processing] Topic: #{message.topic}, Campaign: #{message.payload['campaign_guid']}")

      campaign = Campaign.new(
        campaign_guid: message.payload["campaign_guid"],
        token: message.payload["token"],
        device_type: message.payload["device_type"]&.downcase,
        credentials: message.payload["credentials"] || {},
        campaign_type: message.payload["campaign_type"]&.downcase,
        payload: message.payload["payload"] || {},
        processed_at: Time.current
      )

      if campaign.save
        Rails.logger.info("[Campaign Created] ID: #{campaign.id}, GUID: #{campaign.campaign_guid}")
        process_campaign(campaign)
      else
        Rails.logger.error("[Campaign Error] Topic: #{message.topic}, Campaign: #{campaign.campaign_guid} - #{campaign.errors.full_messages.join(', ')}")
      end
    rescue StandardError => e
      Rails.logger.error("[Campaign Error] Topic: #{message.topic}, Campaign: #{message.payload['campaign_guid']} - #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end
  end

  private

  def process_campaign(campaign)
    case campaign.campaign_type
    when "push"
      process_push_campaign(campaign)
    when "in_app"
      process_in_app_campaign(campaign)
    when "feed"
      process_feed_campaign(campaign)
    end
  end

  def process_push_campaign(campaign)
    Rails.logger.info("[Push Campaign] Starting to process campaign: #{campaign.campaign_guid}")

    begin
      notification_service = PushNotificationService.new(campaign)
      notification_service.send_notification

      Rails.logger.info("[Push Campaign] Successfully processed campaign: #{campaign.campaign_guid}")
    rescue StandardError => e
      Rails.logger.error("[Push Campaign Error] Failed to process campaign #{campaign.campaign_guid}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

      # Create a failed push result if the service didn't create one
      PushResult.create!(
        campaign_guid: campaign.campaign_guid,
        token: campaign.token,
        status: "failure",
        error: "Failed to send push notification: #{e.message}"
      )
    end
  end

  def process_in_app_campaign(campaign)
    # Implementation for in-app messages
    Rails.logger.info("[In-App Campaign] Processing campaign: #{campaign.campaign_guid}")
  end

  def process_feed_campaign(campaign)
    # Implementation for feed items
    Rails.logger.info("[Feed Campaign] Processing campaign: #{campaign.campaign_guid}")
  end
end
