class Conversations::ForwardMessageJob < ApplicationJob
    queue_as :default
  
    def perform(payload)
      @user = User.find(payload[:user_id])
      @account = Account.find(payload[:account_id])
      @message = Message.find(payload[:message_id])
      @target_conversation_ids = payload[:target_conversation_ids] || []
  
      Rails.logger.info @message
      return if @target_conversation_ids.blank?
  
      @target_conversation_ids.each do |conversation_id|
        target_conversation = @account.conversations.find(conversation_id)
        Rails.logger.info target_conversation
        msg = target_conversation.messages.build(message_params(target_conversation))
        Rails.logger.info msg
        process_attachment(msg)
        msg.save!
      rescue StandardError => e
        Rails.logger.error e
        raise e
      end
    end
  
    private
  
    def message_params(target_conversation)
      {
        account_id: @message.account_id,
        inbox_id: target_conversation.inbox_id,
        content: @message.content,
        content_type: @message.content_type,
        content_attributes: @message.content_attributes,
        message_type: :outgoing,
        sender: @user
      }
    end
  
  
    def process_attachment(msg)
      Rails.logger.info @message.attachments
      return if @message.attachments.blank?
  
      @message.attachments.each do |attachment|
        Rails.logger.info attachment
        attach_file(msg, attachment)
        attach_location(msg, attachment)
        attach_contact(msg, attachment)
      end
    end
  
    def attach_file(msg, attachment)
      return if %w[image audio video file].include?(attachment.file_type) == false
      msg.attachments.new(
        account_id: attachment.account_id,
        file_type: attachment.file_type,
        file: attachment.file.blob
      )
    end
  
    def attach_location(msg, attachment)
      return if attachment.file_type != "location"
      msg.attachments.new(
        account_id: attachment.account_id,
        file_type: attachment.file_type,
        coordinates_lat: attachment.coordinates_lat,
        coordinates_long: attachment.coordinates_long,
        fallback_title: attachment.fallback_title,
        external_url: attachment.external_url
      )
    end
  
    def attach_contact(msg, attachment)
      return if attachment.file_type != "contact"
      msg.attachments.new(
        account_id: attachment.account_id,
        file_type: attachment.file_type,
        fallback_title: attachment.fallback_title
      )
    end
  end