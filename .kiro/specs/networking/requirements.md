# Requirements: Módulo Terraform Networking

## Objetivo

Provisionar a camada de rede completa da infraestrutura Moodle na AWS, incluindo VPC, subnets públicas e privadas em múltiplas AZs, Internet Gateway, route tables e security groups para EC2 e RDS.

## Funcionalidades

### VPC

- **CIDR block**: `10.0.0.0/16` (65.534 hosts disponíveis)
- **DNS hostnames**: `enable_dns_hostnames = true` (OBRIGATÓRIO — o endpoint do RDS é um nome DNS, não um IP)
- **DNS support**: `enable_dns_support = true`
- **Região**: `us-east-1` (fixa, restrição do AWS Academy Learner Lab)

### Subnets Públicas

Duas subnets públicas em AZs diferentes, ambas com IP público automático:

- **Subnet pública 1**:
  - CIDR: `10.0.1.0/24` (254 hosts)
  - AZ: `us-east-1a`
  - `map_public_ip_on_launch = true`
  - Hospeda: instância EC2 do Moodle

- **Subnet pública 2**:
  - CIDR: `10.0.4.0/24` (254 hosts)
  - AZ: `us-east-1b`
  - `map_public_ip_on_launch = true`
  - Hospeda: nada hoje (preparação para ALB/Auto Scaling futuro)

### Subnets Privadas

Duas subnets privadas em AZs diferentes para o RDS:

- **Subnet privada 1**:
  - CIDR: `10.0.2.0/24` (254 hosts)
  - AZ: `us-east-1a`
  - Hospeda: instância RDS PostgreSQL

- **Subnet privada 2**:
  - CIDR: `10.0.3.0/24` (254 hosts)
  - AZ: `us-east-1b`
  - Hospeda: nada (existe apenas para satisfazer `aws_db_subnet_group`, que exige mínimo de 2 AZs)

### Internet Gateway e Roteamento

- **Internet Gateway**: anexado à VPC, provê conectividade bidirecional com a internet
- **Route Table pública**: 
  - Rota: `0.0.0.0/0 → Internet Gateway`
  - Associada às **DUAS** subnets públicas (associação explícita necessária para ambas)
- **Subnets privadas**: herdam route table principal da VPC (apenas rota local `10.0.0.0/16`, sem acesso à internet)

### Security Groups

#### Security Group da EC2

**Ingresso**:
- **HTTP (porta 80)**: origem `0.0.0.0/0` (Moodle publicamente acessível)
- **SSH (porta 22)**: origem `var.ssh_allowed_cidr` (CIDR configurável, idealmente IP específico do operador)

**Egresso**:
- Todo tráfego liberado (`0.0.0.0/0`, protocolo `-1`) — EC2 precisa conectar ao RDS, baixar pacotes via dnf, clonar repositório GitHub

#### Security Group do RDS

**Ingresso**:
- **PostgreSQL (porta 5432)**: origem `security_groups = [aws_security_group.ec2.id]` (APENAS do security group da EC2, não de CIDR)

**Egresso**:
- Nenhuma regra explícita (AWS cria egresso implícito permitindo respostas a conexões estabelecidas)

## Restrições do AWS Academy Learner Lab

As seguintes restrições são **requisitos não-negociáveis** do ambiente educacional:

1. **Região fixa**: `us-east-1` (única região disponível com créditos suficientes)
2. **Sem recursos IAM**: nenhum `aws_iam_role`, `aws_iam_policy` ou `aws_iam_instance_profile` é criado (o módulo usa `LabInstanceProfile` existente via data source no módulo `compute`)
3. **Sem NAT Gateway**: subnets privadas não têm saída para a internet (custo ~$32/mês, RDS não precisa)
4. **Sem ACM/CloudFront/Route 53**: serviços bloqueados no Learner Lab

## Variáveis de Entrada

| Variável | Tipo | Obrigatória | Descrição |
|----------|------|-------------|-----------|
| `project_name` | `string` | Sim | Nome do projeto para prefixo de recursos |
| `vpc_cidr` | `string` | Sim | CIDR block da VPC (ex: `"10.0.0.0/16"`) |
| `ssh_allowed_cidr` | `string` | Sim | CIDR permitido para SSH na EC2. **Não tem default** (sem valor seguro padrão). **Marcada `sensitive = true`** (contém dado pessoal: IP residencial do operador). **Validação**: recusa `0.0.0.0/0` |

## Outputs Esperados

| Output | Descrição |
|--------|-----------|
| `vpc_id` | ID da VPC criada |
| `public_subnet_id` | ID da primeira subnet pública (compatibilidade com código existente) |
| `public_subnet_ids` | Lista com IDs das **duas** subnets públicas `[1a, 1b]` |
| `private_subnet_ids` | Lista com IDs das duas subnets privadas `[1a, 1b]` para `aws_db_subnet_group` |
| `ec2_security_group_id` | ID do security group da EC2 |
| `rds_security_group_id` | ID do security group do RDS |

## Critérios de Aceitação

- [ ] VPC com `enable_dns_hostnames = true` (teste: conexão EC2 → RDS funciona)
- [ ] Duas subnets públicas em AZs distintas, ambas com IP público automático
- [ ] Duas subnets privadas em AZs distintas (mínimo para `aws_db_subnet_group`)
- [ ] Route table pública associada às **duas** subnets públicas (teste: nslookup/curl de dentro da segunda subnet alcança a internet)
- [ ] Security group da EC2 aceita HTTP de qualquer origem e SSH de CIDR específico
- [ ] Security group do RDS aceita PostgreSQL **apenas do SG da EC2** (não de CIDR)
- [ ] `ssh_allowed_cidr` rejeita `0.0.0.0/0` com erro claro
- [ ] `terraform validate` passa sem erros
- [ ] `terraform plan` mostra `ssh_allowed_cidr = (sensitive value)` nos logs

## Não-Requisitos (Fora do Escopo)

- NAT Gateway para subnets privadas (custo elevado, RDS não precisa)
- IPv6 (avaliação futura)
- VPC Peering ou Transit Gateway
- Network ACLs customizadas (security groups são suficientes)
- VPC Flow Logs (custo adicional, não obrigatório no ambiente educacional)
- Parametrização de AZs (hoje fixas em `us-east-1a` e `us-east-1b`)
- Parametrização de CIDRs das subnets (hoje fixos: `.1.0`, `.2.0`, `.3.0`, `.4.0`)
