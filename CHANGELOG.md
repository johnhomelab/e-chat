# Changelog v2.7.8
**Imagem: stacklabdigital/kanban:v2.7.8**

## 30 de julho de 2025

### ✨ Novas funcionalidades e Correções
- **Lista de verificação (Checklist)**: Sistema de checklist integrado ao Kanban com atribuição de agentes
- **Campanhas WhatsApp**: Nova funcionalidade para criar e gerenciar campanhas de marketing via WhatsApp (4.4.0) 
- **Cadastro incorporado WhatsApp**: Processo simplificado de integração WhatsApp diretamente na plataforma (4.4.0)
- **Notas privadas em automações**: Possibilidade de adicionar notas privadas nas regras de automação (4.4.0)
- **Menu de configurações**: Novo submenu organizado para configurações de super administrador (4.4.0)
- **Envio de mensagens na API Oficial do Whatsapp**: Corrigido o erro em @signature que impedia o envio de menagens pela API oficial quando não era template (4.4.0)
- **Sistema de movimentação de itens**: Implementação de métodos para mover itens entre estágios do Kanban com controle de permissões
- **Paginação avançada**: Sistema de paginação otimizado para itens do Kanban com suporte a filtros por funil, estágio e agente
- **Gestão de agentes em itens**: Funcionalidade para atribuir e remover agentes de itens do Kanban
- **Sistema de notas em itens**: Possibilidade de criar e gerenciar notas em itens do Kanban
- **Controle de status de itens**: Sistema para alterar status de itens do Kanban
- **Gestão de agentes em checklist**: Atribuição e remoção de agentes em itens específicos de checklist
- **API de funis**: Endpoints para gerenciamento de funis com estatísticas de estágios
- **Geração automática de changelog**: Script para gerar changelog em formato JSON para integração com webhooks

### 🔌 Endpoints de Ações dos Itens do Kanban
- **POST /api/v1/accounts/:account_id/kanban_items/:id/move_to_stage**: Move item para estágio específico com validação de permissões
- **POST /api/v1/accounts/:account_id/kanban_items/:id/move**: Movimentação simples entre funil e estágio
- **POST /api/v1/accounts/:account_id/kanban_items/:id/create_checklist_item**: Cria novo item na checklist com ID único e timestamp
- **POST /api/v1/accounts/:account_id/kanban_items/:id/create_note**: Adiciona nota ao item com autor e timestamp
- **POST /api/v1/accounts/:account_id/kanban_items/:id/assign_agent**: Atribui agente ao item com validação de duplicação
- **DELETE /api/v1/accounts/:account_id/kanban_items/:id/remove_agent**: Remove agente específico do item
- **GET /api/v1/accounts/:account_id/kanban_items/:id/assigned_agents**: Lista agentes atribuídos e agente primário
- **POST /api/v1/accounts/:account_id/kanban_items/:id/change_status**: Altera status do item (won/lost/open)
- **POST /api/v1/accounts/:account_id/kanban_items/:id/assign_agent_to_checklist_item**: Atribui agente a item específico da checklist
- **DELETE /api/v1/accounts/:account_id/kanban_items/:id/remove_agent_from_checklist_item**: Remove agente de item específico da checklist
- **POST /api/v1/accounts/:account_id/kanban_items/reorder**: Reordena múltiplos itens em transação com atualização de cache
- **GET /api/v1/accounts/:account_id/kanban_items/debug**: Informações de debug com ambiente, versões e dados de exemplo
- **GET /api/v1/accounts/:account_id/funnels/:id/stage_stats**: Estatísticas de estágios com contagem e valores totais

### 🎨 Interface/Design
- **Cabeçalho do Kanban**: Layout aprimorado com melhor espaçamento e organização visual
- **Seletor de funil**: Estilos refinados para melhor experiência do usuário
- **Componentes Vue.js otimizados**: Melhorias nos componentes KanbanColumn, KanbanHeader e KanbanTab
- **Modal de envio em massa**: Interface aprimorada para envio de mensagens em massa
- **Formulário de templates**: Melhorias no formulário de criação de templates de mensagem

### ⚡ Melhorias de performance
- **Processamento de mensagens**: Otimização do sistema de atualização de status de mensagens para melhor performance
- **Cache de itens do Kanban**: Implementação de cache baseado em ID e updated_at para melhor performance
- **Paginação otimizada**: Sistema de paginação com limite de 50 itens por página para melhor performance
- **Queries otimizadas**: Melhorias nas consultas do banco de dados com includes apropriados

### 🔧 Melhorias gerais
- **Dependências**: Atualizadas dependências do sistema e configurações Docker
- **Qualidade de código**: Implementada ferramenta Qlty para melhoria contínua da qualidade do código
- **Políticas de autorização**: Implementação de políticas específicas para operações do Kanban
- **Logs de debug**: Adicionados logs detalhados para facilitar debugging do sistema
- **Documentação OpenAPI**: Geração automática de documentação OpenAPI para endpoints do Kanban
- **Integração com Makefile**: Comandos otimizados para build e deploy com suporte a changelog automático
- **Validação de parâmetros**: Validação robusta de parâmetros obrigatórios em todos os endpoints
- **Tratamento de erros**: Mensagens de erro específicas e códigos de status HTTP apropriados
- **Transações de banco**: Uso de transações para operações críticas como reordenação
- **Controle de versão de estágios**: Sistema para evitar conflitos de IDs em estágios de funis
