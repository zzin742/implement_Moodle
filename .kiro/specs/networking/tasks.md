# Tasks: Módulo Terraform Networking

## Status

✅ Módulo implementado e em produção  
📅 Última atualização: 2024-11-18

## Implementação Concluída

### VPC e DNS

- [x] Criar recurso `aws_vpc.main` com CIDR parametrizado via `var.vpc_cidr`
- [x] Habilitar `enable_dns_hostnames = true` (crítico para resolução do endpoint RDS)
- [x] Habilitar `enable_dns_support = true`
- [x] Adicionar tags com `project_name` para identificação

### Subnets Públicas

- [x] Criar subnet pública em `us-east-1a` com CIDR `10.0.1.0/24`
- [x] Criar subnet pública em `us-east-1b` com CIDR `10.0.4.0/24`
- [x] Configurar `map_public_ip_on_launch = true` em ambas
- [x] Aplicar tags descritivas com AZ no nome

### Subnets Privadas

- [x] Criar subnet privada em `us-east-1a` com CIDR `10.0.2.0/24`
- [x] Criar subnet privada em `us-east-1b` com CIDR `10.0.3.0/24`
- [x] Aplicar tags descritivas com AZ no nome
- [x] Documentar no código que segunda subnet existe para `aws_db_subnet_group`

### Internet Gateway e Roteamento

- [x] Criar `aws_internet_gateway.main` anexado à VPC
- [x] Criar `aws_route_table.public` com rota `0.0.0.0/0 → IGW`
- [x] Associar route table à primeira subnet pública (`us-east-1a`)
- [x] Associar route table à segunda subnet pública (`us-east-1b`) — crítico para evitar subnet sem saída
- [x] Adicionar comentário no código explicando necessidade da segunda associação

### Security Groups

- [x] Criar security group da EC2 com regras de ingresso HTTP (80) e SSH (22)
- [x] Parametrizar origem do SSH via `var.ssh_allowed_cidr`
- [x] Configurar egresso liberado no SG da EC2
- [x] Criar security group do RDS com ingresso PostgreSQL (5432)
- [x] Configurar ingresso do RDS usando `security_groups = [ec2_sg.id]` (não CIDR)
- [x] Documentar no código motivo de usar SG ao invés de CIDR

### Variáveis

- [x] Criar variável `project_name` (string, obrigatória)
- [x] Criar variável `vpc_cidr` (string, obrigatória)
- [x] Criar variável `ssh_allowed_cidr` (string, obrigatória, sem default)
- [x] Adicionar `sensitive = true` em `ssh_allowed_cidr`
- [x] Adicionar validation recusando `0.0.0.0/0` em `ssh_allowed_cidr`
- [x] Documentar no código por que `ssh_allowed_cidr` é sensitive (dado pessoal)

### Outputs

- [x] Exportar `vpc_id`
- [x] Exportar `public_subnet_id` (primeira subnet, compatibilidade com código existente)
- [x] Exportar `public_subnet_ids` (lista com ambas subnets públicas)
- [x] Exportar `private_subnet_ids` (lista para `aws_db_subnet_group`)
- [x] Exportar `ec2_security_group_id`
- [x] Exportar `rds_security_group_id`

### Documentação e Testes

- [x] Adicionar comentários explicativos em recursos críticos (DNS, AZs, associações)
- [x] Adicionar TODOs para trabalho futuro (IPv6, NAT Gateway, parametrização de AZs)
- [x] Validar com `terraform validate`
- [x] Validar com `terraform plan` (verificar que `ssh_allowed_cidr` aparece como `(sensitive value)`)
- [x] Testar conectividade EC2 → RDS após apply (confirmar que DNS resolve)

## Trabalho Futuro (Backlog)

### Parametrização e Flexibilidade

- [ ] Parametrizar Availability Zones via variável `availability_zones` (lista de strings)
  - Adicionar validation garantindo exatamente 2 AZs distintas
  - Adicionar validation garantindo que AZs existem na região (data source `aws_availability_zones`)
  - Atualizar todos os recursos `aws_subnet` para usar `var.availability_zones[0]` e `[1]`
  - Atualizar documentação e `terraform.tfvars.example`

