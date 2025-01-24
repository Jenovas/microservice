module Api
  module V1
    class CampaignsController < ApplicationController
      include ActionController::API

      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ActionController::ParameterMissing, with: :bad_request

      api :GET, "/api/v1/campaigns/:campaign_guid", "Get all entries for a campaign"
      param :campaign_guid, String, required: true, desc: "Campaign GUID"
      param :device_type, String, desc: "Filter by device type (android/ios)"
      param :campaign_type, String, desc: "Filter by campaign type (push/in_app/feed)"
      def show
        campaigns = Campaign.by_campaign_guid(params.require(:campaign_guid))
        campaigns = campaigns.by_device_type(params[:device_type]) if params[:device_type].present?
        campaigns = campaigns.by_campaign_type(params[:campaign_type]) if params[:campaign_type].present?

        render json: {
          campaign_guid: params[:campaign_guid],
          total_recipients: campaigns.count,
          entries: campaigns.map { |c| campaign_response(c) }
        }
      end

      api :GET, "/api/v1/campaigns/:campaign_guid/results", "Get campaign results"
      param :campaign_guid, String, required: true, desc: "Campaign GUID"
      param :device_type, String, desc: "Filter by device type (android/ios)"
      param :status, String, desc: "Filter by status (success/failure)"
      def results
        campaigns = Campaign.by_campaign_guid(params.require(:campaign_guid))
        campaigns = campaigns.by_device_type(params[:device_type]) if params[:device_type].present?

        results = PushResult.where(campaign_guid: params[:campaign_guid])
        results = results.where(status: params[:status]) if params[:status].present?

        render json: {
          campaign_guid: params[:campaign_guid],
          total_recipients: campaigns.count,
          total_results: results.count,
          success_count: results.where(status: "success").count,
          failure_count: results.where(status: "failure").count,
          campaigns: campaigns.map { |c| campaign_response(c) },
          results: results.map { |r| result_response(r) }
        }
      end

      private

      def campaign_response(campaign)
        {
          id: campaign.id,
          campaign_guid: campaign.campaign_guid,
          token: campaign.token,
          device_type: campaign.device_type,
          campaign_type: campaign.campaign_type,
          payload: campaign.payload,
          processed_at: campaign.processed_at,
          created_at: campaign.created_at,
          updated_at: campaign.updated_at
        }
      end

      def result_response(result)
        {
          id: result.id,
          campaign_guid: result.campaign_guid,
          token: result.token,
          status: result.status,
          error: result.error,
          created_at: result.created_at
        }
      end

      def not_found
        render json: { error: "Campaign not found" }, status: :not_found
      end

      def bad_request(e)
        render json: { error: e.message }, status: :bad_request
      end
    end
  end
end
