# dx — dev-exec wrapper

Wrapper em Bash que reduz tokens de output de comandos `psql` (via `docker exec`), `ssh` e da API de work items do **Azure DevOps**, preservando o sinal útil para LLMs/AI coding agents.

Economia típica medida: **−50% a −94%** dependendo do tamanho/formato do output.

Ferramenta **global**: instala em `~/.local/bin` e resolve a config a partir do **projeto atual** (o diretório onde você a executa), então serve qualquer repositório.

## Por que

Comandos de troubleshooting (consultas SQL, dumps de schema, logs remotos, chamados) costumam gerar saídas verbosas que consomem tokens de contexto do LLM rapidamente. O `dx`:

- Elimina padding/bordas ASCII do `psql aligned` (usa TSV nativo do servidor)
- Aplica `head + tail sampling` em outputs longos
- Deduplica linhas repetidas com contador `[×N]`
- Trunca linhas individuais muito largas (`>180 chars`)
- Filtra ruído típico de SSH (timestamps syslog, PIDs em colchetes)
- Lê work items do Azure DevOps já em texto limpo (HTML → texto) e baixa os prints
- Reporta erros visíveis (psql/ssh/API) em bloco vermelho — nada de falha silenciosa
- Injeta `LIMIT 100` automático em SELECTs sem LIMIT (com `--full` para desligar)

## Instalação

O `dx` mora neste diretório (fonte única) e é exposto no PATH via `~/.local/bin`.

```bash
./install.sh              # binário (~/.local/bin/dx) + skill do Claude Code (~/.claude/skills/dx)
./install.sh --copy       # copia o binário (não segue updates)
./install.sh --no-skill   # instala só o binário (pula o skill)
./install.sh --uninstall  # remove binário e skill
```

Como são **symlinks**, editar `./dx` ou `./skill/SKILL.md` aqui já reflete no comando
global e no skill — sem reinstalar.

O **skill do Claude Code** (`skill/SKILL.md`) faz o agente usar o `dx` sozinho, sob
demanda, em qualquer projeto (consultas a banco, work items do Azure, logs remotos).
Instala em `~/.claude/skills/dx` (override com `DX_SKILLS_DIR`).

Se `~/.local/bin` não estiver no PATH, o instalador avisa e mostra a linha pra adicionar ao `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Verifique com `dx --help`.

## Configuração por projeto

**Cada projeto declara a sua config.** Valores sensíveis a projeto (banco, org do Azure)
**não têm default** — sem config, o `dx` falha com instrução em vez de apontar para o
ambiente de outro projeto. A config vem do **diretório atual** (raiz do repo git ou CWD),
com esta precedência:

**env exportado** › **`.env` (linhas `DX_*`)** › **defaults do script**

Para ver o que está resolvido e o que falta (token sempre mascarado):

```bash
dx config
```
```text
Projeto:      /caminho/do/projeto
Fonte:        .env (ok: /caminho/do/projeto/.env)

PostgreSQL
  DX_PG_CONTAINER   meu-postgres
  DX_PG_DB          meu_db
  ...
Azure DevOps (wi)
  DX_AZDO_PAT       <definido: 84 chars>
