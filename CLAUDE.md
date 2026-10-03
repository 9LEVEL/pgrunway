# Instruções para agentes

`pgrunway` (antes pginstall.srv) coloca um servidor PostgreSQL + pgvector no ar numa máquina Ubuntu nova: sistema
atualizado, ajustes proporcionais, `pg_hba.conf` em que o `postgres` nunca entra de outra máquina e, com
`--com-docker`, o Docker oficial para projetos em containers na mesma máquina. Um script só, `install.sh`, em bash.

**Idioma:** português do Brasil em tudo: mensagens do script, documentos e commits.

## Regras

| Regra | Na prática |
|---|---|
| **Repositório público** | Nada de dados pessoais, nomes de clientes ou empresas, IPs e domínios internos, nomes de servidores reais, tokens ou senhas. Exemplos usam valores genéricos (`app`, `deploy`, `/docker`, `10.200.0.0/16`) |
| **Poucos parâmetros** | O caso comum é `sudo ./install.sh` sem nada (pedido do mantenedor). Opção nova só se não houver padrão bom; o que dá para decidir sozinho (ex.: atualizar o sistema só na primeira vez), decide |
| **Nada é apagado nem desinstalado** | Conflito para a instalação e explica; quem remove é o sysadmin |
| **Rodar de novo não estraga** | Cada etapa confere o estado e só grava o que mudou (`gravar_se_mudou`); o bloco do `pg_hba.conf` é regravado entre os marcadores |
| **Senha nunca em claro num comando** | Nem em argumento nem no texto de um SQL: use o verificador SCRAM (`scram`) ou o `\password` |
| **`set -e` sem armadilha** | Não termine um `if`, `for` ou função com `condição && ação`: se a condição for falsa, o script para. Use `if`. Pipeline que pode não achar nada dentro de `$(...)` leva `\|\| true`, e `$(cond && echo x)` numa atribuição falha a atribuição inteira |
| **Mensagens em até 92 colunas** | Cabem num terminal comum e nas imagens do README (o terminal da gravação tem ~96) |
| **Commits sem coautoria de ferramentas** | Sem linhas `Co-Authored-By` nem rodapés de geração automática |

## Antes de dizer que terminou

```bash
docker run --rm -v "$PWD:/m:ro" -w /m koalaman/shellcheck:stable -x -S style install.sh teste/*.sh docs/demo/*.sh
teste/rodar.sh 26.04      # e teste/rodar.sh 24.04 quando mexer no PostgreSQL, no pgvector ou nos repositórios
```

Mudou uma mensagem que aparece nas imagens? `docs/demo/capturar.sh` (grava a saída real) e `docs/demo/gravar.sh`
(regrava `docs/img`). Versão nova: `VERSAO` no `install.sh`, `CHANGELOG.md` e o link do tar.gz no README.

Commits: conventional commits em português (`feat: ...`, `fix(pg_hba): ...`).
