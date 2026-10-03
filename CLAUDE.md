# Instruções para agentes

`pginstall.srv` prepara um servidor Ubuntu novo: PostgreSQL + pgvector no host, Docker oficial, ajustes, `pg_hba.conf`
para as redes do Docker e a pasta dos projetos. Um script só, `install.sh`, em bash.

**Idioma:** português do Brasil em tudo: mensagens do script, documentos e commits.

## Regras

| Regra | Na prática |
|---|---|
| **Repositório público** | Nada de dados pessoais, nomes de clientes ou empresas, IPs e domínios internos, nomes de servidores reais, tokens ou senhas. Exemplos usam valores genéricos (`app`, `/docker`, `203.0.113.0/24`) |
| **Nada é apagado nem desinstalado** | Conflito para a instalação e explica; quem remove é o sysadmin |
| **Rodar de novo não estraga** | Cada etapa confere o estado e só grava o que mudou (`gravar_se_mudou`); o bloco do `pg_hba.conf` é regravado entre os marcadores |
| **Senha nunca em claro num comando** | Nem em argumento nem no texto de um SQL: use o verificador SCRAM (`scram`) ou o `\password` |
| **`set -e` sem armadilha** | Não termine um `if`, `for` ou função com `condição && ação`: se a condição for falsa, o script para. Use `if` |

## Antes de dizer que terminou

```bash
docker run --rm -v "$PWD:/m:ro" -w /m koalaman/shellcheck:stable -x -S style install.sh teste/rodar.sh
teste/rodar.sh 26.04      # e teste/rodar.sh 24.04 quando mexer no PostgreSQL, no pgvector ou nos repositórios
```

Commits: conventional commits em português (`feat: ...`, `fix(pg_hba): ...`).
