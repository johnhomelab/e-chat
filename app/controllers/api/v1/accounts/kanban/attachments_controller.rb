class Api::V1::Accounts::Kanban::AttachmentsController < Api::V1::Accounts::BaseController
  before_action :fetch_kanban_item

  def create
    return render json: { error: 'No attachment provided' }, status: :unprocessable_entity if params[:attachment].blank?

    attachment = @kanban_item.attachments.attach(params[:attachment])

    if attachment && @kanban_item.validate_attachments
      # Invalidar cache do item individual após criar attachment
      Rails.cache.delete([@kanban_item.id, @kanban_item.updated_at.to_i])

      render json: {
        id: @kanban_item.attachments.last.id,
        attachment_url: url_for(@kanban_item.attachments.last),
        message: 'Attachment uploaded successfully'
      }, status: :created
    else
      render json: { error: @kanban_item.errors.full_messages.join(', ') },
             status: :unprocessable_entity
    end
  end

  def index
    attachments = @kanban_item.attachments.map do |attachment|
      {
        id: attachment.id,
        url: url_for(attachment),
        filename: attachment.filename.to_s,
        content_type: attachment.content_type,
        byte_size: attachment.byte_size,
        created_at: attachment.created_at
      }
    end

    render json: {
      item_id: @kanban_item.id,
      attachments: attachments,
      attachments_count: attachments.length
    }
  end

  def destroy
    # Busca o attachment pelo ID
    attachment = @kanban_item.attachments.find_by(id: params[:id])

    return render json: { error: 'Attachment not found' }, status: :not_found unless attachment

    # Remove o attachment usando o relacionamento Active Storage
    if attachment.purge
      # Invalidar cache do item individual após deletar attachment
      Rails.cache.delete([@kanban_item.id, @kanban_item.updated_at.to_i])

      render json: { message: 'Attachment deleted successfully' }
    else
      render json: { error: 'Could not delete attachment' }, status: :unprocessable_entity
    end
  end

  private

  def fetch_kanban_item
    @kanban_item = Current.account.kanban_items.find(params[:item_id])
  end
end
