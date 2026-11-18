# Design: Módulo Terraform Networking

## Visão Geral

O módulo `networking` provisiona uma VPC de duas camadas (pública e privada) em duas AZs, seguindo o padrão de arquitetura AWS para aplicações web com banco de dados isolado. A topologia é otimizada para o ambiente educacional do AWS Academy Learner Lab, balanceando segurança, custo e preparação para evolução futura.

## Decisões de Design

### 1. `enable_dns_hostnames = true` na VPC

**Decisão**: VPC configurada com `enable_dns_hostnames = true` e `enable_dns_support = true`.

**Por quê**: O endpoint do RDS retornado pelo Terraform é um nome DNS (ex: `moodle-db.cxu6ck2o0hwz.us-east-1.rds.amazonaws.com`), não um endereço IP. Sem resolução DNS habilitada na VPC, a EC2 recebe o endpoint mas `getent hosts` retorna vazio — a string do hostname não resolve para IP, e a conexão PostgreSQL falha com `could not translate host name to address`. O erro resultante não aponta para a VPC, levando a troubleshooting na direção errada (credenciais, security groups, etc.).

`enable_dns_support` sozinho não basta: ele ativa o resolvedor DNS em `169.254.169.254`, mas sem `enable_dns_hostnames` as instâncias não recebem nomes DNS privados e recursos como RDS não são alcançáveis por hostname.

### 2. Duas AZs nas subnets privadas

**Decisão**: Subnets privadas `10.0.2.0/24` (us-east-1a) e `10.0.3.0/24` (us-east-1b).

**Por quê**: O recurso `aws_db_subnet_group` (usado no módulo `database`) recusa criação com uma única AZ — a API retorna erro `DBSubnetGroupDoesNotCoverEnoughAZs`. A AWS exige mínimo de duas AZs distintas no subnet group, mesmo com `multi_az = false` (sem standby).

Não há instância RDS rodando em `us-east-1b` — ela consome recursos apenas em `us-east-1a`. A segunda subnet existe unicamente para satisfazer a validação da API do RDS. Tentar economizar removendo-a causaria falha no `terraform apply` após VPC e IGW já criados (órfãos consumindo crédito).

### 3. Duas AZs nas subnets públicas

**Decisão**: Subnets públicas `10.0.1.0/24` (us-east-1a) e `10.0.4.0/24` (us-east-1b).

**Por quê**: Hoje nada roda em `us-east-1b` — a EC2 única fica em `us-east-1a`. A segunda subnet existe porque **subnet pública numa AZ só é ponto único de falha estrutural**. Qualquer evolução para alta disponibilidade (Application Load Balancer, Auto Scaling Group) exige no mínimo duas AZs, e a API da AWS recusa criar esses recursos com uma só.

Criar a segunda subnet agora transforma essa evolução em mudança de uma linha (lançar instâncias em ambas), ao invés de refatoração de rede (criar subnet → atualizar route tables → migrar recursos → testar failover). Custo adicional: zero (subnet vazia não cobra).

Escolha de CIDR `10.0.4.0/24` (não `.5.0` ou sequencial): deixa espaço entre `.3.0` (última privada) e `.4.0` para inserir subnets intermediárias futuras sem renumerar.

### 4. Associação explícita da segunda subnet pública à route table

**Decisão**: Recurso `aws_route_table_association.public_1b` associa explicitamente `aws_subnet.public_1b` à `aws_route_table.public`.

**Por quê**: Sem essa associação, a subnet `10.0.4.0/24` herdaria a **route table principal** da VPC, que contém apenas a rota local (`10.0.0.0/16 → local`). Seria uma subnet "pública" (tag, IP público automático) **sem saída para a internet** — comportamento silencioso e confuso.

O erro só apareceria no dia em que algo fosse lançado nela: instância com IP público mas sem conectividade, `curl google.com` timeout, `dnf update` falhando. O troubleshooting apontaria para security groups ou DNS, não para a route table esquecida.

Terraform não avisa sobre subnet sem rota para IGW — é responsabilidade do operador associar explicitamente. A primeira subnet (`public`) tem associação óbvia; a segunda precisa da mesma, não é automática.

### 5. Sem NAT Gateway

**Decisão**: Subnets privadas não têm NAT Gateway — nenhuma rota para `0.0.0.0/0`.

**Por quê**: NAT Gateway custa aproximadamente **$32/mês** ($0.045/hora × 730 horas + $0.045 por GB processado). No contexto do AWS Academy Learner Lab, isso consome **32% do orçamento educacional de $100** em um único mês.

O RDS não precisa de conectividade de saída: ele não baixa patches (gerenciado pela AWS), não faz chamadas API externas, não envia logs para fora da VPC. Todo o tráfego é **inbound** da EC2 (queries PostgreSQL). Um NAT Gateway resolveria um problema que não existe, enquanto custaria mais que a própria instância RDS ($14.71/mês).

Em produção real, NAT seria necessário apenas se: (1) RDS com Lambda que precisa chamar APIs externas, (2) Aurora Serverless que precisa acessar S3, ou (3) compliance exigir patch manual via internet. Nenhum se aplica aqui.

