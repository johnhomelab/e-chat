class Api::V1::Accounts::ScheduledMessagesController < Api::V1::Accounts::BaseController
  def create
    @scheduled_message = Current.account.scheduled_messages.create!(scheduled_message_params)
    render json: @scheduled_message
  end

  def count
    count = Current.account.scheduled_messages
                  .where(conversation_id: params[:conversation_id])
                  .count
    render json: { count: count }
  end

  def destroy
    @scheduled_message = Current.account.scheduled_messages.find(params[:id])
    @scheduled_message.destroy!
    render json: { message: 'Scheduled message deleted successfully' }
  end

  private

  def scheduled_message_params
    params.permit(:conversation_id, :inbox_id, :content, :scheduled_at)
          .merge(user_id: Current.user.id)
  end
end 