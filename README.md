# pginstall.srv

Prepara um servidor Ubuntu novo para receber projetos em containers com o **PostgreSQL no próprio host**:
PostgreSQL e pgvector (versão travada), Docker Engine oficial, ajustes do Postgres ao tamanho da máquina, o
`pg_hba.conf` liberando as redes do Docker e a pasta dos projetos. Termina conferindo tudo com um banco e um login
temporários, apagados no fim.

```bash
git clone https://github.com/9LEVEL/pginstall.srv.git && cd pginstall.srv
sudo ./install.sh --checar               # confere a máquina e mostra o plano; não muda nada
sudo ./install.sh --atualizar-sistema    # instala (mostra o plano e pergunta antes)
```

Outras opções em `./install.sh --ajuda`: versão do PostgreSQL (`--pg`, padrão 18), versão exata do pgvector
(`--pgvector`), pasta (`--pasta`, padrão `/docker`), usuário do grupo docker (`--usuario`), `--cloudflared`
(prepara a pasta de um Cloudflare Tunnel) e `--sim` para automação.

## O que ele faz

| Etapa | O quê |
|---|---|
| Conferência | Ubuntu e arquitetura, systemd, memória, disco, relógio, repositórios alcançáveis, pacotes que conflitam com o Docker oficial, outro PostgreSQL ou a porta 5432 ocupada, redes do Docker cruzando com as da máquina |
| PostgreSQL | do Ubuntu quando ele tem a versão pedida (26.04 tem a 18), senão do PGDG; o pgvector vem do PGDG, travado por pin e `apt-mark hold` |
| Docker | Engine, Buildx e Compose do repositório oficial; `daemon.json` com as redes, rotação de logs e limpeza do cache de build |
| Ajustes | `conf.d/90-pginstall.conf` proporcional à memória e aos núcleos (20% para o cache: os containers dividem a máquina); o `ALTER SYSTEM` vale por cima |
| pg_hba.conf | um bloco marcado no fim: os containers entram com senha (scram-sha-256), o `postgres` nunca; o resto do arquivo fica como está |
| Pasta | `/docker` do grupo docker (setgid) e um `SERVIDOR.md` com as versões e o jeito de criar o banco de um projeto |
| Verificação | pgvector com índice HNSW e busca iterativa, login com senha pela ponte do Docker, `postgres` recusado, um container alcançando o Postgres |

Requisitos: Ubuntu 24.04 ou 26.04 (amd64 ou arm64), 2 GB de memória (4 recomendados), 10 GB livres e acesso a
`apt.postgresql.org`, `download.docker.com` e ao Docker Hub (o teste final usa a imagem `alpine`).

## Cuidados

- **Nada é apagado nem desinstalado.** Um conflito (Docker do Ubuntu ou do snap, outro PostgreSQL) para a
  instalação e diz o que fazer.
- **Rodar de novo é seguro:** o que já está feito é conferido e mantido; um `daemon.json` existente não é tocado.
  O Postgres só reinicia se um ajuste pedir, e pergunta antes se houver conexões abertas.
- **Senha nunca em claro num comando.** O login do teste recebe o verificador SCRAM, e o `pg_stat_statements` não
  guarda comandos utilitários (um `ALTER ROLE ... PASSWORD` ficaria lá com a senha).
- A rede local não ganha acesso ao banco. Para liberar alguém de fora, acrescente uma linha `hostssl` com usuário e
  banco, fora do bloco do pginstall.srv.
- O registro completo de cada execução fica em `/var/log/pginstall.srv/` (permissão 600).

## Testes

`teste/rodar.sh [26.04|24.04]` sobe um Ubuntu descartável com systemd num container privilegiado e roda o
instalador: a recusa por redes cruzadas, o `--checar`, a instalação e uma segunda execução que não pode mudar nada.

## Licença

[MIT](LICENSE)
