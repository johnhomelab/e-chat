class CreateKanbanItems < ActiveRecord::Migration[7.0]
  def up
    # Renomeia a tabela existente se ela existir
    if table_exists?(:kanban_items)
      rename_table :kanban_items, :kanban_items_old
    end

    create_table :kanban_items do |t|
      # Relacionamentos essenciais
      t.references :account, null: false, index: true
      t.bigint :conversation_display_id # Opcional, para integração com conversas
      
      # Campos de funil e etapa
      t.bigint :funnel_id, null: false
      t.string :funnel_stage, null: false
      t.datetime :stage_entered_at
      
      # Campo para posição no quadro
      t.integer :position, null: false
      
      # Campos flexíveis para personalização
      t.jsonb :custom_attributes, default: {} # Atributos personalizados por conta
      t.jsonb :item_details, default: {} # Detalhes como título, descrição, prioridade, etc
      
      # Campos para controle de tempo
      t.datetime :timer_started_at # Para controle de SLA ou tempo em cada etapa
      t.integer :timer_duration, default: 0 # Duração em segundos

      t.timestamps
    end

    # Índices para otimização
    add_index :kanban_items, [:conversation_display_id]
    add_index :kanban_items, [:funnel_id]
    add_index :kanban_items, [:funnel_id, :funnel_stage]
    add_index :kanban_items, [:account_id, :funnel_id, :funnel_stage]
  end

  def down
    drop_table :kanban_items if table_exists?(:kanban_items)
    
    # Restaura a tabela antiga se ela existir
    if table_exists?(:kanban_items_old)
      rename_table :kanban_items_old, :kanban_items
    end
  end
end 