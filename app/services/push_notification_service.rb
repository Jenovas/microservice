class PushNotificationService
  def initialize(campaign)
    @campaign = campaign
  end

  def send_notification
    case @campaign.device_type
    when "android"
      send_android_notification
    when "ios"
      send_ios_notification
    end
  end

  private

  def send_android_notification
    begin
      message = build_firebase_message
      response = FirebaseMessagingService.instance.send_message(
        @campaign.credentials["certificate"],
        message
      )

      Rails.logger.info("[Firebase Success] Sent notification for campaign: #{@campaign.campaign_guid}")
      create_push_result("success")
    rescue StandardError => e
      Rails.logger.error("[Firebase Error] Failed to send notification: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      create_push_result("failure", e.message)
    end
  end

  def send_ios_notification
    begin
      apns_client = create_apns_client
      notification = build_apns_notification
      response = apns_client.push(notification)

      Rails.logger.info("[APNS Success] Sent notification for campaign: #{@campaign.campaign_guid}")
      create_push_result("success")
    rescue StandardError => e
      Rails.logger.error("[APNS Error] Failed to send notification: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      create_push_result("failure", e.message)
    end
  end

  def create_apns_client
    cert = OpenSSL::X509::Certificate.new(@campaign.credentials["certificate"])
    pkey = OpenSSL::PKey::RSA.new(
      @campaign.credentials["certificate"],
      @campaign.credentials["certificate_password"]
    )

    Houston::Client.development.tap do |client|
      client.certificate = cert
      client.key = pkey
    end
  end

  def build_firebase_message
    message = {
      message: {
        token: @campaign.token,
        notification: {
          title: @campaign.payload["push_title"],
          body: @campaign.payload["push_text"]
        },
        android: {
          notification: {
            click_action: @campaign.payload["push_action"],
            channel_id: "default"
          }
        },
        data: {}
      }
    }

    # Add subtitle if present
    if @campaign.payload["push_sub_title"].present?
      message[:message][:notification][:subtitle] = @campaign.payload["push_sub_title"]
    end

    # Add rich media if present
    if @campaign.payload["push_rich_media"].present?
      message[:message][:notification][:image] = @campaign.payload["push_rich_media"]
    end

    # Add action URL if present for deeplink or url actions
    if %w[deeplink url].include?(@campaign.payload["push_action"]) && @campaign.payload["push_action_url"].present?
      message[:message][:data][:action_url] = @campaign.payload["push_action_url"]
    end

    # Add buttons if present
    if @campaign.payload["push_buttons"].present?
      buttons = @campaign.payload["push_buttons"].sort_by { |btn| btn["buttonPosition"] }
      message[:message][:android][:notification][:buttons] = buttons.map do |button|
        btn = {
          button_text: button["buttonLabel"],
          button_action: button["buttonAction"]
        }

        # Add action URL for buttons if needed
        if %w[deeplink url].include?(button["buttonAction"]) && button["button_action_url"].present?
          btn[:button_action_url] = button["button_action_url"]
        end

        btn
      end
    end

    message
  end

  def build_apns_notification
    notification = Houston::Notification.new(device: @campaign.token)

    # Basic notification content
    notification.alert = {
      title: @campaign.payload["push_title"],
      subtitle: @campaign.payload["push_sub_title"],
      body: @campaign.payload["push_text"]
    }.compact

    # Add rich media if present
    if @campaign.payload["push_rich_media"].present?
      notification.mutable_content = true
      notification.content_available = true
      notification.custom_data = {
        rich_media_url: @campaign.payload["push_rich_media"]
      }
    end

    # Handle actions
    case @campaign.payload["push_action"]
    when "deeplink", "url"
      notification.custom_data ||= {}
      notification.custom_data[:action] = @campaign.payload["push_action"]
      notification.custom_data[:action_url] = @campaign.payload["push_action_url"]
    when "open_app"
      notification.custom_data ||= {}
      notification.custom_data[:action] = "open_app"
    end

    # Add buttons if present
    if @campaign.payload["push_buttons"].present?
      buttons = @campaign.payload["push_buttons"].sort_by { |btn| btn["buttonPosition"] }

      # Create a unique category ID for this campaign's buttons
      category_id = "CAMPAIGN_#{@campaign.campaign_guid}"
      notification.category = category_id

      # Add button actions to custom data
      notification.custom_data ||= {}
      notification.custom_data[:buttons] = buttons.map do |button|
        {
          id: "btn_#{button["buttonPosition"]}",
          label: button["buttonLabel"],
          action: button["buttonAction"],
          action_url: button["button_action_url"]
        }.compact
      end
    end

    notification
  end

  def create_push_result(status, error = nil)
    PushResult.create!(
      campaign_guid: @campaign.campaign_guid,
      user_token: @campaign.token,
      platform: @campaign.device_type,
      was_success: status == "success",
      error: error,
      processed_at: Time.current
    )
  end
end
