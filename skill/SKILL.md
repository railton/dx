---
name: dx
description: >-
  Ferramenta CLI global `dx` que reduz tokens de output. Use para: consultar
  PostgreSQL local OU remoto (via SSH→docker exec) em vez de `docker exec psql`
  cru ou MCP; buscar nome de tabela/coluna no schema antes de escrever a query;
  rodar o console do framework (migrations, cache, filas) sem `docker exec`
  manual; ler o log do app sem o ruído de stack trace de dependências; puxar
  work items do Azure DevOps (Bug/Task/chamado) já em texto limpo, com
  anexos/prints; e rodar comandos/logs por SSH com ruído filtrado. Dispara ao
  consultar banco de dados, rodar migration/limpar cache/mexer em filas,
  investigar erro ou exceção no log da aplicação, abrir um chamado/work item/
  ticket do Azure DevOps, ou coletar logs de um servidor remoto.
---

# dx — dev-exec wrapper

`dx` é um comando global (em `~/.local/bin/dx`) que corta o output verboso de
PostgreSQL, SSH e Azure DevOps, preservando o sinal. Resolve config a partir do
**projeto atual** (bloco `DX_*` no `.env` do git-root do CWD).

Antes de detalhes, rode `dx --help` (e veja o `EXAMPLE.md` no repositório do dx).

## Quando usar

- **Consultar o banco** → `dx pg "<query>"` em vez de `docker exec … psql` cru
  (economiza 50–90% de tokens: TSV nativo, dedup, amostragem head/tail). Nunca use
  ferramenta MCP para o banco.
- **Banco remoto** (troubleshooting em outro servidor) → `dx pg --host user@srv "<query>"`
  (roda o psql via `ssh → docker exec -i`, query por stdin). Ou fixe `DX_PG_SSH` na config do projeto.
- **Chamado / work item do Azure DevOps** → `dx wi <id>` (traz campos, repro, comentários
  e baixa os prints inline automaticamente).
- **Logs / comandos num servidor** → `dx ssh <host> "<comando>"` (remove timestamp/host/PID + dedup).
- **Console do framework** (migrations, cache, filas) → `dx yii <cmd>` em vez de `docker exec … ./yii`.
- **Log do app** (erro/exceção) → `dx logs` (colapsa stack de dependências, mantém frames do projeto).
- **Não lembra o nome da tabela/coluna?** → `dx pg --find <termo>` **antes** de escrever a query.

## PostgreSQL (`dx pg`)

```bash
dx pg "SELECT id, nome FROM cliente WHERE id = 1"     # auto-LIMIT 100
dx pg --full "<query>"                                # sem auto-LIMIT
dx pg --describe <tabela>                             # \d (TSV)
dx pg --list-tables                                   # \dt (TSV)
dx pg --explain "<query>"                             # EXPLAIN resumido (nó top, custo, tempo)
dx pg --host user@srv "<query>"                       # psql remoto via SSH→docker exec
dx pg --find <termo>                                  # busca tabela/coluna no schema
```

## Framework e logs (`dx yii` / `dx logs`)

```bash
dx yii migrate                    # console Yii no container do app
dx yii migrate --interactive=0    # sem prompt (agentes/scripts)
dx yii cache/flush-all
dx logs -n 200                    # log com stack de dependências colapsada
dx logs --errors                  # só entradas [error]
```

Container/log vêm da config do projeto (`DX_APP_CONTAINER`, `DX_LOG_PATH`) — funciona
em qualquer projeto Yii. Em `dx logs`, os frames do **projeto** são preservados de
propósito: são eles que apontam onde está o bug.

**`dx yii` e `dx logs` são LOCAIS** — não existe `--host`. Se pedirem console ou log de
outro servidor, use `dx ssh <host> "<comando>"`; não finja que `dx yii` alcança o remoto.

Regras: valide `Model::tableName()` e colunas antes de afirmar; o modo remoto **não**
corrompe datas (não aplica o strip do ssh). Fallback cru: `dx --raw pg …`.

## Banco remoto / outro ambiente — NÃO ASSUMIR A CONFIG LOCAL

`--host` troca **só a máquina**. Container, usuário e banco continuam vindo do `.env`
local: o comando é `ssh <host> 'docker exec -i <DX_PG_CONTAINER> psql -U <DX_PG_USER>
-d <DX_PG_DB>'`. Um servidor pode hospedar vários ambientes (dev/hml/staging), e o `dx`
não inspeciona o host — se existir container de mesmo nome de OUTRO ambiente, a query
roda no lugar errado **sem aviso**.

Ao receber "veja X no banco de hml/staging/produção":

1. **Descubra o alvo real, não deduza:** `dx ssh <host> "docker ps --format '{{.Names}}'"`.
2. **Aponte explicitamente**, sobrescrevendo por comando (o export vence o `.env` e não
   altera a config local):
   ```bash
   DX_PG_CONTAINER=<container> DX_PG_DB=<banco> dx pg --host <host> "SELECT ..."
   ```
   Se o banco for derivado (`DX_PG_DB=${POSTGRES_DB}`), basta a variável de ambiente do
   projeto (ex.: `APP_ENV=hml`) que o nome acompanha.