- [ ] Parametrizar CIDRs das subnets via variáveis
  - `public_subnet_cidrs = ["10.0.1.0/24", "10.0.4.0/24"]`
  - `private_subnet_cidrs = ["10.0.2.0/24", "10.0.3.0/24"]`
  - Adicionar validation garantindo CIDRs dentro do VPC CIDR
  - Adicionar validation garantindo CIDRs não sobrepostos

### Alta Disponibilidade e Produção

- [ ] Adicionar NAT Gateway para subnets privadas (quando necessário)
  - Criar `aws_eip` para NAT
  - Criar `aws_nat_gateway` em cada subnet pública
  - Criar route tables privadas com `0.0.0.0/0 → NAT`
  - Documentar custo (~$32/mês por NAT) e justificativa
  - Adicionar flag `enable_nat_gateway` (default false) para controlar criação

- [ ] Adicionar suporte a IPv6 (quando AWS Academy suportar)
  - Solicitar `ipv6_cidr_block` para VPC
  - Adicionar `ipv6_cidr_block` em cada subnet
  - Configurar `assign_ipv6_address_on_creation = true`
  - Atualizar security groups para aceitar regras IPv6

- [ ] Adicionar VPC Flow Logs para auditoria
  - Criar CloudWatch Log Group
  - Criar IAM Role para VPC Flow Logs (quando IAM disponível)
  - Ativar flow logs com `traffic_type = "ALL"`
  - Documentar custo adicional (~$0.50/GB)

### Security e Compliance

- [ ] Adicionar security group para HTTPS quando ACM estiver disponível
  - Duplicar regra HTTP (porta 80) para HTTPS (porta 443)
  - Atualizar outputs para incluir `https_security_group_id`
  - Adicionar TODO comentando que depende de ACM

- [ ] Adicionar Network ACLs customizadas (se compliance exigir)
  - Criar NACL para subnets públicas
  - Criar NACL para subnets privadas
  - Documentar diferença entre NACL (stateless) e Security Groups (stateful)

### Outputs e Integração

- [ ] Adicionar output `public_route_table_id`
  - Permitir anexar rotas customizadas (ex: VPC Peering, Transit Gateway)
  - Documentar uso em comentário

- [ ] Adicionar output `private_route_table_id` (se NAT for implementado)
  - Útil para troubleshooting de conectividade privada

### Testes e Validação

- [ ] Criar testes automatizados para validações de variáveis
  - Testar que `ssh_allowed_cidr = "0.0.0.0/0"` falha
  - Testar que `ssh_allowed_cidr = "203.0.113.45/32"` passa
  - Testar que `ssh_allowed_cidr` sem valor gera erro claro

- [ ] Criar teste de conectividade pós-deploy
  - Script que verifica `nslookup` do endpoint RDS funciona da EC2
  - Script que verifica `curl` da segunda subnet pública alcança internet
  - Script que verifica instância na segunda subnet recebe IP público

## Dependências Externas

Mudanças em outros módulos que impactam este:

- **Módulo `database`**: Se mudar de RDS para Aurora, ainda precisa de `aws_db_subnet_group` (sem mudança aqui)
- **Módulo `compute`**: Se adicionar Auto Scaling Group, vai consumir `public_subnet_ids` (output já existe)
- **Infraestrutura raiz**: Se adicionar ALB, vai precisar de `public_subnet_ids` (output já existe)

## Notas de Manutenção

- **Atenção ao mudar AZs**: Subnets não podem mudar de AZ — mudança força destruição e recriação (downtime)
- **Atenção ao mudar CIDRs**: Subnets não podem mudar CIDR — mudança força destruição e recriação (downtime)
- **Credenciais AWS expiram em 4h**: Learner Lab — sempre `terraform destroy` ao fim da sessão
- **Validação de `ssh_allowed_cidr`**: Erro intencional — força operador a pensar em segurança
- **`sensitive = true` em `ssh_allowed_cidr`**: Privacidade, não segurança — IP é dado pessoal