### 6. Regra do SG do RDS por `security_groups`, não por CIDR

**Decisão**: Ingresso do RDS usa `security_groups = [aws_security_group.ec2.id]`, não `cidr_blocks = ["10.0.1.x/32"]`.

**Por quê**: O IP privado da EC2 (ex: `10.0.1.50`) é **alocado dinamicamente** pela subnet — não é fixo. Se a instância for destruída e recriada (ex.: mudança no `user_data` com `user_data_replace_on_change = true`), ela recebe um IP privado diferente (ex: `10.0.1.73`).

Uma regra baseada em CIDR (`10.0.1.50/32`) deixaria de funcionar **silenciosamente** após a recriação: RDS rejeitaria conexões com `no pg_hba.conf entry`, e o operador suspeitaria de credenciais ou DNS, não da regra de security group que "sempre funcionou".

Referenciar o **security group** (`aws_security_group.ec2.id`) mantém a conectividade independente do IP: qualquer instância com aquele SG pode conectar. É a prática recomendada da AWS para comunicação intra-VPC.

### 7. `ssh_allowed_cidr` sem default e com validation recusando `0.0.0.0/0`

**Decisão**: Variável `ssh_allowed_cidr` declarada **sem `default`** e com bloco `validation` que recusa `"0.0.0.0/0"`.

**Por quê**: Não existe **valor seguro de default** para acesso SSH. Um default de `0.0.0.0/0` abre a porta 22 para a internet inteira em qualquer `terraform apply` que não passe `terraform.tfvars` — cenário comum em CI/CD ou deploys automatizados.

Sem default, o Terraform falha cedo com `Error: Missing required variable` se `ssh_allowed_cidr` não for fornecida. O operador é **forçado a pensar** no valor correto (seu IP com `/32`) antes do apply, ao invés de subir infraestrutura exposta e descobrir pelo scan de port scanner.

A validação recusa `0.0.0.0/0` com mensagem explicativa: `"SSH access from 0.0.0.0/0 (internet inteira) é proibido por segurança. Especifique seu IP público (ex: \"203.0.113.45/32\"). Descubra seu IP com: curl -s https://checkip.amazonaws.com"`. Isso previne erro consciente (operador sabe que é inseguro mas "é só teste") com orientação clara.

### 8. `ssh_allowed_cidr` marcada como `sensitive = true`

**Decisão**: Variável `ssh_allowed_cidr` tem atributo `sensitive = true`.

**Por quê**: O valor não é um **segredo criptográfico** (não é senha, chave privada ou token), mas é **dado pessoal** segundo LGPD/GDPR: o IP residencial ou corporativo do operador com máscara `/32` revela localização física de onde ele trabalha.

Em repositório público, o workflow `terraform-plan.yml` publica `terraform show tfplan` no `GITHUB_STEP_SUMMARY` (visível na aba Actions para qualquer visitante). Variáveis não-sensitive aparecem em texto claro no plano: `cidr_blocks = ["203.0.113.45/32"]`. Isso equivale a **doxxing involuntário**.

Com `sensitive = true`, o Terraform oculta o valor nos logs e plans: `cidr_blocks = (sensitive value)`. O IP do operador nunca vaza em logs públicos, mesmo com repositório aberto e CI rodando.

`sensitive` não impede uso da variável (regra de security group é criada normalmente), apenas mascara nos outputs.

### 9. CIDRs das subnets fixos no código

**Decisão**: CIDRs `10.0.1.0/24`, `10.0.2.0/24`, `10.0.3.0/24`, `10.0.4.0/24` hardcoded no `main.tf`.

**Por quê**: Parametrizar CIDRs (`var.public_subnet_1_cidr`, etc.) adiciona 4 variáveis sem benefício claro no contexto educacional. O VPC CIDR (`10.0.0.0/16`) já é parametrizado; subdividir em `/24` é matemática simples e raramente muda.

Tradeoff: menos flexibilidade vs menos variáveis para documentar/validar/preencher em `terraform.tfvars`. Em produção multi-ambiente (dev/staging/prod), parametrizar CIDRs faz sentido para evitar overlap de VPC peering. No Learner Lab (ambiente único, VPC efêmera), o custo de complexidade não compensa.

Valores escolhidos (`10.0.X.0/24`): múltiplos de 1 (não aleatórios), deixam gaps para inserção futura (`.5.0`, `.6.0` disponíveis).

### 10. AZs fixas em `us-east-1a` e `us-east-1b`

**Decisão**: Availability zones hardcoded como `"us-east-1a"` e `"us-east-1b"` no código.

**Por quê**: Parametrizar AZs (`var.availability_zones = ["us-east-1a", "us-east-1b"]`) exige validação complexa (garantir duas AZs distintas, ambas válidas na região, não repetidas) e torna `terraform.tfvars` mais verboso.

No AWS Academy Learner Lab, a região é **fixa em `us-east-1`** (única com créditos suficientes). Não há deploy multi-região. As AZs `-1a` e `-1b` existem em todas as contas AWS há anos (não são removidas). O risco de mudança é zero no horizonte do desafio educacional.

