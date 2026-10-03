<h1 align="center">pgrunway</h1>

<p align="center"><strong>A pista de decolagem do seu servidor PostgreSQL: da máquina zerada ao banco no ar,<br>
com um comando, conferido antes e testado no fim.</strong></p>

<p align="center">
  <a href="https://github.com/9LEVEL/pgrunway/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/9LEVEL/pgrunway/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="Ubuntu 24.04 e 26.04" src="https://img.shields.io/badge/Ubuntu-24.04%20%7C%2026.04-E95420?logo=ubuntu&logoColor=white">
  <img alt="PostgreSQL 18" src="https://img.shields.io/badge/PostgreSQL-18-4169E1?logo=postgresql&logoColor=white">
  <img alt="pgvector travado" src="https://img.shields.io/badge/pgvector-travado-336791">
  <img alt="Docker opcional" src="https://img.shields.io/badge/Docker-opcional-2496ED?logo=docker&logoColor=white">
  <a href="LICENSE"><img alt="Licença MIT" src="https://img.shields.io/badge/licen%C3%A7a-MIT-blue.svg"></a>
</p>

<p align="center"><img src="docs/img/demo.gif" alt="install.sh num Ubuntu 26.04 recém-instalado: conferência, plano, instalação e verificação" width="820"></p>

```bash
git clone https://github.com/9LEVEL/pgrunway.git && cd pgrunway
sudo ./install.sh
```

Numa máquina Ubuntu nova, física ou virtual, o `install.sh` atualiza o sistema, instala o PostgreSQL e o pgvector
(com a versão travada), ajusta o Postgres ao tamanho da máquina e fecha o `pg_hba.conf`: o superusuário `postgres`
nunca entra de outra máquina. Antes de mudar qualquer coisa, confere a máquina e mostra o plano; no fim, prova que o
banco responde como deveria.

## Para quem é

| É para você se | Não é para você se |
|---|---|
| vai pôr um PostgreSQL no ar numa máquina nova (bare metal ou VM) | quer o banco num serviço gerenciado (RDS, Cloud SQL) |
| quer a mesma instalação, conferida e repetível, em cada servidor | o servidor não é Ubuntu 24.04 ou 26.04 |
| usa ou vai usar pgvector (busca por similaridade, RAG) | precisa de replicação ou alta disponibilidade |

## Siga-me: da máquina zerada à primeira aplicação

### 1. Instale

Num Ubuntu Server **24.04 ou 26.04** recém-instalado (amd64 ou arm64), com 2 GB de memória ou mais e acesso a
`apt.postgresql.org`:

```bash
git clone https://github.com/9LEVEL/pgrunway.git && cd pgrunway
sudo ./install.sh
```

Esta é a tela inicial: o que ele vai fazer, a conferência da máquina e o plano. **Nada muda até você responder
`s`.** Para só conferir, sem instalar: `sudo ./install.sh --checar`.

<p align="center"><img src="docs/img/inicio.png" alt="Tela inicial: explicação, conferência da máquina, plano e a pergunta Seguir com a instalação" width="820"></p>

### 2. Acompanhe até o fim

Cada etapa mostra o que fez. A verificação final cria um banco e um login temporários, confere o pgvector com um
índice HNSW, entra com senha e confere o SSL; depois apaga tudo o que criou. No fim, os comandos do próximo passo.

<p align="center"><img src="docs/img/instalacao.png" alt="Etapas da instalação, a verificação final e o próximo passo" width="820"></p>

Se algo estiver errado, ele para **antes** de mudar qualquer coisa e diz o que fazer. Aqui, a máquina já tinha o
PostgreSQL 16 do Ubuntu:

<p align="center"><img src="docs/img/recusa.png" alt="Conferência recusando a instalação: já há PostgreSQL 16 na máquina" width="820"></p>

### 3. Crie o banco da primeira aplicação

