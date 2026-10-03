<h1 align="center">pgrunway</h1>

<p align="center"><strong>A pista de decolagem do seu servidor PostgreSQL: da máquina zerada ao banco no ar,<br>
conferido antes de mudar qualquer coisa e testado no fim.</strong></p>

<p align="center">
  <a href="https://github.com/9LEVEL/pgrunway/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/9LEVEL/pgrunway/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Ubuntu 24.04 e 26.04" src="https://img.shields.io/badge/Ubuntu-24.04%20%7C%2026.04-E95420?logo=ubuntu&logoColor=white">
  <img alt="PostgreSQL 18" src="https://img.shields.io/badge/PostgreSQL-18-4169E1?logo=postgresql&logoColor=white">
  <img alt="pgvector travado" src="https://img.shields.io/badge/pgvector-travado-336791">
  <img alt="Docker opcional" src="https://img.shields.io/badge/Docker-opcional-2496ED?logo=docker&logoColor=white">
  <a href="LICENSE"><img alt="Licença MIT" src="https://img.shields.io/badge/licen%C3%A7a-MIT-blue.svg"></a>
</p>

<p align="center"><img src="docs/img/demo.gif" alt="install.sh num Ubuntu 26.04 recém-instalado: conferência, plano, instalação e verificação" width="820"></p>

O `install.sh` faz a primeira instalação de um servidor PostgreSQL numa máquina Ubuntu nova, física ou virtual:
PostgreSQL e pgvector (com a versão travada), ajustes proporcionais à memória e aos núcleos e um `pg_hba.conf` em
que só entra quem você liberar, com senha, e o superusuário `postgres` nunca pela rede. Antes de mudar qualquer
coisa, ele confere a máquina e mostra o plano; no fim, prova que o banco responde como deveria.

## Para quem é

| É para você se | Não é para você se |
|---|---|
| vai pôr um PostgreSQL no ar numa máquina nova (bare metal ou VM) | quer o banco num serviço gerenciado (RDS, Cloud SQL) |
| quer a mesma instalação, conferida e repetível, em cada servidor | o servidor é Debian, RHEL ou outro que não seja Ubuntu |
| usa ou vai usar pgvector (busca por similaridade, RAG) | precisa de replicação, alta disponibilidade ou um cluster |
| roda as aplicações noutras máquinas ou em containers na mesma (`--com-docker`) | quer o PostgreSQL dentro de um container |

## Siga-me: da máquina zerada à primeira aplicação

### 1. Antes de começar

- Ubuntu Server **24.04 ou 26.04** recém-instalado (amd64 ou arm64), com um usuário que tenha `sudo`.
- 2 GB de memória (4 GB ou mais recomendados) e 10 GB livres.
- Acesso a `apt.postgresql.org` (e, com `--com-docker`, a `download.docker.com` e ao Docker Hub).
- A rede de onde as aplicações vão conectar, por exemplo `10.0.10.0/24`.

### 2. Baixe

```bash
git clone https://github.com/9LEVEL/pgrunway.git
cd pgrunway
```

Sem git: `curl -fsSL https://github.com/9LEVEL/pgrunway/archive/refs/tags/v0.3.0.tar.gz | tar xz && cd pgrunway-0.3.0`

### 3. Confira a máquina (não muda nada)

```bash
sudo ./install.sh --checar --liberar 10.0.10.0/24
```

Ele confere o sistema, a memória, o disco, o repositório do PostgreSQL, outro PostgreSQL ou a porta 5432 ocupada,
mostra o plano e sai.

### 4. Instale

```bash
sudo ./install.sh --atualizar-sistema --liberar 10.0.10.0/24
```

`--atualizar-sistema` roda um `apt upgrade` antes, o recomendado num servidor recém-instalado. `--liberar` diz de
onde as aplicações entram; sem ele, o Postgres só atende a própria máquina. Esta é a tela inicial: o que ele vai
fazer, a conferência e o plano. **Nada muda até você responder `s`.**

<p align="center"><img src="docs/img/inicio.png" alt="Tela inicial: explicação, conferência da máquina, plano e a pergunta Seguir com a instalação" width="820"></p>

