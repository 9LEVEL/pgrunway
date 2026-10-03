<h1 align="center">pginstall.srv</h1>

<p align="center"><strong>Um servidor Ubuntu pronto para rodar projetos em Docker, com PostgreSQL + pgvector no host.<br>
Um comando, conferido antes e testado no fim.</strong></p>

<p align="center">
  <a href="https://github.com/9LEVEL/pginstall.srv/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/9LEVEL/pginstall.srv/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Ubuntu 24.04 e 26.04" src="https://img.shields.io/badge/Ubuntu-24.04%20%7C%2026.04-E95420?logo=ubuntu&logoColor=white">
  <img alt="PostgreSQL 18" src="https://img.shields.io/badge/PostgreSQL-18-4169E1?logo=postgresql&logoColor=white">
  <img alt="pgvector travado" src="https://img.shields.io/badge/pgvector-travado-336791">
  <img alt="Docker oficial" src="https://img.shields.io/badge/Docker-oficial-2496ED?logo=docker&logoColor=white">
  <a href="LICENSE"><img alt="Licença MIT" src="https://img.shields.io/badge/licen%C3%A7a-MIT-blue.svg"></a>
</p>

<p align="center"><img src="docs/img/demo.gif" alt="install.sh num Ubuntu 26.04 recém-instalado: conferência, plano, instalação e verificação" width="820"></p>

O `install.sh` deixa um Ubuntu recém-instalado pronto para receber projetos em containers: instala o PostgreSQL e o
pgvector no host, o Docker oficial, ajusta o Postgres ao tamanho da máquina, libera os containers no `pg_hba.conf`
(só com senha, nunca como `postgres`) e cria a pasta dos projetos. Antes de mudar qualquer coisa, confere a máquina
e mostra o plano; no fim, prova que um container consegue entrar no banco.

## Para quem é

> **Para servidores que rodam os projetos em containers Docker.** O Docker faz parte da instalação, e o PostgreSQL
> fica no próprio host, fora dos containers. Se os seus projetos não usam Docker, ou se você quer o PostgreSQL
> dentro de um container, este não é o instalador certo.

| É para você se | Não é para você se |
|---|---|
| os projetos sobem com `docker compose` e falam com um PostgreSQL | o servidor não vai ter Docker |
| quer um PostgreSQL por servidor, no host, compartilhado pelos projetos | quer o banco num container ou num serviço gerenciado (RDS, Cloud SQL) |
| usa ou vai usar pgvector (busca por similaridade, RAG) | o servidor é Debian, RHEL ou outro que não seja Ubuntu |
| quer a mesma instalação repetível em cada servidor novo | precisa de replicação, alta disponibilidade ou um cluster |

## Siga-me: do servidor zerado ao primeiro projeto

### 1. Antes de começar

- Ubuntu Server **24.04 ou 26.04** recém-instalado (amd64 ou arm64), com um usuário que tenha `sudo`.
- 2 GB de memória (4 GB ou mais recomendados) e 10 GB livres.
- Acesso a `apt.postgresql.org`, `download.docker.com` e ao Docker Hub; o teste final usa a imagem `alpine` e o
  repositório do Alpine.

### 2. Baixe

```bash
git clone https://github.com/9LEVEL/pginstall.srv.git
cd pginstall.srv
```

Sem git: `curl -fsSL https://github.com/9LEVEL/pginstall.srv/archive/refs/tags/v0.2.0.tar.gz | tar xz && cd pginstall.srv-0.2.0`

### 3. Confira a máquina (não muda nada)

```bash
sudo ./install.sh --checar
```

Ele confere o sistema, a memória, o disco, os repositórios, pacotes que brigam com o Docker oficial, outro
PostgreSQL ou a porta 5432 ocupada, e se as redes do Docker cruzam com as da máquina. Mostra o plano e sai.

### 4. Instale

```bash
sudo ./install.sh --atualizar-sistema
```

`--atualizar-sistema` roda um `apt upgrade` antes, o recomendado num servidor recém-instalado. Esta é a tela
inicial: o que ele vai fazer, a conferência da máquina e o plano. **Nada muda até você responder `s`.**

<p align="center"><img src="docs/img/inicio.png" alt="Tela inicial: explicação, conferência da máquina, plano e a pergunta Seguir com a instalação" width="820"></p>

### 5. Acompanhe até o fim

Cada etapa mostra o que fez. A verificação final cria um banco, um login e uma rede temporários e entra no Postgres
**de dentro de um container**, pela ponte padrão do Docker e por uma rede do Compose, do jeito que os seus
projetos vão entrar; confere também que o `postgres` é recusado. Depois apaga tudo o que criou para o teste.

<p align="center"><img src="docs/img/instalacao.png" alt="Etapas da instalação e a verificação a partir de containers" width="820"></p>

### 6. Se algo estiver errado, ele para e explica

Um problema encontrado na conferência para tudo antes de qualquer mudança, com o que fazer. Aqui, a rede da máquina
cruza com a que o Docker usaria:

<p align="center"><img src="docs/img/recusa.png" alt="Conferência recusando a instalação: a rede da máquina cruza com a do Docker" width="820"></p>

### 7. Crie o banco do primeiro projeto

Cada projeto tem o seu login, **dono** do banco dele, sem superusuário. A senha entra pelo `\password`, que manda só
o hash ao servidor:

```bash
sudo -u postgres psql -c "CREATE ROLE app LOGIN"
sudo -u postgres psql -c "\password app"
sudo -u postgres psql -c "CREATE DATABASE app OWNER app"
sudo -u postgres psql -d app -c "CREATE EXTENSION vector"   # o pgvector não é "trusted": cria como postgres
```