Cada aplicação tem o seu login, **dono** do banco dela, sem superusuário. O `\password` pede a senha e manda só o
hash ao servidor:

```bash
sudo -u postgres psql -c "CREATE ROLE app LOGIN" -c "\password app"
sudo -u postgres psql -c "CREATE DATABASE app OWNER app"
sudo -u postgres psql -d app -c "CREATE EXTENSION vector"
```

### 4. Libere a rede da aplicação

De fábrica, só a própria máquina entra. Se a aplicação está noutra máquina, acrescente uma linha **no fim** do
`/etc/postgresql/18/main/pg_hba.conf`, com a rede dela, e recarregue:

```
hostssl all all 10.0.10.0/24 scram-sha-256
```

```bash
sudo systemctl reload postgresql
```

A aplicação conecta com SSL: `postgres://app:SENHA@IP-DO-SERVIDOR:5432/app?sslmode=require`

### 5. Aplicações em containers nesta mesma máquina (opcional)

`sudo ./install.sh --com-docker` instala também o Docker Engine e o Compose oficiais, libera as redes dele no
`pg_hba.conf` (com senha) e cria a pasta `/docker`. A verificação final entra no Postgres de dentro de containers.
No `compose.yaml`:

```yaml
services:
  app:
    image: minha-app:1.0
    extra_hosts: ["host.docker.internal:host-gateway"]
    environment:
      DATABASE_URL: postgres://app:${DB_PASSWORD}@host.docker.internal:5432/app
```

## Opções

Sem opção nenhuma é o caso comum.

| Opção | Para quê |
|---|---|
| `--checar` | só confere a máquina e mostra o plano; não muda nada |
| `--com-docker` | instala também o Docker, para projetos em containers nesta máquina |
| `-y`, `--sim` | não pergunta (automação) |

Raramente: `--pg N` (outra versão do PostgreSQL), `--pgvector X.Y.Z` (versão exata do pgvector), `--disco ssd`
(quando a máquina virtual não diz que o disco é SSD) e, com `--com-docker`, `--usuario`, `--pasta`, `--docker-bip`
e `--docker-pool`. Detalhes: `./install.sh --ajuda`.

## Bom saber

- **Nada é apagado nem desinstalado.** Um conflito (outro PostgreSQL, a porta ocupada, o Docker do Ubuntu) para a
  instalação e diz o que fazer.
- **Rodar de novo é seguro:** confere e mantém o que já está feito, não atualiza o sistema de novo e regrava o
  bloco do pgrunway no `pg_hba.conf` **no mesmo lugar**, sem tocar nas linhas que você acrescentou.
- **Os ajustes** ficam em `/etc/postgresql/18/main/conf.d/90-pgrunway.conf` (25% da memória para o cache; 20% com
  Docker). O `ALTER SYSTEM` vale por cima.
- **O pgvector fica travado:** um `apt upgrade` não troca a extensão dos bancos. Para trocar: `--pgvector X.Y.Z` e,
  depois, `ALTER EXTENSION vector UPDATE` em cada banco.
- **O certificado SSL é o autoassinado do Ubuntu:** basta para `sslmode=require`; para `verify-full`, troque por um
  da sua CA.
- **O registro** de cada execução fica em `/var/log/pgrunway/`. Para administrar o servidor no dia a dia, veja o
  [pgtower](https://github.com/9level/pgtower).

## Desenvolvimento

`teste/rodar.sh [26.04|24.04]` roda o instalador num Ubuntu descartável (container com systemd): as recusas, a
instalação, uma aplicação liberada no `pg_hba.conf`, o mesmo servidor ganhando `--com-docker` e as repetições, que
não podem mudar nada. É o que o [CI](.github/workflows/ci.yml) roda a cada mudança. As imagens são de uma execução
real (`docs/demo/capturar.sh` e `docs/demo/gravar.sh`). Mudanças: [CHANGELOG.md](CHANGELOG.md).

## Licença

[MIT](LICENSE) © 9Level
