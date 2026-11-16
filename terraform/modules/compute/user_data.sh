#!/bin/bash
# TODO: Adicionar healthcheck do Moodle após docker compose up para confirmar sucesso do deploy

set -euo pipefail

# Log de execução para troubleshooting
exec > >(tee -a /var/log/user-data.log)
exec 2>&1

echo "===== Iniciando configuração do Moodle $(date) ====="

# 1. Atualizar sistema e instalar dependências
echo ">> Atualizando sistema e instalando Docker..."
dnf update -y
dnf install -y docker git

# 2. Habilitar e iniciar Docker
echo ">> Habilitando e iniciando Docker..."
systemctl enable docker
systemctl start docker

# 3. Instalar Docker Compose v2 como plugin
# Amazon Linux 2023 não inclui docker-compose no dnf
# Versão fixada para evitar falha se API do GitHub atingir rate limit
# TODO: o nome do binario abaixo chumba a arquitetura (linux-x86_64). Funciona
# porque var.instance_type e da familia t3 (x86). Numa familia Graviton (t4g,
# m7g) o download traz o binario errado e `docker compose version` falha com
# "exec format error". Derivar o sufixo de `uname -m` resolveria.
echo ">> Instalando Docker Compose v2..."
DOCKER_CONFIG=/usr/local/lib/docker
DOCKER_COMPOSE_VERSION="v2.29.7"
mkdir -p $${DOCKER_CONFIG}/cli-plugins
curl -fsSL "https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o $${DOCKER_CONFIG}/cli-plugins/docker-compose
chmod +x $${DOCKER_CONFIG}/cli-plugins/docker-compose

# Verificar instalação
docker compose version

# 4. Clonar repositório com Moodle (idempotente)
# TODO: Considerar usar artifact pré-buildado ao invés de clone para produção
echo ">> Preparando diretório do Moodle..."
MOODLE_DIR="/opt/moodle"

if [ -d "$${MOODLE_DIR}/.git" ]; then
  echo "   Repositório já existe, fazendo pull..."
  cd "$${MOODLE_DIR}"
  git pull
else
  echo "   Clonando repositório..."
  rm -rf "$${MOODLE_DIR}"
  git clone ${repo_url} "$${MOODLE_DIR}"
fi

cd "$${MOODLE_DIR}/docker"

# 5. Criar docker-compose.override.yml para expor porta 80
# O docker-compose.yml do repo publica "8080:80" para ambiente local
# Em produção na AWS, o security group abre porta 80, então precisamos "80:80"
# Override substitui a configuração de ports do arquivo original
echo ">> Criando docker-compose.override.yml para porta 80..."
cat > docker-compose.override.yml <<'OVERRIDE_EOF'
services:
  moodle:
    ports:
      - "80:80"
OVERRIDE_EOF

# Criar arquivo .env com credenciais do RDS
echo ">> Criando arquivo .env com configurações do banco RDS..."
# Criar arquivo com permissão restrita ANTES de escrever conteúdo
# Evita janela onde arquivo existe com 644 e credenciais expostas
touch .env
chmod 600 .env

# Heredoc com aspas simples impede expansão de variáveis pelo shell
# Sem aspas, caracteres especiais ($, `, \) nas senhas seriam interpretados
cat > .env <<'EOF'
# Gerado automaticamente pelo Terraform
# TODO: Migrar para AWS Secrets Manager em produção para rotação automática

MOODLE_DATABASE_TYPE=pgsql
MOODLE_DATABASE_HOST=${rds_address}
MOODLE_DATABASE_NAME=${db_name}
MOODLE_DATABASE_USER=${db_username}
MOODLE_DATABASE_PASSWORD=${db_password}
MOODLE_DATABASE_PORT_NUMBER=5432
MOODLE_USERNAME=${moodle_admin_user}
MOODLE_PASSWORD=${moodle_admin_password}
MOODLE_SITE_NAME=${moodle_site_name}
EOF

# CRÍTICO: usar --no-deps para não subir o serviço 'db' local do Compose
# O docker-compose.yml define serviço 'db' (Postgres local) para desenvolvimento
# Em produção usamos RDS, não o Postgres local
# Sem --no-deps, Compose sobe Postgres ocioso e depends_on trava o Moodle esperando por ele
echo ">> Iniciando Moodle com Docker Compose..."
docker compose up -d --build --no-deps moodle

# 8. Aguardar inicialização
echo ">> Aguardando inicialização do Moodle..."
sleep 30

# 9. Verificar status
echo ">> Status dos contêineres:"
docker compose ps

# 10. Obter hostname público via IMDSv2
# IMDSv2 exige token de sessão - sem token retorna 401
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PUBLIC_HOSTNAME=$(curl -s -H "X-aws-ec2-metadata-token: $${TOKEN}" \
  http://169.254.169.254/latest/meta-data/public-hostname)

echo "===== Configuração concluída $(date) ====="
echo ">> Moodle deve estar acessível em: http://$${PUBLIC_HOSTNAME}"
