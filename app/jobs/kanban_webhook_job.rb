class KanbanWebhookJob < ApplicationJob
  queue_as :medium

  def perform(webhook_url, payload, event_type)
    return unless webhook_url.present?

    begin
      response = RestClient::Request.execute(
        method: :post,
        url: webhook_url,
        payload: payload.to_json,
        headers: {
          content_type: :json,
          accept: :json,
          'User-Agent': 'Chatwoot-Kanban-Webhook/1.0'
        },
        timeout: 30
      )

      Rails.logger.info "Kanban webhook sent successfully: #{event_type} to #{webhook_url}"
      Rails.logger.debug { "Webhook payload: #{payload}" }

    rescue RestClient::Exception => e
      Rails.logger.error "Kanban webhook failed (#{event_type}): #{e.message} - URL: #{webhook_url}"
      Rails.logger.error "Response code: #{e.http_code}, Response body: #{e.http_body}"

    rescue StandardError => e
      Rails.logger.error "Kanban webhook error (#{event_type}): #{e.message} - URL: #{webhook_url}"
      Rails.logger.error "Error class: #{e.class}, Backtrace: #{e.backtrace.first(5).join(', ')}"
    end
  end
end
