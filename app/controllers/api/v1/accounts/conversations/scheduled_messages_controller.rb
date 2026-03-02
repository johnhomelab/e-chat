module Api
  module V1
    module Accounts
      module Conversations
        class ScheduledMessagesController < Api::V1::Accounts::BaseController
          before_action :fetch_conversation, only: [:create, :index, :count]
          before_action :fetch_scheduled_message, only: [:show, :update, :destroy]

          def index
            return render json: { error: 'Conversation not found' }, status: :not_found unless @conversation

            @scheduled_messages = @conversation.scheduled_messages
            render json: {
              payload: @scheduled_messages.map do |message|
                {
                  id: message.id,
                  message: message.content,
                  scheduled_at: message.scheduled_at.to_i,
                  title: message.title,
                  inbox_id: message.inbox_id,
                  conversation_id: message.conversation_id,
                  created_at: message.created_at.to_i,
                  status: message.status || 'pending',
                  is_recurrent: message.is_recurrent,
                  period: message.period
                }
              end
            }
          end

          def create
            @scheduled_message = @conversation.scheduled_messages.new(scheduled_message_params)
            @scheduled_message.account_id = Current.account.id
            @scheduled_message.user_id = current_user.id
            @scheduled_message.status = 'pending'
            @scheduled_message.is_recurrent = params[:scheduled_message][:is_recurrent] if params[:scheduled_message].key?(:is_recurrent)
            
            # Processa o campo period como JSON
            if params[:scheduled_message].key?(:period) && params[:scheduled_message][:period].present?
              @scheduled_message.period = { type: params[:scheduled_message][:period] }
            end
            
            if @scheduled_message.save
              render json: {
                id: @scheduled_message.id,
                message: @scheduled_message.content,
                scheduled_at: @scheduled_message.scheduled_at.to_i,
                title: @scheduled_message.title,
                inbox_id: @scheduled_message.inbox_id,
                conversation_id: @scheduled_message.conversation_id,
                created_at: @scheduled_message.created_at.to_i,
                status: @scheduled_message.status,
                is_recurrent: @scheduled_message.is_recurrent,
                period: @scheduled_message.period
              }
            else
              render json: { error: @scheduled_message.errors.full_messages.join(', ') }, status: :unprocessable_entity
            end
          end

          def update
            params[:scheduled_message].delete(:status) if params[:scheduled_message]
            
            # Processa o campo period como JSON
            if params[:scheduled_message].key?(:period) && params[:scheduled_message][:period].present?
              params[:scheduled_message][:period] = { type: params[:scheduled_message][:period] }
            end
            
            if @scheduled_message.update(scheduled_message_params)
              render json: {
                id: @scheduled_message.id,
                message: @scheduled_message.content,
                scheduled_at: @scheduled_message.scheduled_at.to_i,
                title: @scheduled_message.title,
                inbox_id: @scheduled_message.inbox_id,
                conversation_id: @scheduled_message.conversation_id,
                created_at: @scheduled_message.created_at.to_i,
                status: @scheduled_message.status,
                is_recurrent: @scheduled_message.is_recurrent,
                period: @scheduled_message.period
              }
            else
              render json: { error: @scheduled_message.errors.full_messages.join(', ') }, status: :unprocessable_entity
            end
          end

          def destroy
            if @scheduled_message.destroy
              head :ok
            else
              render json: { error: @scheduled_message.errors.full_messages.join(', ') }, status: :unprocessable_entity
            end
          end

          def count
            return render json: { error: 'Conversation not found' }, status: :not_found unless @conversation

            count = @conversation.scheduled_messages.count
            render json: { count: count }
          end

          def show
            render json: {
              id: @scheduled_message.id,
              message: @scheduled_message.content,
              scheduled_at: @scheduled_message.scheduled_at.to_i,
              title: @scheduled_message.title,
              inbox_id: @scheduled_message.inbox_id,
              conversation_id: @scheduled_message.conversation_id,
              created_at: @scheduled_message.created_at.to_i
            }
          end

          private

          def fetch_conversation
            @conversation = Current.account.conversations.find_by(display_id: params[:conversation_id])
          end

          def fetch_scheduled_message
            @scheduled_message = Current.account.scheduled_messages.find(params[:id])
          end

          def scheduled_message_params
            params.require(:scheduled_message).permit(
              :content,
              :scheduled_at,
              :title,
              :inbox_id,
              :conversation_id,
              :status,
              :is_recurrent,
              :period
            )
          end
        end
      end
    end
  end
end 