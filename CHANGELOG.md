# Mudanças

## 0.6.1 (06/10/2026)

**O fim da instalação ensina a usar, e sai mais uma opção.**

- O resumo final vira um guia, **Como usar**: quem administra, os comandos daqui (no seu usuário ou depois de um
  `sudo -i`), como entrar da sua estação, passo a passo, e o banco de uma aplicação. Fica também no
  `~/pgrunway.txt` de quem administra e no registro.
- O pgtower do root também abre o servidor: depois de um `sudo -i`, `pgtower` entra como quem administra, com a
  senha lida do `.pgpass` dele (sem cópia). O `config.yml` gerado pelo pgrunway é regravado ao rodar de novo; um que
  o pgtower já regravou fica como está.
- Sai `--disco`: o tipo do disco é detectado. Numa máquina virtual, o disco que se diz rotativo (o "QEMU HARDDISK"
  do KVM, por exemplo) recebe os ajustes de SSD; por baixo, quase sempre é SSD ou um storage com cache.
- Correção: a verificação do pgtower dava às vezes um aviso falso ("o pgtower não listou este servidor", com um
  `Broken pipe` no registro). O `grep -q` fechava o pipe antes de o pgtower terminar de escrever.
- Correção: o cabeçalho do `90-pgrunway.conf` tinha a data; rodando de novo noutro dia, o arquivo era regravado sem
  nada mudar.

## 0.6.0 (03/10/2026)

- Com `--com-docker`, instala também o [pghangar](https://github.com/9level/pghangar) (versão fixa, SHA256 do
  release conferido), que copia e restaura bancos entre servidores em containers. Fica em `/opt/pghangar` e em
  `/usr/local/bin`; o resumo final mostra como começar (`sudo pghangar`).
- `PGR_PGTOWER_BASE` e `PGR_PGHANGAR_BASE` apontam os downloads para um espelho (`file://` também serve).
- O `SERVIDOR.md` da pasta `/docker` diz quem administra e como usar as ferramentas.
- README: a família pgrunway, pgtower e pghangar e como usar o pghangar daqui ou de outra máquina.
- Correção: o `max_wal_size` dependia do espaço livre no disco, que muda; rodando de novo, a configuração podia ir e
  voltar (e pedir reinício). Agora depende do tamanho do disco.

## 0.5.0 (03/10/2026)

**Sai pronto para administrar.**

- Cria o seu superusuário de administração, com o nome do seu usuário Linux (quem rodou o `sudo`; como root direto,
  `dba`). Entra pelo socket sem senha; a senha, para entrar de outra máquina, fica no `~/.pgpass`, só seu. Rodar de
  novo não a troca. `--usuario` passa a valer sempre: quem administra.
- Baixa o [pgtower](https://github.com/9level/pgtower) (versão fixa, SHA256 conferido) e deixa este servidor
  cadastrado no `config.yml` de quem administra, com a memória e os núcleos: é digitar `pgtower`.
- O resumo final mostra como administrar e a linha do `pg_hba.conf` com o IP da sua estação, de onde veio o SSH.
- Sai do caminho principal o banco da primeira aplicação; fica como passo opcional no README.

## 0.4.0 (03/10/2026)

**Menos opções: o caso comum é `sudo ./install.sh`, sem nada.**

- Sai `--liberar`: a rede de uma aplicação se libera com uma linha no fim do `pg_hba.conf`, como em qualquer
  PostgreSQL; o resumo final e o README mostram a linha.
- Sai `--atualizar-sistema`: a primeira instalação atualiza o sistema sozinha (e avisa se ele pedir reinício);
  rodando de novo, não.
- Sai `--cloudflared`.
- O `postgres` não entra de nenhuma outra máquina (`reject` para 0.0.0.0/0 e ::/0), com ou sem Docker.
- O bloco do pgrunway no `pg_hba.conf` é regravado no mesmo lugar: as linhas acrescentadas depois dele ficam.
- O Postgres escuta em todas as interfaces; quem entra é o `pg_hba.conf` que decide.

## 0.3.0 (03/10/2026)

**O nome passa a ser pgrunway** (antes pginstall.srv), e o foco, o servidor PostgreSQL.

- **Docker opcional** (`--com-docker`): sem ele, nada de Docker, pasta `/docker` ou redes de containers no
  `pg_hba.conf`. `--usuario`, `--pasta`, `--docker-bip`, `--docker-pool` e `--cloudflared` só valem com ele.
- **`--liberar CIDR`**: as redes de onde as aplicações entram, só com SSL e senha, e o `postgres` nunca. Sem nada
  liberado (nem Docker), o Postgres só escuta na própria máquina. `--liberar 0.0.0.0/0` é recusado.
- Servidor só de banco: 25% da memória para o cache e 75% de cache do sistema (com `--com-docker`, 20% e 60%).
- A verificação entra com senha pela rede da própria máquina e confere o SSL das redes liberadas; os testes de
  dentro de containers ficam para `--com-docker`.
- Novos nomes: `conf.d/90-pgrunway.conf`, `/etc/apt/preferences.d/pgrunway-pgdg`, `/var/log/pgrunway/`, bloco
  `pgrunway` no `pg_hba.conf` e variáveis `PGR_DOCKER_BIP`, `PGR_DOCKER_POOL` e `PGR_CLOUDFLARED_IMAGEM`.
- Mensagens em até 92 colunas; o resumo final mostra os comandos para criar o banco de uma aplicação.

## 0.2.0 (03/10/2026)

- A tela inicial diz que o instalador é para projetos em **containers Docker**, com o PostgreSQL no host.
- `--docker-bip` e `--docker-pool` trocam as redes do Docker quando elas cruzam com as da máquina; a recusa mostra
  um exemplo.
- Mensagens em até 100 colunas e o resumo final com as versões curtas.
- README com passo a passo e imagens de uma execução real; CI com shellcheck e a instalação completa no Ubuntu
  24.04 e 26.04.

## 0.1.0 (03/10/2026)

Primeira versão: conferência da máquina, PostgreSQL e pgvector travado, Docker oficial, ajustes proporcionais,
`pg_hba.conf` para as redes do Docker, pasta dos projetos e verificação a partir de containers.
