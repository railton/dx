# CLAUDE.md

## Language
Respostas em pt-BR.

## Project Overview
`dx` — wrapper CLI em Bash que reduz o output verboso de **PostgreSQL** (via `docker exec`), **SSH** e **work items do Azure DevOps**, preservando o sinal útil para LLMs/agentes. Economia típica: 50–94%.

Ferramenta **global**: instalada em `~/.local/bin/dx`, mas resolve config a partir do **projeto atual** (CWD/git-root), então serve qualquer repositório.

## Estrutura

```
dx              # script único (todo o código vive aqui — bash puro)
install.sh      # instala binário + skill do Claude Code (symlinks)
skill/SKILL.md  # skill do Claude Code → ~/.claude/skills/dx
README.md       # documentação completa
EXAMPLE.md      # exemplos de uso (pg, yii, logs, ssh, wi)
```

## Instalação / desenvolvimento

```bash
./install.sh              # symlinks: ~/.local/bin/dx e ~/.claude/skills/dx
./install.sh --no-skill   # só o binário
./install.sh --uninstall  # remove ambos
```

**Instalação é por symlink** → editar `./dx` ou `./skill/SKILL.md` reflete **na hora** no comando global. Não precisa reinstalar após alterar.

## Validação

Não há suíte de testes. O ciclo é:

```bash
bash -n dx && bash -n install.sh     # sintaxe (sempre rodar após editar)
dx pg "SELECT 1"                     # smoke por subcomando
dx wi <id> --no-anexos
dx ssh <host> "uptime"
echo $?                              # exit code importa — ver gotcha do set -e
```

Ao mudar algo, teste também os **caminhos de erro** (id inválido, host inexistente, container ausente) — o valor do `dx` está em falhar de forma legível.

## Arquitetura do script

Pipeline comum a todos os subcomandos (exceto `--raw` e modo interativo):

```
comando → stdout/stderr separados
        → reduce(): trim_long_lines → dedup_consecutive → head_tail_sample
        → maybe_save() (se --save: grava arquivo, devolve sumário)
```

Dispatch no fim do arquivo: `cmd_pg` | `cmd_ssh` | `cmd_wi` | `cmd_yii` | `cmd_logs`. Flags globais são parseadas **antes** do dispatch (`--raw`, `--full`, `--save`, `--max-lines`, `--host`).

Helpers reutilizáveis: `die`/`error`/`warn`/`info`, `report_block` (bloco vermelho de erro), `shq` (quoting sh-safe), `html_to_text`, `find_env_file`, `load_azdo_pat`.

## Gotchas (Bash)

- **`set -euo pipefail` + trap ERR:** `[[ cond ]] && cmd` como **última linha** de função/bloco retorna exit 1 quando a condição é falsa — contamina o exit code e dispara "abortou inesperadamente". Use `if [[ cond ]]; then cmd; fi` no fim de blocos. *(Já causou 2 bugs.)*
- **Array vazio:** `set -- "${ARGS[@]:-}"` injeta um argumento **vazio** (`$#`=1). Cheque `${#ARGS[@]}` antes e use `set -- "${ARGS[@]}"`.
- **jq dentro de string bash single-quoted:** não escape aspas (`\"—\"` é inválido em jq). Use `"—"` direto.
- **psql para JSON:** o modo cru de `run_psql_c` (2º arg = `0`) usa `-t -A` (tuples-only unaligned). Sem isso vem a tabela *aligned* com header e `(N rows)` — e o jq não parseia.
- **`--raw` deve ser respeitado em todo filtro**, não só no `reduce()`. Em `cmd_ssh`, `--raw` pula o `strip_ssh_noise`.

## Gotchas (domínio)