```

### Bloco no `.env` (única forma de config por projeto)

Não cria arquivo novo e o `.env` normalmente já está no `.gitignore`. **Declare só o
que diverge do default** — na maioria dos projetos é uma linha (duas, com Azure DevOps):

```bash
# ── dx (dev-exec wrapper) ───────────────────────────────────────
DX_PG_DB=meu_db          # único obrigatório (sem default, de propósito)
DX_AZDO_PAT=<seu-token>  # só p/ `dx wi`; sem ele, os outros comandos seguem normais
```

Org e projeto do Azure DevOps **não precisam ser declarados**: o `dx` os deriva do
remote git quando ele aponta para `dev.azure.com` (formas SSH e HTTPS). Declare
`DX_AZDO_ORG`/`DX_AZDO_PROJECT` só em repo espelhado ou remote atípico — o `.env`
vence a derivação.

O resto tem default e só entra no `.env` se o seu projeto for diferente:

| | Default |
|---|---|
| `DX_PG_CONTAINER` / `DX_PG_USER` | `postgres` / `postgres` |
| `DX_APP_CONTAINER` | `app-local` |
| `DX_APP_DIR` / `DX_YII_BIN` | `/var/www/html` / `yii` |
| `DX_LOG_PATH` | `app/runtime/logs/app.log` |

Rode `dx config` para ver o que ficou resolvido (o `wi` mostra `(do remote git)`
quando org/projeto vieram de lá).

### Referenciar outras chaves do `.env`

Um valor `DX_*` pode apontar para outra chave do mesmo arquivo, para o nome do banco
ou do container morar num lugar só:

```bash
POSTGRES_DB=meuapp_${APP_ENV}
DX_PG_DB=${POSTGRES_DB}              # → meuapp_local
DX_APP_CONTAINER=app-${APP_ENV}      # segue o ambiente
```

A expansão é recursiva (o alvo pode referenciar outro) e aceita `${VAR}` ou `$VAR`.
Variável exportada no shell vence a do `.env` — então `APP_ENV=prod dx pg "..."`
aponta banco e container para prod de uma vez. Referência inexistente vira vazio;
ciclo (`A=${B}`, `B=${A}`) é cortado, não trava.

> **O `dx` faz *parse* do `.env` (grep), nunca `source`.** Isso mantém o arquivo válido
> para os outros consumidores (docker compose, dotenv do PHP/Node) e garante que nenhum
> código vindo dele seja executado. A expansão acima é **puramente textual**: `$(cmd)` e
> crase **não** são executados, ficam literais. Não use lógica de shell no `.env`.

> **O `dx` não lê nenhum outro arquivo de config do projeto** — não há `.dxrc` nem
> equivalente. Ele nunca faz `source` de arquivo dentro do repositório, então nenhum
> código do projeto é executado pelo `dx`.

### Valores dinâmicos — variáveis de ambiente

```bash
export DX_PG_CONTAINER="meu-postgres"
export DX_PG_DB="meu_db"
```

Coloque em `.envrc` (direnv), `~/.bashrc` ou num wrapper do projeto. Tem a maior
precedência — útil para sobrescrever pontualmente (ex.: `DX_PG_DB=outro dx pg "..."`)
e para o que o `.env` não expressa, por ser dotenv puro: valor derivado de outra
variável, como `export DX_APP_CONTAINER="app-${APP_ENV:-local}"`.

## Dependências

- `bash` 4+
- `awk` (gawk, mawk e busybox awk todos funcionam)
- `jq` (para `dx pg --explain` e para o subcomando `wi`)
- `docker` (para subcomando `pg`)
- `ssh` (para subcomando `ssh`)
- `curl` (para subcomando `wi`)
- `git` (para descobrir a raiz do projeto — opcional; cai pro CWD sem ele)
- `python3` (opcional; melhora a limpeza de HTML do `wi` — sem ele, fallback com `sed`)

Todas geralmente já presentes em qualquer máquina de dev.

## Uso

### PostgreSQL via docker exec

```bash
dx pg "SELECT id, nome FROM cliente"           # auto-LIMIT 100
dx pg --full "SELECT * FROM cliente"           # sem auto-LIMIT
dx pg --list-tables                            # \dt em TSV
dx pg --describe usuario                       # \d usuario em TSV
dx pg --explain "SELECT ..."                   # EXPLAIN: só nó top + custo + tempo
dx pg                                          # shell psql interativo (sem filtros)
```

#### PostgreSQL remoto (via SSH → docker exec)

Para resolver problemas num banco remoto, o `pg` pode rodar o `psql` num container
Docker de outro servidor, por SSH — mantendo TSV, auto-`LIMIT` e o pipeline de redução,
**sem** o strip de logs do `ssh` (que corromperia linhas iniciadas por data):

```bash
dx pg --host deploy@srv-01 "SELECT ..."      # pontual
```

Ou fixe na config do projeto (aí todo `dx pg` já vai pro remoto):

```bash
# .env
DX_PG_SSH=deploy@srv-01
DX_PG_CONTAINER=meu-postgres
DX_PG_DB=meu_db
```

A query trafega por **stdin** (`psql -f -`), então não há problema de aspas. Requer SSH
(de preferência por chave) e permissão de `docker` no host. `dx pg` (sem query) abre o
psql interativo remoto via `ssh -t`.

> **`--host` troca só a máquina — não o ambiente.** Container, usuário e banco continuam
> vindo da config **local**: o comando montado é
> `ssh <host> 'docker exec -i <DX_PG_CONTAINER> psql -U <DX_PG_USER> -d <DX_PG_DB>'`.
> O `dx` não inspeciona o host remoto e não tem como saber que o nome certo lá é outro.

Isso importa quando **um mesmo servidor hospeda vários ambientes** (dev, hml, staging).
Comece descobrindo o que existe lá, em vez de deduzir:

```bash
dx ssh user@srv "docker ps --format '{{.Names}}'"
```

Duas topologias comuns, com implicações bem diferentes:

**1. Um Postgres compartilhado, ambientes separados por banco** (o arranjo mais comum):

```
app-hml  app-dev  app-sistema
postgres → meuapp_hml · meuapp_dev · meuapp_sistema
```

O nome do container é o mesmo do seu local, então **só o banco muda**. Se o `DX_PG_DB`
for derivado (`DX_PG_DB=${POSTGRES_DB}` com `POSTGRES_DB=meuapp_${APP_ENV}`), uma
variável resolve tudo:

```bash
APP_ENV=hml dx pg --host user@srv "SELECT ..."
```

**2. Um Postgres por ambiente** (containers com nomes distintos) — aí aponte os dois:

```bash
DX_PG_CONTAINER=pg-hml DX_PG_DB=meuapp_hml dx pg --host user@srv "SELECT ..."
```

Variável exportada vence o `.env` e vale só para aquele comando — a config local fica
intacta.

**Como cada erro se manifesta:** se o container não existir no host, o Docker responde
`No such container` — falha barulhenta, sem risco. Se o container existir mas o banco
não, o psql recusa a conexão — também barulhento. O caso silencioso é o **banco errado
que existe**: trocar `hml` por `dev` conecta normalmente e devolve dados do ambiente
errado. Por isso o `dx` anuncia o alvo antes de toda query remota:

```
→ remoto: user@srv · postgres · meuapp_hml
```

Confira essa linha — é a única defesa contra o ambiente trocado.

**`dx yii` e `dx logs` não têm modo remoto** — atuam sempre no container/repo local. Para
console ou log de outro servidor, use `dx ssh`.

#### Buscar tabela/coluna no schema

Evita query quebrada por nome errado — responde na hora se a coluna existe:

```bash
dx pg --find fantasia      # 0 rows → a coluna não existe
dx pg --find status        # lista tabelas com coluna "status"
```

### Console do framework (`dx yii`)

Roda o console Yii dentro do container do app, sem `docker exec` manual:

```bash
dx yii migrate                    # migrations pendentes
dx yii migrate/history
dx yii cache/flush-all
dx yii migrate --interactive=0    # sem prompt de confirmação (scripts/agentes)
```

Container e caminhos vêm da config do projeto (`DX_APP_CONTAINER`, `DX_APP_DIR`,
`DX_YII_BIN`), então serve a vários projetos Yii. Aloca TTY só quando há terminal —
prompts funcionam para humanos e não quebram em pipe/agente.

### Logs do app (`dx logs`)

Mostra o log colapsando os frames de stack trace de **dependências** (`/vendor/`) e
**preservando os frames do projeto** — que são os que apontam onde está o bug:

```bash
dx logs                 # últimas 100 linhas, filtradas
dx logs -n 300
dx logs --errors        # só entradas [error]
dx logs --file /caminho/outro.log
```

Numa exceção real com trace profundo, a redução medida foi de **~35%** das linhas.

### SSH remoto

```bash
dx ssh prod "journalctl -u nginx -n 500"
dx ssh prod "tail -n 1000 /var/log/app.log"
dx ssh prod "ps aux | grep php-fpm"
```

### Work item do Azure DevOps

Lê um work item (Bug/Task/etc.) pela REST API **por inteiro**, já em texto limpo, e
**baixa os anexos/prints automaticamente** — inclusive imagens **inline** coladas no
HTML de qualquer campo.

O retorno tem, nesta ordem: cabeçalho (tipo, título, estado, área, sprint,
responsável), Repro Steps/Descrição, **um bloco por campo preenchido** (critérios de
aceite, protótipo, campos custom do processo), comentários e anexos.

```bash
dx wi 1234                          # work item completo + baixa anexos (auto)
dx wi 1234 --relacoes               # + relações (pai/filho/relacionados)
dx wi 1234 --no-anexos              # só texto (não baixa nada — bom p/ pipe/grep)
dx wi 1234 --dir /tmp/wi            # baixa anexos num diretório específico
dx wi 1234 --json                   # JSON cru da API (pra pipar em jq)
dx --raw wi 1234                    # texto integral, sem truncar linhas longas
```

**Campos custom:** o processo do time costuma guardar requisito fora da descrição, e
esses campos chegam da API como GUID (`Custom.<uuid>`). O `dx` resolve o rótulo real
("Protótipo", "Critérios de Aceite") na lista de campos da organização, cacheada por 7
dias em `$TMPDIR/dx-azdo-fields-<org>-<projeto>.json`. Sem rede nem cache, cai para o
`referenceName` — nunca omite o campo.

**Comentários e anexos saem sempre**, mesmo zerados (`--- Comentários (0) --- /
(nenhum)`): "não tem" e "não olhei" são conclusões diferentes para quem lê a task.
Com `--no-anexos` a contagem continua aparecendo, só o download é pulado.

**Anexos:** por padrão baixam para `$TMPDIR/dx-wi-<id>/` (não sujam o diretório
atual), e a seção `--- Anexos ---` no retorno lista os caminhos locais. É
**idempotente** (não rebaixa o que já existe) e dedup por GUID (imagem inline que
também conste como `AttachedFile` baixa uma vez só). Use `--dir` ou `--no-anexos`.

**Autenticação:** o PAT (Personal Access Token) é lido do `.env` na raiz do repo
token nunca é ecoado. Escopo mínimo do PAT: **Work Items → Read** (a leitura de
anexos faz parte do mesmo escopo).

### Flags globais

| Flag | Descrição |
|---|---|
| `--raw` | Desliga o pipeline de redução (output cru; em `wi`, texto integral) |
| `--full` | Não injeta `LIMIT 100` em SELECTs sem LIMIT |
| `--save <arquivo>` | Salva output **completo** em arquivo; devolve só sumário (head 10 + tail 10) |
| `--max-lines N` | Override do limite antes do head/tail sample (default: 80; `wi`: 1000) |
| `-h`, `--help` | Help |

### Variáveis de ambiente

| Var | Default | Descrição |
|---|---|---|
| `DX_PG_CONTAINER` | `postgres` | Nome do container Docker do Postgres |
| `DX_PG_USER` | `postgres` | Usuário do banco |
| `DX_PG_DB` | **obrigatório** | Nome do banco — defina no `.env` (sem default: evita apontar pro banco de outro projeto) |
| `DX_PG_SSH` | _(vazio)_ | Host SSH p/ rodar o psql remoto (= flag `--host`) |
| `DX_APP_CONTAINER` | `app-local` | Container do app (`yii`, `logs`) |
| `DX_APP_DIR` | `/var/www/html` | Workdir do app no container |
| `DX_YII_BIN` | `yii` | Binário do console, relativo a `DX_APP_DIR` |
| `DX_LOG_PATH` | `app/runtime/logs/app.log` | Log do app, relativo à raiz do projeto |
| `DX_VENDOR_MARK` | `/vendor/` | Marca de frame de dependência a colapsar |
| `DX_MAX_LINES` | `80` | Linhas antes de aplicar head/tail sample (o `wi` sobe pra 1000 sem override) |
| `DX_AZDO_ORG` | _(auto: do remote git, se `dev.azure.com`)_ | Organização do Azure DevOps |
| `DX_AZDO_PROJECT` | _(auto: do remote git, se `dev.azure.com`)_ | Projeto/team project |
| `DX_ENV_FILE` | _(auto: `.env` na raiz do repo atual)_ | De onde ler a config e o PAT |
| `DX_BIN_DIR` | `~/.local/bin` | Onde o `install.sh` instala |
| `NO_COLOR` | _(unset)_ | Se setado, desliga cores ANSI no stderr |

## Como o pipeline funciona

Cada subcomando passa pelo mesmo pipeline (exceto `--raw` e modo interativo):

```
comando → captura stdout+stderr separados
        → reduce()
            ├── trim_long_lines  (>180 chars → trunca + "[+N chars]")
            ├── dedup_consecutive (linhas iguais → "[×N] linha")
            └── head_tail_sample  (>MAX_LINES → head 20 + "...omitidas..." + tail 20)
        → maybe_save (se --save: grava arquivo, devolve sumário)
