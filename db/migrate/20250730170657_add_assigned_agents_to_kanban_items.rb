class AddAssignedAgentsToKanbanItems < ActiveRecord::Migration[7.2]
  def up
    # Adicionar a nova coluna com valor padrão
    add_column :kanban_items, :assigned_agents, :jsonb, default: []

    # Adicionar índice GIN para consultas eficientes
    add_index :kanban_items, :assigned_agents, using: :gin

    # Migrar dados existentes de item_details['agent_id'] para assigned_agents
    KanbanItem.reset_column_information

    KanbanItem.find_each do |item|
      if item.item_details.is_a?(Hash) && item.item_details['agent_id'].present?
        agent_id = item.item_details['agent_id']

        # Verificar se o agente existe
        agent = ::User.find_by(id: agent_id)
        if agent
          # Adicionar o agente à nova coluna
          item.assigned_agents = [{
            id: agent.id,
            name: agent.name,
            email: agent.email,
            avatar_url: agent.avatar_url,
            assigned_at: Time.current,
            assigned_by: nil # Não temos contexto de usuário na migration
          }]

          # Remover o agent_id do item_details
          item.item_details.delete('agent_id')
          item.save!(validate: false)
        end
      end
    end
  end

  def down
    # Migrar dados de volta para item_details antes de remover a coluna
    KanbanItem.reset_column_information

    KanbanItem.find_each do |item|
      if item.assigned_agents.present? && item.assigned_agents.any?
        # Pegar o primeiro agente como principal
        primary_agent = item.assigned_agents.first
        if primary_agent && primary_agent['id']
          item.item_details['agent_id'] = primary_agent['id']
          item.save!(validate: false)
        end
      end
    end

    # Remover índice e coluna
    remove_index :kanban_items, :assigned_agents
    remove_column :kanban_items, :assigned_agents
  end
end
