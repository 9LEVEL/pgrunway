# Mudanças

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