No `compose.yaml` do projeto, o container chega ao Postgres do host por `host.docker.internal`:

```yaml
services:
  app:
    image: minha-app:1.0
    extra_hosts: ["host.docker.internal:host-gateway"]
    environment:
      DATABASE_URL: postgres://app:${DB_PASSWORD}@host.docker.internal:5432/app
```

O usuário que rodou o `sudo` entrou no grupo `docker`: saia e entre de novo para usar `docker` sem `sudo`. O
resumo do servidor fica em `/docker/SERVIDOR.md`.

### 8. Mais tarde

- **Rodar de novo é seguro:** o que já está feito é conferido e mantido; o Postgres só reinicia se um ajuste pedir,
  e pergunta antes se houver conexões abertas.
- **Trocar o pgvector:** `sudo ./install.sh --pgvector 0.8.6` troca a versão travada; depois,
  `ALTER EXTENSION vector UPDATE` em cada banco.
- **O registro completo** de cada execução fica em `/var/log/pginstall.srv/` (permissão 600).

## O que ele instala e configura

| | O quê |
|---|---|
| PostgreSQL | do Ubuntu quando ele tem a versão pedida (o 26.04 tem a 18), senão do [PGDG](https://wiki.postgresql.org/wiki/Apt) |
| pgvector | do PGDG, travado por pin e `apt-mark hold`: um `apt upgrade` não troca a extensão dos bancos |
| Docker | Engine, Buildx e Compose do repositório oficial; `daemon.json` com as redes, rotação de logs e limpeza do cache de build |
| Ajustes | `/etc/postgresql/<versão>/main/conf.d/90-pginstall.conf`, proporcional à memória e aos núcleos (20% da memória para o cache, porque os containers dividem a máquina); o `ALTER SYSTEM` vale por cima |
| `pg_hba.conf` | um bloco marcado no fim: as redes do Docker entram com senha (scram-sha-256), o `postgres` nunca; o resto do arquivo fica como está |
| Pasta | `/docker` do grupo docker (setgid), uma pasta por projeto, e um `SERVIDOR.md` com as versões e os comandos acima |

## Opções

| Opção | Para quê |
|---|---|
| `--checar` | só confere a máquina e mostra o plano; não muda nada |
| `--atualizar-sistema` | `apt upgrade` antes de tudo |
| `-y`, `--sim` | não pergunta (automação) |
| `--pg N` | versão principal do PostgreSQL (padrão: 18) |
| `--pgvector X.Y.Z` | versão exata do pgvector (padrão: a mais nova na primeira instalação) |
| `--pasta CAMINHO` | pasta dos projetos (padrão: `/docker`) |
| `--usuario NOME` | quem entra no grupo docker e fica dono da pasta (padrão: quem chamou o `sudo`) |
| `--docker-bip CIDR` e `--docker-pool CIDR` | redes do Docker, quando as padrão (172.17.0.0/16 e 172.18.0.0/16) cruzam com as da sua rede |
| `--disco ssd\|hdd` | tipo do disco, quando a detecção erra (comum em máquina virtual) |
| `--cloudflared` | prepara `/docker/cloudflare` para um Cloudflare Tunnel (sobe quando o token estiver no `.env`) |

## Segurança

- **Nada é apagado nem desinstalado.** Um conflito (Docker do Ubuntu ou do snap, outro PostgreSQL) para a
  instalação e diz o que fazer; quem remove é você.
- **A rede local não ganha acesso ao banco.** Só as redes do Docker, com senha. Para liberar alguém de fora, uma
  linha `hostssl` com usuário e banco, fora do bloco do pginstall.srv.
- **Senha nunca em claro num comando.** O login do teste recebe o verificador SCRAM, e o `pg_stat_statements` não
  guarda comandos utilitários: um `ALTER ROLE ... PASSWORD` ficaria lá com a senha.
- **Um `daemon.json` que já existe não é tocado**, e o `pg_hba.conf` anterior fica copiado em
  `pg_hba.conf.antes-pginstall`.

## Perguntas frequentes

**Por que o PostgreSQL fora do Docker?** Um banco por servidor, compartilhado pelos projetos, com a memória e o disco
ajustados para ele, atualizações de segurança pelo `apt` e backup com as ferramentas de sempre. Os projetos
continuam isolados em containers, cada um com o seu login e o seu banco.

**Já tenho Docker instalado.** Se for o oficial (`docker-ce`), ele fica como está, e o `daemon.json` também. Se for
o do Ubuntu (`docker.io`) ou o do snap, a conferência para e mostra como remover.

**A rede da empresa usa 172.17 ou 172.18.** Use `--docker-bip` e `--docker-pool` com outras faixas; a conferência
avisa quando as redes cruzam.

**Funciona em Debian?** Ainda não: os repositórios e os testes são do Ubuntu 24.04 e 26.04.

**Como conecto o DBeaver?** Por túnel SSH até o servidor e `localhost:5432` no DBeaver, com um login que não seja o
`postgres`.

## Desenvolvimento

- `teste/rodar.sh [26.04|24.04]` sobe um Ubuntu descartável com systemd num container privilegiado e roda o
  instalador: a recusa por redes cruzadas, o `--checar`, a instalação e uma segunda execução que não pode mudar
  nada. É o que o [CI](.github/workflows/ci.yml) roda a cada mudança, nas duas versões.
- As imagens deste README são de uma execução real (`docs/demo/capturar.sh`), reproduzida com o
  [VHS](https://github.com/charmbracelet/vhs) (`docs/demo/gravar.sh`).
- Mudanças por versão: [CHANGELOG.md](CHANGELOG.md).

## Licença

[MIT](LICENSE) © 9Level
