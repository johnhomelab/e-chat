# 🐳 Setup do Workflow Docker Build & Release

## ✅ Criado com Sucesso
- Arquivo: `.github/workflows/build-and-release.yml`
- Trigger: Push/merge na branch `main`
- Imagem: `stacklabdigital/kanban:latest`
- Versioning: Inicia em `v2.7.7`

## 🔧 CONFIGURAÇÃO OBRIGATÓRIA

### 1. Secrets do GitHub (IMPORTANTE!)
Vá em **Settings → Secrets and variables → Actions** e adicione:

- `DOCKER_USERNAME`: Seu username do Docker Hub
- `DOCKER_PASSWORD`: Token do Docker Hub

### 2. Como criar Token Docker Hub:
1. Acesse Docker Hub → Account Settings → Security
2. New Access Token → Name: "github-actions" → Generate
3. Copie o token e cole em `DOCKER_PASSWORD`

## 🚀 Como Funciona

1. Push na `main` → Workflow executa automaticamente
2. Busca última tag (se não existe, inicia v2.7.7)
3. Incrementa versão (+0.0.1)
4. Build Docker multi-platform
5. Push para `stacklabdigital/kanban:latest` e `stacklabdigital/kanban:v2.7.x`
6. Cria tag Git e Release no GitHub

## 🏷️ Sistema de Versões
- v2.7.7 → v2.7.8 → v2.7.9 (incremento automático)
- Docker tags: `latest` + versão específica

## 📋 Para Testar
1. Configure os secrets
2. Faça um push na main
3. Veja em Actions → Build and Release

Pronto! 🎉
