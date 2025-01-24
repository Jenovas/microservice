module Api
  module V1
    class PushRetriesController < ApplicationController
      api :GET, "/api/v1/push_retries/stats", "Get statistics about push notification retries"
      def stats
        stats = FirebaseMessagingService.instance.retry_stats
        render json: stats
      end

      api :DELETE, "/api/v1/push_retries", "Cancel push notification retries"
      param :count, Integer, desc: "Number of oldest retries to cancel. If not provided, cancels all retries."
      def cancel
        count = params[:count]&.to_i
        cancelled = FirebaseMessagingService.instance.cancel_retries(count)
        render json: { cancelled_count: cancelled }
      end
    end
  end
end
