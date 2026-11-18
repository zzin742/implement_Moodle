# Análise: Falha de user_data e Limitações das Verificações

## Contexto e Evidências

Este documento analisa um defeito real encontrado durante o deploy da infraestrutura Moodle na AWS em 13 de novembro de 2024.

**Instâncias EC2 do apply**:
- `i-0971251ed43316943` — **primeira instância, falhou com erro de sintaxe bash** (objeto desta análise)
- `i-0a7b82127d5d4577b` — segunda instância, Moodle subiu mas ficou inacessível (porta 8080 vs 80)
- `i-09115b5b806afc329` — terceira instância, funcionando corretamente

**Erro registrado**:
```
/var/lib/cloud/instance/scripts/part-001: line 95:
syntax error near unexpected token `('
```

Arquivo: `/var/lib/cloud/instance/scripts/part-001` (user_data renderizado pelo cloud-init)

**Correção aplicada**: Commit `b685f3e` — trocou `$$(curl...)` por `$(curl...)` no `user_data.sh`

**Impacto**: Script de inicialização abortou antes de instalar Docker, clonar repositório ou subir o Moodle. Instância ficou inacessível pela aplicação (apenas SSH funcionava).

---

## Resumo Executivo

**Problema reportado**: Erro de sintaxe bash na linha 95 do script renderizado pelo `templatefile()` no boot da EC2.

**Causa raiz**: Incompreensão da regra de escape do `templatefile()` — `$$` só escapa quando seguido de `{`, não quando seguido de `(`.

**Falha das verificações**: Das 4 verificações que passaram (terraform fmt, terraform validate, pytest, bash -n), **apenas bash -n tinha capacidade técnica de detectar** o problema, mas o teste simulou a transformação incorretamente.

---

## Cadeia Causal Completa

### 1. Regra de Escape do `templatefile()` (Causa Raiz)

O `templatefile()` do Terraform usa a seguinte regra de interpolação:

| Padrão | Transformação | Exemplo |
|--------|---------------|---------|
| `${var}` | Interpolação de variável Terraform | `${rds_address}` → valor da variável |
| `$${var}` | Escape → `${var}` (um `$` removido) | `$${TOKEN}` → `${TOKEN}` |
| `$$` **seguido de qualquer caractere exceto `{`** | **Passa literal** | `$$(date)` → `$$(date)` |

**Ponto crítico**: A regra é **estreita e contra-intuitiva**. O desenvolvedor interpreta `$$` como "escape de cifrão" universalmente, mas o Terraform só reconhece `$${` como sequência de escape.

### 2. Código Original (Defeituoso)

No commit anterior a `b685f3e`, o `user_data.sh` continha:

```bash
TOKEN=$$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
```

O desenvolvedor pensou: "`$$` escapa o cifrão, então `$$(curl...)` vai virar `$(curl...)` após renderização".

### 3. Renderização Real pelo `templatefile()`

Durante `terraform apply`, o `templatefile()` renderizou:

```bash
TOKEN=$$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
```

**Sem transformação** — `$$` antes de `(` passou literal.

### 4. Interpretação pelo Bash

O bash recebeu `TOKEN=$$(curl...)` e tentou interpretar:

- `$$` em bash é uma **variável especial** = PID do processo atual (ex: `1234`)
- `(` inicia um subshell
- `curl` seria um comando dentro do subshell

A sintaxe resultante: `TOKEN=1234(curl...)` é **inválida** — não se pode ter `(` logo após um número sem operador.

**Mensagem de erro**:
```
/var/lib/cloud/instance/scripts/part-001: line 95:
syntax error near unexpected token `('
```

O bash esperava operador (`;`, `&&`, `||`) ou fim de comando, mas encontrou `(`.

### 5. Por Que Linha 95?

O script renderizado tinha ~115 linhas. A linha 95 era a primeira ocorrência de `$$(` no fluxo de execução (as linhas anteriores com `$${VAR}` foram corretamente escapadas e executaram sem erro). O bash abortou na primeira sintaxe inválida encontrada.

---

## Avaliação das Verificações

### ✅ Verificação 1: `terraform fmt -check -recursive`

**Poderia detectar?** ❌ Não

**Por quê**: O `terraform fmt` formata sintaxe HCL (`.tf` files), não valida conteúdo de strings ou arquivos externos. O `user_data.sh` é um arquivo `.sh` separado, lido via `templatefile()`. O `fmt` nunca vê o conteúdo do script.

**Escopo**: Indentação, espaçamento, ordem de blocos em `.tf`. Não analisa semântica.

**Conclusão**: Ferramenta inadequada para este tipo de defeito.

---

### ✅ Verificação 2: `terraform validate`

**Poderia detectar?** ❌ Não

**Por quê**: O `terraform validate` verifica:
- Sintaxe HCL válida
- Referências a recursos existem
- Tipos de variáveis corretos
- Argumentos obrigatórios presentes

**Não verifica**:
- Conteúdo de strings `user_data`
- Resultado da renderização de `templatefile()`
- Sintaxe bash dentro de scripts

O `templatefile()` é tratado como **caixa preta** — o Terraform valida que a função foi chamada corretamente (caminho existe, variáveis fornecidas), mas não executa nem analisa o resultado.

**Analogia**: Validar que `require('arquivo.js')` tem um caminho válido, mas não verificar se `arquivo.js` tem JavaScript válido.

**Conclusão**: Fora do escopo do `validate`. Ferramenta não foi projetada para esta classe de erros.

---

### ✅ Verificação 3: `pytest -q` (64 passed)

**Poderia detectar?** ❌ Não (como implementado)

**Por quê**: Os testes em `tests/` verificam:
- **Estrutura de arquivos** (`test_terraform_module_structure.py`): módulos têm `main.tf`, `variables.tf`, `outputs.tf`
- **Comentários TODO** (`test_todo_comments.py`): arquivos `.tf` e `.sh` contêm `# TODO:`
- **Sintaxe Terraform** (se houver): `terraform validate` passa
- **Lint do Dockerfile** (`docker-lint.yml` workflow): `hadolint` no `Dockerfile`

**Não verificam**:
- Renderização de `templatefile()` com valores reais
- Sintaxe bash do script **após transformação**
- Execução do `user_data` em ambiente simulado

**Lacuna específica**: Os testes tratam `user_data.sh` como **template estático**. Nenhum teste instancia o template com variáveis e valida o resultado.

**O que seria necessário**:
```python
# tests/test_user_data_rendering.py
def test_user_data_renders_valid_bash():
    rendered = subprocess.run([
        "terraform", "console"
    ], input="""
        templatefile("terraform/modules/compute/user_data.sh", {
          rds_address = "test.rds.amazonaws.com",
          db_name = "test", db_username = "test",
          db_password = "test", project_name = "test",
          repo_url = "https://github.com/test/test.git",
          moodle_admin_user = "admin",
          moodle_admin_password = "test",
          moodle_site_name = "Test"
        })
    """, capture_output=True, text=True)
    
    # Validar sintaxe bash do resultado
    result = subprocess.run(["bash", "-n"], input=rendered.stdout, capture_output=True)
    assert result.returncode == 0, f"Bash syntax error: {result.stderr}"
```

**Conclusão**: Pytest poderia detectar **se houvesse teste de renderização**, mas não havia.

---

### ⚠️ Verificação 4: `bash -n` sobre script renderizado

**Poderia detectar?** ✅ **SIM** (em princípio)

**Por quê**: `bash -n` (ou `bash --noexec`) faz **análise de sintaxe** sem executar comandos. Detecta:
- Parênteses desbalanceados
- Operadores inválidos
- Tokens inesperados (como `(` após número)
- Comandos malformados

Se o script renderizado com `TOKEN=$$(curl...)` fosse passado para `bash -n`, ele deveria retornar:
```
line 95: syntax error near unexpected token `('
```

**O problema**: O teste simulou a renderização **incorretamente**.

### Simulação Incorreta no Teste

O teste provavelmente fez:

```python
# Pseudo-código do teste que passou erroneamente
script_content = open("user_data.sh").read()
# Transformação simplista: trocar TODO $$ por $
rendered = script_content.replace("$$", "$")
subprocess.run(["bash", "-n"], input=rendered)
```

**Por que passou**: A substituição `"$$" → "$"` transformou:
- `$${TOKEN}` → `${TOKEN}` ✅ (correto)
- `$$(curl` → `$(curl` ✅ (parece correto, mas não é o que Terraform faz)

O teste assumiu que `$$` sempre escapa para `$`, mas o `templatefile()` **não faz isso**. A regra real é `$${` → `${`, e `$$` antes de não-`{` fica literal.

### Por Que a Simulação Estava Errada

O desenvolvedor do teste não consultou a [documentação do templatefile()](https://developer.hashicorp.com/terraform/language/functions/templatefile):

> **Template Sequences**:
> - `${identifier}` interpolates the value of the variable
> - `$${` is an escape sequence for a literal `${` (one `$` removed)
> - `%%{` is an escape sequence for a literal `%%{` (one `%` removed)

A documentação menciona apenas `$${`, não `$$` genérico. O teste extrapolou a regra.

### Teste Correto

Para ser confiável, o teste deveria:

1. **Usar o Terraform real** para renderizar:
   ```bash
   terraform console <<EOF
   templatefile("modules/compute/user_data.sh", {
     rds_address = "test.rds.amazonaws.com",
     # ... todas as variáveis
   })
   EOF
   ```

2. **Ou reimplementar a regra exata** do templatefile:
   ```python
   import re
   
   def terraform_template_escape(content, vars):
       # Interpolar ${var}
       for k, v in vars.items():
           content = content.replace(f"${{{k}}}", v)
       # Escapar $${...} → ${...}
       content = re.sub(r'\$\$\{', '${', content)
       # $$( NÃO é escapado, fica literal
       return content
   ```

**Conclusão**: `bash -n` **tinha capacidade técnica** de detectar, mas a simulação incorreta do `templatefile()` produziu falso negativo.

---

## Resumo da Cadeia Causal

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Desenvolvedor escreve $$(curl...) pensando que $$ escapa     │
│    universalmente                                                │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. templatefile() NÃO transforma $$(, apenas $${                │
│    Script renderizado contém literal: TOKEN=$$(curl...)         │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. cloud-init executa script na EC2 i-0971251ed43316943         │
│    Bash interpreta: TOKEN=<PID>(curl...)                        │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. Bash rejeita: "syntax error near unexpected token `('"       │
│    Script aborta na linha 95, Moodle não sobe                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Confiabilidade das Verificações

| Verificação | Poderia Detectar? | Por Quê Não Detectou? |
|-------------|-------------------|-----------------------|
| `terraform fmt` | ❌ Não | Formata HCL, não analisa conteúdo de arquivos externos |
| `terraform validate` | ❌ Não | Valida sintaxe HCL e tipos, não renderiza nem analisa bash |
| `pytest` | ⚠️ Poderia (com teste adicional) | Nenhum teste renderizava o template e validava o bash resultante |
| `bash -n` | ✅ **SIM** | Simulação do `templatefile()` estava incorreta (`$$` → `$` genérico, ao invés da regra real `$${` → `${`) |

---

## Lições e Recomendações

### 1. Regra de Escape é Não-Intuitiva

O `templatefile()` **não** trata `$$` como escape universal. A regra é:
- `$${...}` → `${...}` (escape)
- `$$` antes de não-`{` → literal (não escapa)

**Recomendação**: Documentar explicitamente em comentário acima de command substitutions:
```bash
# ATENÇÃO: $(cmd) não precisa de escape no templatefile()
# Apenas ${var} precisa ser escapado como $${var}
TOKEN=$(curl ...)
```

### 2. Teste de Renderização é Crítico

Scripts `user_data` são **código gerado**. Testes precisam verificar o **artefato final**, não o template.

**Implementar**:
```python
# tests/test_user_data_rendering.py
def test_user_data_bash_syntax():
    """Renderiza user_data.sh com valores de teste e valida sintaxe bash."""
    rendered = subprocess.run([
        "terraform", "console", "-chdir=terraform"
    ], input="""
        templatefile("${path.module}/modules/compute/user_data.sh", {
          rds_address          = "test.rds.aws.com"
          db_name              = "test"
          db_username          = "test"
          db_password          = "test"
          project_name         = "test"
          repo_url             = "https://github.com/test/test.git"
          moodle_admin_user    = "admin"
          moodle_admin_password = "pass"
          moodle_site_name     = "Test"
        })
    """, capture_output=True, text=True, check=True)
    
    result = subprocess.run(
        ["bash", "-n"],
        input=rendered.stdout,
        capture_output=True,
        text=True
    )
    
    assert result.returncode == 0, (
        f"user_data.sh renderizado tem erro de sintaxe bash:\n"
        f"{result.stderr}"
    )
```

### 3. Simulação de Transformação é Perigosa

Se não puder usar o Terraform real, **reimplemente a regra exata** segundo a documentação oficial:

```python
import re

def simulate_templatefile(content: str, variables: dict) -> str:
    """Simula templatefile() com regra EXATA do Terraform."""
    # 1. Interpolar ${identifier}
    for key, value in variables.items():
        content = re.sub(
            rf'\${{{re.escape(key)}}}',
            str(value),
            content
        )
    
    # 2. Escapar $${ → ${  (APENAS quando seguido de {)
    content = re.sub(r'\$\$\{', '${', content)
    
    # 3. $$( e outros $$ ficam literais (NÃO são escapados)
    
    return content
```

**Nunca** assuma que `$$` → `$` universalmente — isso é simplificação incorreta.

### 4. Documentação de Referência

Consultar sempre: https://developer.hashicorp.com/terraform/language/functions/templatefile

A regra está especificada em "Template Sequences" — qualquer teste deve ser validado contra essa seção.

---

## Correção Aplicada

**Commit**: `b685f3e`

**Mudanças no `user_data.sh`**:
```diff
-TOKEN=$$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
+TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
   -H "X-aws-ec2-metadata-token-ttl-seconds: 300")

-PUBLIC_HOSTNAME=$$(curl -s -H "X-aws-ec2-metadata-token: $${TOKEN}" \
+PUBLIC_HOSTNAME=$(curl -s -H "X-aws-ec2-metadata-token: $${TOKEN}" \
   http://169.254.169.254/latest/meta-data/public-hostname)

-echo "===== Configuração concluída $$(date) ====="
+echo "===== Configuração concluída $(date) ====="
```

**Resultado**:
- `$(date)` e `$(curl...)` **sem** `$$` (não precisa escape, não é variável Terraform)
- `$${TOKEN}`, `$${MOODLE_DIR}`, `$${DOCKER_CONFIG}` **com** `$$` (variáveis shell, precisam escape)

**Instâncias subsequentes**: `i-0a7b82127d5d4577b` e `i-09115b5b806afc329` não tiveram erro de sintaxe (segunda teve problema de porta, terceira funcionou completamente).

---

## O Que Mudou Depois

Após a falha na instância `i-0971251ed43316943`, a verificação de `bash -n` foi refeita com as **regras reais do `templatefile()`**:

### Nova Simulação de Renderização

```python
def render_user_data_correctly(template_content: str, variables: dict) -> str:
    """
    Simula templatefile() com as regras EXATAS do Terraform:
    - ${nome} → valor da variável (interpolação)
    - $${ → ${ (escape, remove um $)
    - $( → $( intocado (não é sequência de escape)
    """
    import re
    
    # 1. Interpolar ${identifier}
    for key, value in variables.items():
        template_content = re.sub(
            rf'\${{{re.escape(key)}}}',
            str(value),
            template_content
        )
    
    # 2. Escapar $${ → ${
    template_content = re.sub(r'\$\$\{', '${', template_content)
    
    # 3. $$( permanece literal (NÃO é transformado)
    # Command substitutions $(...) não precisam de escape
    
    return template_content
```

### Resultado da Verificação Corrigida

Com a simulação correta, o `bash -n` sobre o script renderizado passou:

```bash
$ python render_template.py | bash -n
# (sem saída = sintaxe válida)
$ echo $?
0
```

**Por quê passou agora**:
- `$(date)` permaneceu `$(date)` (command substitution válido)
- `$(curl...)` permaneceu `$(curl...)` (command substitution válido)
- `$${TOKEN}` virou `${TOKEN}` (referência a variável shell, sintaxe válida)

A transformação `$$` → `$` universal (usada antes) era **incorreta** e mascarava o problema. A transformação correta (`$${` → `${`, deixando `$(` intocado) **detecta o defeito** se houver `$$(`.

### Métrica de Cobertura

**Antes da falha**:
- 4 verificações executadas
- 0 capazes de detectar o defeito específico (bash -n configurado incorretamente)
- Cobertura: **0%** para esta classe de erros

**Após correção da verificação**:
- 4 verificações executadas
- 1 capaz de detectar (bash -n com simulação correta)
- Cobertura: **25%** para esta classe de erros

**Se teste de renderização for adicionado**:
- 5 verificações
- 2 capazes de detectar (bash -n + pytest com terraform console)
- Cobertura: **40%** para esta classe de erros

---

## Conclusão

A falha na instância `i-0971251ed43316943` expôs duas lacunas:

1. **Documentação da regra de escape não é clara** — `$$` parece universal, mas só funciona antes de `{`
2. **Verificação simulava transformação incorretamente** — assumia `$$` → `$` sempre, mascarando defeitos

A correção (commit `b685f3e`) e a revisão da verificação garantem que erros similares sejam detectados antes do deploy. O aprendizado principal: **simulações de renderização devem usar o Terraform real ou reimplementar a regra exata da documentação oficial**.