### 5. Acompanhe até o fim

Cada etapa mostra o que fez. A verificação final cria um banco e um login temporários: confere o pgvector com um
índice HNSW, entra com senha (scram-sha-256) e confere que as redes liberadas exigem SSL. Depois apaga tudo o que
criou para o teste.

<p align="center"><img src="docs/img/instalacao.png" alt="Etapas da instalação e a verificação final" width="820"></p>

### 6. Se algo estiver errado, ele para e explica

Um problema encontrado na conferência para tudo antes de qualquer mudança, com o que fazer. Aqui, a máquina já tinha
o PostgreSQL 16 do Ubuntu:

<p align="center"><img src="docs/img/recusa.png" alt="Conferência recusando a instalação: já há PostgreSQL 16 na máquina" width="820"></p>

### 7. Crie o banco da primeira aplicação

Cada aplicação tem o seu login, **dono** do banco dela, sem superusuário. A senha entra pelo `\password`, que manda
só o hash ao servidor:

```bash
sudo -u postgres psql -c "CREATE ROLE app LOGIN" -c "\password app"
sudo -u postgres psql -c "CREATE DATABASE app OWNER app"
sudo -u postgres psql -d app -c "CREATE EXTENSION vector"   # o pgvector não é "trusted": cria como postgres
```

A aplicação, numa máquina de `10.0.10.0/24`, conecta com SSL:

```
postgres://app:SENHA@IP-DO-SERVIDOR:5432/app?sslmode=require
```

### 8. Aplicações em containers nesta mesma máquina (opcional)

Com `--com-docker`, o pgrunway instala também o Docker Engine e o Compose oficiais, libera as redes dele no
`pg_hba.conf` (com senha; o `postgres` nunca) e cria a pasta `/docker`, uma por projeto. A verificação final entra no
Postgres **de dentro de containers**, pela ponte padrão e por uma rede do Compose.

```bash
sudo ./install.sh --liberar 10.0.10.0/24 --com-docker
```

No `compose.yaml`, o container chega ao Postgres do host por `host.docker.internal`:

```yaml
services:
  app:
    image: minha-app:1.0
    extra_hosts: ["host.docker.internal:host-gateway"]
    environment:
      DATABASE_URL: postgres://app:${DB_PASSWORD}@host.docker.internal:5432/app
```

Se a sua rede já usa 172.17 ou 172.18, troque as do Docker com `--docker-bip` e `--docker-pool`.

### 9. Mais tarde

- **Rodar de novo é seguro:** o que já está feito é conferido e mantido; o Postgres só reinicia se um ajuste pedir,
  e pergunta antes se houver conexões abertas.
- **`--liberar` é a lista completa:** a cada execução o bloco do `pg_hba.conf` é refeito com as redes passadas.
  Para acrescentar uma, repita as que já estavam: `--liberar 10.0.10.0/24 --liberar 10.0.20.0/24`.
- **Trocar o pgvector:** `--pgvector 0.8.6` troca a versão travada; depois, `ALTER EXTENSION vector UPDATE` em cada
  banco.
