module Api
  module V1
    class PushTestController < ApplicationController
      api :POST, "/api/v1/push_test", "Send a test push notification"
      param :token, String, required: true, desc: "Device token"
      param :device_type, String, required: true, desc: "Device type (android/ios)"
      param :certificate, Hash, required: true, desc: "Firebase JSON credentials or APNS certificate"
      param :certificate_password, String, desc: "Certificate password (required for APNS)"
      def send_test
        token = params.require(:token)
        device_type = params.require(:device_type).downcase
        certificate = params.require(:certificate)

        unless %w[android ios].include?(device_type)
          return render json: { error: "Invalid device_type. Must be 'android' or 'ios'" }, status: :bad_request
        end

        begin
          Rails.logger.info("[Push Test] Starting test push for device_type: #{device_type}, token: #{token}")

          # Create test campaign
          campaign = Campaign.new(
            campaign_guid: "test-#{SecureRandom.uuid}",
            token: token,
            device_type: device_type,
            campaign_type: "push",
            credentials: {
              certificate: certificate,
              certificate_password: params[:certificate_password]
            },
            payload: {
              push_title: "Test Push",
              push_text: "This is a test push notification",
              push_action: "open_app"
            },
            processed_at: Time.current
          )

          if campaign.save
            Rails.logger.info("[Push Test] Created campaign: #{campaign.campaign_guid}")

            begin
              notification_service = PushNotificationService.new(campaign)
              notification_service.send_notification

              Rails.logger.info("[Push Test] Notification sent, fetching results")
              results = PushResult.where(campaign_guid: campaign.campaign_guid)

              render json: {
                campaign_guid: campaign.campaign_guid,
                status: "success",
                results: results.map { |r| {
                  status: r.was_success ? "success" : "failure",
                  error: r.error
                }}
              }
            rescue StandardError => e
              Rails.logger.error("[Push Test] Error sending notification: #{e.message}")
              Rails.logger.error(e.backtrace.join("\n"))
              render json: { error: "Failed to send notification: #{e.message}" }, status: :internal_server_error
            end
          else
            Rails.logger.error("[Push Test] Campaign validation failed: #{campaign.errors.full_messages.join(', ')}")
            render json: { error: campaign.errors.full_messages.join(", ") }, status: :unprocessable_entity
          end
        rescue StandardError => e
          Rails.logger.error("[Push Test] Unexpected error: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          render json: { error: e.message }, status: :internal_server_error
        end
      end
    end
  end
end
