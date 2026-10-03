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
nunca entra de outra máquina. Cria o **seu** superusuário de administração e deixa o
[pgtower](https://github.com/9level/pgtower) instalado e apontado para o servidor: terminou, é digitar `pgtower`.
Antes de mudar qualquer coisa, confere a máquina e mostra o plano; no fim, prova que tudo responde.

**Da mesma família, da 9Level:** o pgrunway é a pista, onde o servidor decola; o
[pgtower](https://github.com/9level/pgtower) é a torre, que administra a frota; o
[pghangar](https://github.com/9level/pghangar) é o hangar, onde as cópias dos bancos são preparadas. O pgrunway já
deixa as duas ferramentas no servidor.

## Para quem é

| É para você se | Não é para você se |
|---|---|
| vai pôr um PostgreSQL no ar numa máquina nova (bare metal ou VM) | quer o banco num serviço gerenciado (RDS, Cloud SQL) |
| quer a mesma instalação, conferida e repetível, em cada servidor | o servidor não é Ubuntu 24.04 ou 26.04 |
| usa ou vai usar pgvector (busca por similaridade, RAG) | precisa de replicação ou alta disponibilidade |

## Siga-me: da máquina zerada ao servidor administrado

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

Cada etapa mostra o que fez. A verificação final confere o pgvector com um índice HNSW, o SSL, o seu superusuário
(com a senha e sem senha) e o pgtower; depois apaga o banco e o login que criou para o teste.

<p align="center"><img src="docs/img/instalacao.png" alt="Etapas da instalação, a verificação final e como administrar" width="820"></p>

Se algo estiver errado, ele para **antes** de mudar qualquer coisa e diz o que fazer. Aqui, a máquina já tinha o
PostgreSQL 16 do Ubuntu:

<p align="center"><img src="docs/img/recusa.png" alt="Conferência recusando a instalação: já há PostgreSQL 16 na máquina" width="820"></p>

### 3. Administre

O superusuário de administração tem o nome do seu usuário Linux (quem rodou o `sudo`); rodando como root direto, ele
se chama `dba`. A senha fica no seu `~/.pgpass`, que só você lê, e rodar o pgrunway de novo não a troca.

| Daqui do servidor | Como |
|---|---|
| pgtower | `pgtower`: já abre este servidor, sem senha |
| psql | `psql -d postgres`, sem senha |

**De outra máquina** (o pgtower na sua estação, uma ferramenta de cópia, um restore): libere o IP dela com uma linha
no fim do `/etc/postgresql/18/main/pg_hba.conf` e recarregue. O resumo final já mostra a linha com o IP de onde veio
a sua sessão SSH:

```
hostssl all deploy 10.0.0.50/32 scram-sha-256
```

```bash
sudo systemctl reload postgresql
```

Na estação, `postgres://deploy@IP-DO-SERVIDOR:5432/postgres?sslmode=require`, com a senha do `~/.pgpass` do servidor.
Sem abrir nada na rede, um túnel SSH também serve: `ssh -L 5432:127.0.0.1:5432 deploy@servidor`.

### 4. Cópias e restores com o pghangar

O pghangar copia bancos entre servidores (a produção para um dev ou homolog, por exemplo) por `pg_dump` e
`pg_restore` em containers, e restaura um dump de fora.

**Este servidor recebe as cópias:** `sudo ./install.sh --com-docker` instala o Docker e o pghangar. Depois,
`sudo pghangar`: na aba 6, `b` baixa as imagens do PostgreSQL e `g` gera a chave SSH; na aba 3, cadastre a origem
(acesso `ssh`) e este servidor como destino: `127.0.0.1:5432`, o seu superusuário e a senha do `~/.pgpass`.

**O pghangar está em outra máquina** e este servidor é a origem ou o destino dele: cole no `~/.ssh/authorized_keys`
do seu usuário a linha que o pghangar mostra (aba 6, tecla `l`). Ela só abre o túnel até a porta do banco, mais
nada. No cadastro dele: acesso `ssh`, banco `127.0.0.1:5432`, o seu superusuário e a senha do `~/.pgpass`.

### 5. Bancos de aplicações (opcional)

Para uma aplicação, um login **dono** do banco dela, sem superusuário, e a rede dela liberada como acima:

```bash
sudo -u postgres psql -c "CREATE ROLE app LOGIN" -c "\password app"
sudo -u postgres psql -c "CREATE DATABASE app OWNER app"
```

```
hostssl all app 10.0.10.0/24 scram-sha-256
```

### 6. Aplicações em containers nesta mesma máquina (opcional)

`sudo ./install.sh --com-docker` instala também o Docker Engine e o Compose oficiais (e o pghangar), libera as
redes do Docker no `pg_hba.conf` (com senha) e cria a pasta `/docker`. A verificação final entra no Postgres de dentro de containers. No `compose.yaml`:

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
| `--com-docker` | instala também o Docker e o pghangar, para containers e cópias nesta máquina |
| `-y`, `--sim` | não pergunta (automação) |

Raramente: `--usuario NOME` (outro usuário Linux como administrador), `--pg N` (outra versão do PostgreSQL),
`--pgvector X.Y.Z` (versão exata do pgvector), `--disco ssd` (quando a máquina virtual não diz que o disco é SSD) e,
com `--com-docker`, `--pasta`, `--docker-bip` e `--docker-pool`. Detalhes: `./install.sh --ajuda`.

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
- **O pgtower e o pghangar** vêm em versões fixas, com o SHA256 do release conferido. Sem acesso ao GitHub, o banco
  fica pronto do mesmo jeito e só as ferramentas ficam para depois (`PGR_PGTOWER_BASE` e `PGR_PGHANGAR_BASE` apontam
  para um espelho). Um `config.yml` do pgtower que já existe não é tocado (o servidor entra pela tecla `l`). O
  pghangar só tem binário para amd64.
- **O registro** de cada execução fica em `/var/log/pgrunway/`.

## Desenvolvimento

`teste/rodar.sh [26.04|24.04]` roda o instalador num Ubuntu descartável (container com systemd): as recusas, a
instalação com o superusuário e o pgtower, uma aplicação liberada no `pg_hba.conf`, o mesmo servidor ganhando
`--com-docker` com o pghangar e as repetições, que não podem mudar nada, nem a senha. É o que o [CI](.github/workflows/ci.yml) roda a cada mudança. As imagens são de uma execução
real (`docs/demo/capturar.sh` e `docs/demo/gravar.sh`). Mudanças: [CHANGELOG.md](CHANGELOG.md).

## Licença

[MIT](LICENSE) © 9Level