- **O registro completo** de cada execução fica em `/var/log/pgrunway/` (permissão 600).
- **Para administrar** o servidor no dia a dia (sessões, locks, logins, `pg_hba.conf`, ajustes), veja o
  [pgtower](https://github.com/9level/pgtower).

## O que ele instala e configura

| | O quê |
|---|---|
| PostgreSQL | do Ubuntu quando ele tem a versão pedida (o 26.04 tem a 18), senão do [PGDG](https://wiki.postgresql.org/wiki/Apt) |
| pgvector | do PGDG, travado por pin e `apt-mark hold`: um `apt upgrade` não troca a extensão dos bancos |
| Ajustes | `/etc/postgresql/<versão>/main/conf.d/90-pgrunway.conf`, proporcional à máquina: 25% da memória para o cache num servidor só de banco, 20% com `--com-docker`; `pg_stat_statements` ligado. O `ALTER SYSTEM` vale por cima |
| `pg_hba.conf` | um bloco marcado no fim: as redes de `--liberar` só com SSL e senha, as do Docker com senha, o `postgres` nunca pela rede; o resto do arquivo fica como está |
| Escuta | só a própria máquina enquanto nada estiver liberado; em todas as interfaces com `--liberar` ou `--com-docker` (o `pg_hba.conf` decide quem entra) |
| Docker (opcional) | Engine, Buildx e Compose oficiais, `daemon.json` com as redes e rotação de logs, pasta `/docker` do grupo docker |

## Opções

| Opção | Para quê |
|---|---|
| `--checar` | só confere a máquina e mostra o plano; não muda nada |
| `--atualizar-sistema` | `apt upgrade` antes de tudo |
| `-y`, `--sim` | não pergunta (automação) |
| `--liberar CIDR` | rede de onde as aplicações entram, só com SSL e senha; repita para mais de uma |
| `--pg N` | versão principal do PostgreSQL (padrão: 18) |
| `--pgvector X.Y.Z` | versão exata do pgvector (padrão: a mais nova na primeira instalação) |
| `--disco ssd\|hdd` | tipo do disco, quando a detecção erra (comum em máquina virtual) |
| `--com-docker` | instala o Docker e libera as redes dele, para projetos em containers nesta máquina |
| `--usuario NOME`, `--pasta CAMINHO` | com `--com-docker`: quem entra no grupo docker e a pasta dos projetos (padrão: quem chamou o `sudo`, `/docker`) |
| `--docker-bip CIDR`, `--docker-pool CIDR` | com `--com-docker`: as redes do Docker (padrão: 172.17.0.0/16 e 172.18.0.0/16) |
| `--cloudflared` | com `--com-docker`: prepara `/docker/cloudflare` para um Cloudflare Tunnel |

## Segurança

- **Nada é apagado nem desinstalado.** Um conflito (outro PostgreSQL, a porta ocupada, o Docker do Ubuntu ou do
  snap) para a instalação e diz o que fazer; quem remove é você.
- **Ninguém entra pela rede sem ser liberado**, e as redes liberadas exigem SSL e senha. `--liberar 0.0.0.0/0` é
  recusado: diga de que redes as aplicações vêm.
- **Senha nunca em claro num comando.** O login do teste recebe o verificador SCRAM, e o `pg_stat_statements` não
  guarda comandos utilitários: um `ALTER ROLE ... PASSWORD` ficaria lá com a senha.
- **O `pg_hba.conf` anterior fica copiado** em `pg_hba.conf.antes-pgrunway`, e um `daemon.json` que já existe não é
  tocado.

## Perguntas frequentes

**Por que o Docker é opcional?** Num servidor só de banco ele não tem função: as aplicações ficam noutras máquinas.
Ele entra com `--com-docker` quando as aplicações rodam em containers na mesma máquina do banco.

**O certificado SSL é autoassinado.** É o que o Ubuntu cria na instalação (`ssl-cert-snakeoil`): basta para
`sslmode=require`. Para `verify-full`, troque `ssl_cert_file` e `ssl_key_file` por um certificado da sua CA.

**Funciona em Debian?** Ainda não: os repositórios e os testes são do Ubuntu 24.04 e 26.04.

**Como conecto o DBeaver?** Por túnel SSH até o servidor e `localhost:5432`, com um login que não seja o `postgres`;
ou de uma rede liberada, com SSL.

## Desenvolvimento

- `teste/rodar.sh [26.04|24.04]` sobe um Ubuntu descartável com systemd num container privilegiado e roda o
  instalador: as recusas, o `--checar`, um servidor só de banco, o mesmo servidor ganhando `--com-docker` e as
  execuções repetidas, que não podem mudar nada. É o que o [CI](.github/workflows/ci.yml) roda a cada mudança.
- As imagens deste README são de uma execução real (`docs/demo/capturar.sh`), reproduzida com o
  [VHS](https://github.com/charmbracelet/vhs) (`docs/demo/gravar.sh`).
- Mudanças por versão: [CHANGELOG.md](CHANGELOG.md).

## Licença

[MIT](LICENSE) © 9Level
