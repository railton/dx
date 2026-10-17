# Exemplos de uso do `dx`

O `dx` reduz o output verboso das ferramentas do dia a dia — **PostgreSQL**, **console
do framework**, **logs**, **SSH** e **work items do Azure DevOps** — para economizar
tokens/leitura, resolvendo a config a partir do projeto atual.

Índice: [PostgreSQL](#1-postgresql-dx-pg) · [Console](#2-console-do-framework-dx-yii) ·
[Logs](#3-logs-do-app-dx-logs) · [SSH](#4-ssh-dx-ssh) · [Azure DevOps](#5-azure-devops-dx-wi)

> Os exemplos usam um schema fictício (`cliente`, `pedido`) e host `srv-01`.
> Adapte ao seu projeto no `.env` (bloco `DX_*`) — veja `dx config` e o `README.md`.

---

## 1. PostgreSQL (`dx pg`)

Roda a query via `docker exec ... psql`, em TSV nativo (sem bordas/padding), com
auto-`LIMIT 100` em SELECTs e amostragem head/tail em resultados grandes.

### Query

```bash
dx pg "SELECT id, nome, status FROM cliente WHERE id IN (1, 2)"
```
```text
⚠ dx: resultado cortado no auto-LIMIT 100 — use --full para tudo   (só quando bateu no teto)
id	nome	status
1	Cliente Exemplo	ativo
2	Outro Cliente	inativo
(2 rows)
```

### Estrutura da tabela

```bash
dx pg --describe cliente
```
```text
Table "public.cliente"
Column	Type	Collation	Nullable	Default
id	integer		not null	nextval('cliente_id_seq'::regclass)
nome	character varying(255)		not null	
status	character varying(50)			
...
```

### Buscar tabela/coluna no schema

Evita query quebrada por nome errado — responde na hora se a coluna existe:

```bash
dx pg --find fantasia      # 0 rows → não existe nenhuma tabela/coluna com esse termo
dx pg --find status        # lista todas as tabelas que têm coluna "status"
```

### Plano de execução (resumido)

`--explain` roda `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` e destila só o nó de topo:

```bash
dx pg --explain "SELECT * FROM cliente WHERE nome LIKE 'ACME%'"
```
```text
Plano:        Seq Scan
Custo total:  102.26
Tempo (ms):   0.249
Planning ms:  0.515
Linhas:       15
Filtro:       ((nome)::text ~~ 'ACME%'::text)
Index:        —
```

### Banco remoto (via SSH → docker exec)

Pra investigar um postgres em outro servidor, sem abrir túnel na mão:

```bash
dx pg --host deploy@srv-01 "SELECT count(*) FROM pedido WHERE status = 'erro'"
```

Roda o `psql` no container Docker do host remoto por SSH, mandando a query por
**stdin** — mantém TSV/auto-LIMIT e **não** aplica o strip do `ssh` (datas nas linhas
ficam intactas). Dá pra fixar o host na config do projeto: `DX_PG_SSH=deploy@srv-01`.

### Outros

```bash
dx pg --list-tables                 # \dt em TSV
dx pg --full "SELECT * FROM cliente" # sem auto-LIMIT
dx pg                               # shell psql interativo (sem filtros)
```

---

## 2. Console do framework (`dx yii`)

Roda o console do framework dentro do container do app, sem `docker exec` manual:

```bash
dx yii migrate                    # migrations pendentes
dx yii migrate/history
dx yii cache/flush-all
dx yii migrate --interactive=0    # sem prompt de confirmação (scripts/agentes)
```
```text
Yii Migration Tool (based on Yii v2.0.55)

Showing the last 10 applied migrations:
	(2026-07-23 17:32:02) m260723_154353_exemplo_migration
	(2026-07-22 12:55:09) m260721_234500_outra_migration
```

Container e caminhos vêm da config do projeto (`DX_APP_CONTAINER`, `DX_APP_DIR`, `DX_YII_BIN`),
então o mesmo comando serve a qualquer projeto. Aloca TTY só quando há terminal —
prompts funcionam para humanos e não quebram em pipe/agente.

---

## 3. Logs do app (`dx logs`)

Mostra o log colapsando os frames de stack trace de **dependências** (`/vendor/`) e
**preservando os frames do projeto** — que são os que apontam onde está o bug.

```bash
dx logs                 # últimas 20 entradas, cada uma com seu stack
dx logs -n 50           # -n conta ENTRADAS, não linhas
dx logs --errors        # só entradas [error], inteiras
dx logs --errors --since 14:30   # erros a partir de um horário
dx logs --file /caminho/outro.log
```

```text
2026-07-10 22:26:00 [172.18.0.1][317][...][error][yii\web\HttpException:404] ...
Stack trace:
  [... 8 frames de dependências omitidos ...]
#9 /var/www/html/app/services/PedidoService.php(142): app\services\PedidoService->processar()
#10 /var/www/html/web/index.php(12): yii\base\Application->run()
```

Numa exceção real com trace profundo, a redução medida foi de **~35%** das linhas —
mantendo intactos os frames que localizam o erro no código do projeto.

---

## 4. SSH (`dx ssh`)

Remove timestamp de syslog, host e `[PID]`; depois deduplica linhas consecutivas
iguais (colapsa em `[×N] …`).

```bash
dx --raw ssh deploy@srv-01 "journalctl -n 5 --no-pager"   # cru (--raw não filtra)
```
```text
Jul 24 15:05:31 srv-01 systemd[174883]: Listening on dbus.socket - D-Bus User Message Bus Socket.
Jul 24 15:05:31 srv-01 systemd[174883]: Reached target sockets.target - Sockets.
Jul 24 15:05:31 srv-01 systemd[174883]: Reached target basic.target - Basic System.
Jul 24 15:05:31 srv-01 systemd[1]: Started user@1000.service - User Manager for UID 1000.
Jul 24 15:05:31 srv-01 systemd[1]: Started session-12717.scope - Session 12717.
```

```bash
dx ssh deploy@srv-01 "journalctl -n 5 --no-pager"         # via dx (filtrado)
```
```text
systemd Listening on dbus.socket - D-Bus User Message Bus Socket.
systemd Reached target sockets.target - Sockets.
systemd Reached target basic.target - Basic System.
systemd Started user@1000.service - User Manager for UID 1000.
systemd Started session-12717.scope - Session 12717.
```

> O nome do programa (`systemd`) é preservado — só o timestamp, o host e o `[PID]`
> saem. Linhas consecutivas iguais viram `[×N] …`. Use `--raw` para a saída intacta.

---

## 5. Azure DevOps (`dx wi`)

Puxa um work item (Bug/Task/etc.) já em texto limpo (campos + Repro Steps +
comentários) e **baixa os prints automaticamente** — inclusive as imagens coladas
*inline* no HTML do chamado.

### Setup (uma vez por projeto)

Acrescente ao `.env` do projeto (já ignorado pelo git) — org, projeto e o **PAT**
(escopo *Work Items → Read*):

```bash
# .env
DX_AZDO_ORG=minha-org
DX_AZDO_PROJECT=MeuProjeto
DX_AZDO_PAT=seu_token_aqui
```

> Gere em: Azure DevOps → *User settings* → *Personal access tokens* → *New Token*.
> Confira com `dx config` (mostra o token mascarado).

### Uso

```bash
dx wi 1234
```
```text
ID       : 1234
Tipo     : Bug
Titulo   : Erro ao gerar relatório mensal
Estado   : Active / Approved
Area     : MeuProjeto\Time A
Sprint   : MeuProjeto\Sprint 84
Assigned : fulano.silva
Criado   : 2026-07-23T13:11:47.987Z

--- Repro Steps / Descrição ---
O cliente relatou não conseguir emitir o relatório do mês de Junho.
Após análise, o mês não aparece na lista de seleção. (...)

--- Critérios de Aceite ---
Dado que o mês possua movimento, deve aparecer na lista. (...)

--- Protótipo ---
Campo Mês: combo com os 12 meses do exercício corrente.

--- Comentários (2) ---
[fulano.silva @ 2026-07-24] Valida em homologação, por favor.
[beltrano.souza @ 2026-07-23] Reproduzido no ambiente de testes.

--- Anexos (/tmp/dx-wi-1234) ---
  /tmp/dx-wi-1234/wi1234_1_image.png (104548 bytes)
  /tmp/dx-wi-1234/wi1234_2_image.png (36447 bytes)
```

### Variações úteis

```bash
dx wi 1234 --relacoes     # + pai/filho (ex.: Parent #1200, Child #1240)
dx wi 1234 --no-anexos    # só texto (bom pra grep/pipe)
dx wi 1234 --dir ./prints # baixa os anexos num diretório específico
dx wi 1234 --json | jq    # payload cru da API (qualquer campo)
dx --raw wi 1234          # texto integral, sem truncar linhas longas
```

Detalhes: o HTML vira texto legível; **todo campo preenchido vira um bloco** (campo
custom do processo aparece com o rótulo real, não com o GUID da API); as seções de
comentários e anexos saem mesmo zeradas, pra não confundir "não tem" com "não olhei";
prints inline baixam pra `/tmp/dx-wi-<id>/` (não sujam o CWD) de forma idempotente; o
PAT é lido do `.env` do projeto e **nunca é ecoado**.

---

## Flags globais (valem pra todos os subcomandos)

| Flag | Efeito |
|---|---|
| `--raw` | Desliga a redução (output cru; em `wi`, texto integral) |
| `--full` | Não injeta `LIMIT 100` (só `pg`) |
| `--write` | Libera escrita no `pg` remoto |
| `--save <arquivo>` | Salva o output completo em arquivo, devolve só o sumário |
| `--max-lines N` | Ajusta o limite da amostragem head/tail (default: 80; `wi`: 1000, pra task sair inteira) |
| `--host user@srv` | Roda o `pg` num host remoto |

Config por projeto (container/db/org/PAT) via bloco `DX_*` no `.env` da raiz do repo — ver `README.md`.