Tradeoff: código menos portável (mudar para `us-west-2` exige edit manual) vs menos variáveis e validações. Em infraestrutura multi-região de produção, parametrizar AZs é obrigatório. No escopo deste desafio, rigidez é aceitável.

## Diagrama de Arquitetura

```
┌─────────────────────────────────────────────────────────────────────┐
│ VPC 10.0.0.0/16                                                     │
│ enable_dns_hostnames=true, enable_dns_support=true                  │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ Internet Gateway                                             │   │
│  └──────────────────────┬──────────────────────────────────────┘   │
│                         │                                            │
│  ┌──────────────────────▼──────────────────────────────────────┐   │
│  │ Route Table Pública: 0.0.0.0/0 → IGW                        │   │
│  └──────────┬───────────────────────────────────────┬──────────┘   │
│             │                                        │               │
│  ┌──────────▼──────────────┐          ┌────────────▼──────────┐   │
│  │ Subnet Pública (1a)      │          │ Subnet Pública (1b)   │   │
│  │ 10.0.1.0/24              │          │ 10.0.4.0/24           │   │
│  │ us-east-1a               │          │ us-east-1b            │   │
│  │ map_public_ip=true       │          │ map_public_ip=true    │   │
│  │                          │          │                       │   │
│  │  ┌─────────────────┐    │          │  (vazia, preparada    │   │
│  │  │ EC2 Moodle       │    │          │   para ALB/ASG)       │   │
│  │  │ SG: HTTP, SSH    │    │          │                       │   │
│  │  └─────────────────┘    │          └───────────────────────┘   │
│  └─────────────────────────┘                                       │
│                                                                       │
│  ┌──────────────────────────┐          ┌───────────────────────┐   │
│  │ Subnet Privada (1a)       │          │ Subnet Privada (1b)   │   │
│  │ 10.0.2.0/24               │          │ 10.0.3.0/24           │   │
│  │ us-east-1a                │          │ us-east-1b            │   │
│  │ (sem rota para IGW)       │          │ (sem rota para IGW)   │   │
│  │                           │          │                       │   │
│  │  ┌──────────────────┐    │          │  (vazia, exigida pelo │   │
│  │  │ RDS PostgreSQL    │    │          │   aws_db_subnet_group)│   │
│  │  │ SG: 5432 do SG EC2│    │          │                       │   │
│  │  └──────────────────┘    │          └───────────────────────┘   │
│  └──────────────────────────┘                                       │
│                                                                       │
└───────────────────────────────────────────────────────────────────┘
```

## Dependências Entre Recursos

Ordem de criação (respeitada pelo Terraform automaticamente via referências):

1. `aws_vpc.main` (nenhuma dependência)
2. `aws_subnet.*` (depende de `vpc.id`)
3. `aws_internet_gateway.main` (depende de `vpc.id`)
4. `aws_route_table.public` (depende de `vpc.id` e `igw.id`)
5. `aws_route_table_association.*` (depende de `subnet.id` e `route_table.id`)
6. `aws_security_group.ec2` e `aws_security_group.rds` (depende de `vpc.id`)
   - SG do RDS referencia SG da EC2, criando dependência implícita

## Tradeoffs e Limitações Conhecidas

| Decisão | Benefício | Custo | Justificativa |
|---------|-----------|-------|---------------|
| Sem NAT Gateway | Economia de $32/mês | Subnets privadas sem saída | RDS não precisa de conectividade externa |
| AZs fixas em código | Menos variáveis, validação mais simples | Código não é multi-região | Learner Lab só opera em us-east-1 |
| CIDRs fixos | Menos variáveis para gerenciar | Menos flexível para overlap | Ambiente único, sem peering |
| Segunda subnet pública vazia | Preparação para HA futuro | Nenhum (subnet vazia é gratuita) | Evolução para ALB/ASG vira mudança de 1 linha |
| `ssh_allowed_cidr` sem default | Força decisão consciente sobre segurança | Operador precisa consultar próprio IP | Previne expor SSH para 0.0.0.0/0 acidentalmente |

## Evolução Futura

Mudanças esperadas conforme o projeto evolui:

1. **Parametrizar AZs** (em `variables.tf`): permitir deploy em outras regiões sem editar `main.tf`
2. **Adicionar NAT Gateway** (em produção): se RDS precisar chamar APIs externas (ex: Lambda + RDS Proxy)
3. **Security group HTTPS** (quando ACM disponível): duplicar regra HTTP para porta 443
4. **Route table IDs nos outputs** (se routing customizado for necessário): expor `aws_route_table.public.id` para anexar rotas adicionais
5. **Parametrizar CIDRs das subnets** (em ambientes multi-VPC): evitar overlaps em VPC peering
6. **IPv6** (quando AWS Academy suportar): adicionar `ipv6_cidr_block` e `assign_ipv6_address_on_creation`
7. **VPC Flow Logs** (em produção): auditar tráfego de rede para troubleshooting e compliance
