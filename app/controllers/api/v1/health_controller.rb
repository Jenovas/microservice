module Api
  module V1
    class HealthController < ApplicationController
      include ActionController::API

      api :GET, "/api/v1/health", "Health check endpoint"
      def show
        health_status = {
          database: database_connected?,
          kafka: kafka_connected?,
          timestamp: Time.current
        }

        if health_status.values.all?
          render json: health_status, status: :ok
        else
          render json: health_status, status: :service_unavailable
        end
      end

      private

      def database_connected?
        ActiveRecord::Base.connection.active?
      rescue StandardError
        false
      end

      def kafka_connected?
        Karafka.monitor.consumer_groups.any?
      rescue StandardError
        false
      end
    end
  end
end