- **`strip_ssh_noise` corrompe dados**, não só logs: ele remove prefixos que *parecem* timestamp. Por isso o **pg remoto NÃO passa por ele** — senão linhas de dados iniciadas por data seriam mutiladas.
- **pg remoto** (`--host` / `DX_PG_SSH`): `ssh → docker exec -i psql -f -`, com a query indo por **stdin** (evita inferno de aspas) e o comando remoto quotado por `shq`. **Limitação conhecida e assumida:** `--host` troca só a máquina — container/user/db continuam vindo do `.env` local, e o `dx` não inspeciona o host. Num servidor com vários ambientes, container homônimo de outro ambiente responde sem aviso. Se um dia isso virar feature (perfil por ambiente, `--env`), o requisito é **apontar explícito**, nunca adivinhar o alvo remoto.
- **PAT nunca é ecoado.** É lido do `.env` do projeto (chave `DX_AZDO_PAT`) e passado via `curl -u :"$pat"`. Nunca adicione `-v`/echo do token.
- **O `dx` só lê variáveis do namespace `DX_`.** O filtro do `.env` é `^DX_[A-Z0-9_]+=` e o nome do PAT é fixo (`DX_AZDO_PAT`) — sem indireção que aponte para fora. Nunca reintroduza uma opção que faça o `dx` ler uma variável arbitrária do `.env`: ele não deve ter acesso a segredos de outras ferramentas que compartilham o arquivo. Para reaproveitar um PAT já existente sob outro nome, exporte a ponte no shell (`export DX_AZDO_PAT="$OUTRO"`).
- **Anexos do `wi`** baixam por padrão em `$TMPDIR/dx-wi-<id>/` — nunca no CWD (é comando de leitura, não deve sujar o repo). Idempotente e com dedup por GUID.
- **Config resolve pelo projeto atual**, não pelo diretório do script (o `dx` é global). `find_env_file`/`_dx_project_root` usam `git rev-parse --show-toplevel` do CWD.
- **Config mínima é meta de design.** Toda variável nova precisa de um default sensato ou de derivação do próprio repo — `.env` não é lugar de repetir o óbvio. `DX_AZDO_ORG`/`DX_AZDO_PROJECT` saem do remote git (`_dx_azdo_from_remote`, formas SSH `v3/<org>/<proj>/<repo>` e HTTPS `<org>/<proj>/_git/<repo>`), e a derivação só roda com o host `dev.azure.com` — remote de outro host não vira palpite. **Exceção deliberada: `DX_PG_DB` não ganha default nem inferência** — banco errado é falha silenciosa, que é pior que falhar na cara.
- **O `.env` é a ÚNICA fonte de config por projeto, e é PARSEADO (grep), nunca `source`.** Ele pertence a outros consumidores (docker compose, dotenv do PHP/Node) e precisa continuar `KEY=value` puro; além disso, `source` executaria código arbitrário do arquivo. **Nunca reintroduza um `.dxrc`** ou qualquer outro arquivo de config lido do repositório: o `dx` não executa nada vindo do projeto. Precedência: env exportado › `.env` › defaults.
- **Valores `DX_*` expandem `${VAR}`/`$VAR`** contra o env exportado e as outras chaves do `.env` (`_dx_expand`/`_dx_ref`), para não duplicar nome de banco/container. É substituição **textual e à mão** — nunca `eval`/`source`, e `$(...)`/crase ficam literais **de propósito**: não "conserte" isso. Ciclo é barrado por `_DX_EXPANDING` (cadeia de nomes em expansão); a profundidade sozinha não basta — cada nível reexpande e o custo vira exponencial. Toda chave do `.env` entra na tabela de substituição, mas **só `DX_*` vira variável do script**.
- **`dx config` mascara o PAT** (`<definido: N chars>`). Qualquer saída nova que toque o `.env` deve seguir isso — nunca imprimir valor de token.
- **`dx logs` preserva frames do projeto de propósito.** Só colapsa frames com `DX_VENDOR_MARK` (`/vendor/`) — os frames em `app/`/`web/` são o sinal que aponta o bug; colapsá-los destruiria o valor do comando.
- **`dx yii` aloca TTY condicionalmente** (`-it` só se `[[ -t 0 ]]`): prompts funcionam para humanos, e não quebra com "the input device is not a TTY" sob pipe/agente. Comandos que perguntam (ex.: `migrate`) aceitam `--interactive=0`.
- **Subcomandos de app (`yii`/`logs`) são configuráveis por projeto** (`DX_APP_CONTAINER`, `DX_APP_DIR`, `DX_YII_BIN`, `DX_LOG_PATH`) — há mais de um projeto Yii usando o `dx`. Nunca hardcode caminho/container de um projeto específico.

## Convenções

- **Bash puro**, sem dependências além de: `awk`, `jq`, `curl`, `docker`, `ssh`, `git`, `python3` (opcional, melhora `html_to_text`).
- **Tudo num arquivo só** (`dx`) — é a proposta do projeto; não fragmentar em libs.
- Mensagens ao usuário em **pt-BR**, sempre em **stderr** (stdout é o dado, que pode ser pipado).
- Ao adicionar subcomando: criar `cmd_<nome>`, registrar no `case` do dispatch, documentar no header do script (o `--help` é gerado dele por `sed`), no `README.md`, no `EXAMPLE.md` e no `skill/SKILL.md`.
- **`skill/SKILL.md` deve ser portável** — sem caminhos pessoais (`/home/<user>/...`), pois o repo é compartilhado com outros devs.
- **Nada de dado real nos docs nem no código.** O `dx` é agnóstico de projeto e o repo é compartilhado: nunca use nome de cliente/empresa, CNPJ, IP/host interno, nome de pessoa, ID de chamado real ou nome de banco de um projeto específico. Exemplos usam schema fictício (`cliente`, `pedido`), host `srv-01`, work item `1234`.
- **Sem default para valor sensível a projeto** (`DX_PG_DB`, `DX_AZDO_ORG`, `DX_AZDO_PROJECT`): sem config, falhe com instrução. Um default herdado apontaria queries de um projeto para o banco de outro silenciosamente.

## Seleção de Modelo
Tarefas mecânicas (rodar comandos, commits, pushes, renomear) cabem num modelo menor/econômico (ex.: Haiku). Reserve o modelo mais capaz para debug do script, design de subcomando e decisões de arquitetura.