3. **Confirme antes de rodar:** mostre ao usuário host + container + banco resolvidos
   (`dx config` com as mesmas variáveis na frente) e só então execute. Ambiente
   compartilhado não é lugar de tentativa e erro.
4. **Escrita (`UPDATE`/`DELETE`/DDL) exige autorização explícita** para o ambiente em
   questão — o auto-`LIMIT` só protege `SELECT`. Autorização para um ambiente não vale
   para outro.
5. Se o resultado vier vazio ou estranho, **suspeite do alvo antes da query**: container
   de outro ambiente responde normalmente, só com os dados errados.

## Azure DevOps work item (`dx wi`)

```bash
dx wi <id>                 # campos + repro + comentários + baixa anexos
dx wi <id> --relacoes      # + pai/filho
dx wi <id> --no-anexos     # só texto (p/ grep/pipe)
dx wi <id> --json | jq     # payload cru da API
```

Os prints inline vão para `/tmp/dx-wi-<id>/` — para VER as imagens, use `Read` nos
caminhos listados na seção `--- Anexos ---`. O PAT sai do `.env` do projeto (chave
`DX_AZDO_PAT`); **nunca** ecoe o token.

## SSH (`dx ssh`)

```bash
dx ssh <host> "journalctl -u <svc> -n 500"
dx ssh <host> "docker ps"
dx --raw ssh <host> "<cmd>"    # saída remota crua (sem filtro)
```

## Flags globais

`--raw` (sem redução) · `--full` (sem auto-LIMIT) · `--save <arq>` (dump completo em arquivo) ·
`--max-lines N` · `--host user@srv` (pg remoto).

## Seleção de modelo

Rodar comandos `dx` é mecânico — commits, pushes, execução de comandos e chores
semelhantes cabem num modelo menor/mais econômico (ex.: Haiku). Já a **investigação**
sobre o resultado (debug, análise das linhas do banco, decisão de design) merece o
modelo mais capaz; não delegue o raciocínio a um modelo barato só porque veio do `dx`.

## Config por projeto — CHECAR ANTES DE USAR

Precedência: **env exportado › `.env` (linhas `DX_*`) › defaults**. O `.env` é a
única fonte de config por projeto — não existe `.dxrc` nem outro arquivo.

**Se um comando `dx` falhar com "não definido para este projeto", ou na primeira vez
que usar o `dx` num projeto, rode primeiro:**

```bash
dx config      # mostra a config resolvida e o que está faltando (token mascarado)
```

### Bootstrap: criar a config quando não existir

Se `dx config` acusar chaves faltando, **descubra os valores no próprio projeto** e
proponha um bloco para o fim do `.env` (não crie arquivo novo; o `.env` já costuma
estar no `.gitignore`).

**Declare só o que diverge do default.** Rode `dx config` primeiro: o que já aparece
com o valor certo não vai para o `.env`. Na maioria dos projetos basta:

```bash
# ── dx (dev-exec wrapper) ───────────────────────────────────────
DX_PG_DB=<nome do banco>   # único obrigatório
DX_AZDO_PAT=<token>        # só p/ dx wi
```

Org/projeto do Azure DevOps **não se declara**: o `dx` deriva do remote git quando é
`dev.azure.com` (`dx config` marca `(do remote git)`). Só declare se `dx config`
mostrar `<NÃO DEFINIDO>`.

Se algo divergir do default, aí sim descubra e acrescente a chave:

1. **Container do banco e do app** (`DX_PG_CONTAINER` / `DX_APP_CONTAINER`, defaults
   `postgres` / `app-local`) → `docker ps --format '{{.Names}}\t{{.Image}}'`.
2. **Nome do banco** (`DX_PG_DB`) → `POSTGRES_DB`/`DB_DATABASE` no `.env`, ou no
   `docker-compose`.
3. **Workdir do app** (`DX_APP_DIR`, default `/var/www/html`) → `docker exec <app> pwd`.
4. **Log** (`DX_LOG_PATH`, default `app/runtime/logs/app.log`) → procure
   `runtime/logs/*.log` (Yii), `storage/logs/*.log` (Laravel), **relativo à raiz do repo**.

**Regras ao fazer isso:**
- **Confirme os valores com o usuário antes de gravar** — você está editando a config
  do projeto dele; e o PAT só ele pode fornecer.
- **Nunca imprima o valor do PAT** (nem via `cat`/`tail`/`grep` no `.env`). Para
  conferir, use `dx config`, que mascara.
- **Prefira referenciar a chave que já existe** a duplicar o valor: `DX_PG_DB=${POSTGRES_DB}`,
  `DX_APP_CONTAINER=app-${APP_ENV}`. O `dx` expande `${VAR}`/`$VAR` contra o env exportado
  e as outras chaves do `.env`, recursivamente.
- A expansão é textual: `$(cmd)` e crase **não** são executados. Para lógica de verdade,
  exporte a variável no ambiente (direnv/wrapper) — ela vence o `.env`.
- Valide no fim: `dx config` e um `dx pg "SELECT 1"`.