```

Erros são exibidos em **bloco vermelho** no stderr com a query/comando/URL original:

```
✗ dx: psql falhou (exit 1)
→ query: SELECT * FROM tabela_inexistente
┌─ stderr do psql
│ ERROR:  relation "tabela_inexistente" does not exist
└─────
```

## Economia de tokens (benchmarks reais)

| Cenário | RAW | DX | Ganho |
|---|---:|---:|---:|
| Tabela pequena (3 linhas) | ~29 tok | ~15 tok | −48,7% |
| 20 linhas, 6 col largas | ~1.016 tok | ~490 tok | −51,8% |
| 200 linhas (ativa sample) | ~11.316 tok | ~728 tok | **−93,6%** |
| `\dt` (todas tabelas) | ~4.340 tok | ~421 tok | **−90,3%** |
| `\d` em tabela com 30+ colunas | ~4.093 tok | ~865 tok | −78,9% |
| 500 linhas estreitas | ~3.679 tok | ~249 tok | **−93,2%** |

Quanto maior o output, maior a economia.

## Quando NÃO usar

- Quando você precisa do output **exato** (formatação aligned) — use `psql` direto ou `dx --raw`
- Quando vai redirecionar pra um script que parseia output do psql (use `--raw`)
- Em shell interativo: rode `dx pg` sem args → cai direto no psql sem filtros

## Limitações conhecidas

- Modo `\x` (expanded display) do psql não é otimizado especificamente
- SSH não faz pool de conexões; cada `dx ssh` abre conexão nova (use ControlMaster do SSH se preciso)
- Saída binária em `ssh`/`pg` quebra o pipeline de texto — use `--raw` ou evite

## Adaptando o subcomando `pg` para outros bancos

O subcomando `pg` é amarrado a `docker exec ... psql`. Para outro banco, copie o
script e troque `run_psql_c`:

- **MySQL/MariaDB**: `mysql -u $USER -p$PASS $DB -e "$q" --batch` (`--batch` já dá TSV)
- **MongoDB**: `mongosh --quiet --eval`
- **Banco local (sem Docker)**: remova o `docker exec` e chame `psql` direto

Mantenha o resto do pipeline (`reduce`, `maybe_save`) — são agnósticos.

## Estrutura do projeto

```
dx/
├── dx              # script executável (fonte única)
├── install.sh      # instala/desinstala binário + skill
├── skill/
│   └── SKILL.md    # skill do Claude Code (usado sob demanda)
├── EXAMPLE.md      # exemplos (pg, ssh, wi)
├── README.md       # este arquivo
└── .gitignore
```

Instalado em `~/.local/bin/dx` (symlink para `./dx`) e `~/.claude/skills/dx`
(symlink para `./skill`).

## Licença / atribuição

Inspirado no [rtk-ai/rtk](https://github.com/rtk-ai/rtk) (binário Rust que faz algo similar para 100+ comandos). O `dx` é um wrapper Bash mínimo focado em 3 casos (PostgreSQL via Docker + SSH + work items do Azure DevOps).
