class Api::V1::KanbanAutomationsController < Api::BaseController
  before_action :set_automation, only: [:show, :update, :destroy]

  def index
    @automations = KanbanAutomation.all
    render json: @automations
  end

  def show
    render json: @automation
  end

  def create
    @automation = KanbanAutomation.new(automation_params)

    if @automation.save
      render json: @automation, status: :created
    else
      render json: { error: @automation.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    if @automation.update(automation_params)
      render json: @automation
    else
      render json: { error: @automation.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def destroy
    @automation.destroy
    head :no_content
  end

  private

  def set_automation
    @automation = KanbanAutomation.find(params[:id])
  end

  def automation_params
    params.require(:kanban_automation).permit(
      :name, 
      :description, 
      :active,
      trigger: {},
      conditions: [],
      actions: []
    )
  end
end
