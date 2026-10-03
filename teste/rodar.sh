#!/usr/bin/env bash
# Testa o install.sh num Ubuntu descartável (teste/comum.sh): um container privilegiado com systemd, que faz papel
# de servidor novo. Nada do host é alterado além dos containers, das redes e dos volumes do teste, apagados no fim.
#
#   teste/rodar.sh                  Ubuntu 26.04
#   teste/rodar.sh 24.04            outra versão (no 24.04 o PostgreSQL 18 vem do PGDG)
#   teste/rodar.sh 26.04 --manter   deixa o container de pé para olhar (docker exec -it pgi-teste-26.04 bash)
#
# Roteiro: (1) num container ligado à rede padrão do Docker o --checar precisa recusar (as redes cruzam) e aceitar
# com --docker-bip e --docker-pool em outras redes;
# (2) --checar no servidor de teste; (3) a instalação; (4) a segunda instalação não muda nada.
# Precisa de Docker no host e de internet (apt, Docker Hub e o repositório do Alpine).

set -Eeuo pipefail

UBUNTU=${1:-26.04}
MANTER=${2:-}
# shellcheck source=teste/comum.sh
. "$(dirname "$0")/comum.sh"
NOME=pgi-teste-$UBUNTU
REDE=pgi-teste-$UBUNTU
SUBREDE=10.251.${UBUNTU%%.*}.0/24   # uma por versão (testes em paralelo), fora das redes do Docker de dentro
SAIDA=$(mktemp -d)

passo() { printf '\n\e[1m### %s\e[0m\n' "$*"; }
limpar_docker() {
	derrubar "$NOME" "$NOME-conflito"
	docker network rm "$REDE" >/dev/null 2>&1 || true
}
limpar() {
	rm -rf "$SAIDA"
	if [[ $MANTER != --manter ]]; then limpar_docker; fi
}
trap limpar EXIT

passo "imagem do servidor de teste (Ubuntu $UBUNTU com systemd, sem as listas do apt, como um servidor recém-instalado)"
construir_imagem "$UBUNTU"
limpar_docker # sobras de um teste anterior
docker network create --subnet "$SUBREDE" "$REDE" >/dev/null

passo "1. redes cruzadas: na rede padrão do Docker (172.17.0.0/16) o --checar precisa recusar"
subir "$NOME-conflito" bridge "$UBUNTU"
if docker exec "$NOME-conflito" /pginstall/install.sh --checar --usuario teste >"$SAIDA/conflito.txt" 2>&1; then
	cat "$SAIDA/conflito.txt"
	echo "FALHOU: o --checar deveria recusar redes cruzadas" >&2
	exit 1
fi
if ! grep -q 'cruza com a do Docker (172.17.0.0/16)' "$SAIDA/conflito.txt"; then
	cat "$SAIDA/conflito.txt"
	echo "FALHOU: recusou, mas não pelas redes cruzadas" >&2
	exit 1
fi
echo "ok: recusou ($(grep -c 'cruza' "$SAIDA/conflito.txt") rede(s) cruzada(s))"
if ! docker exec "$NOME-conflito" /pginstall/install.sh --checar --usuario teste \
	--docker-bip 10.200.0.1/16 --docker-pool 10.201.0.0/16 >"$SAIDA/outras-redes.txt" 2>&1; then
	cat "$SAIDA/outras-redes.txt"
	echo "FALHOU: com --docker-bip e --docker-pool o --checar deveria aceitar" >&2
	exit 1
fi
echo "ok: com --docker-bip e --docker-pool fora da rede da máquina, aceitou"
derrubar "$NOME-conflito"

passo "2. --checar no servidor de teste"
subir "$NOME" "$REDE" "$UBUNTU"
docker exec "$NOME" /pginstall/install.sh --checar --usuario teste

passo "3. instalação"
docker exec "$NOME" /pginstall/install.sh --sim --usuario teste --disco ssd

passo "4. de novo: nada pode mudar"
docker exec "$NOME" /pginstall/install.sh --sim --usuario teste --disco ssd | tee "$SAIDA/segunda.txt"
if ! grep -q 'ajustes sem mudança' "$SAIDA/segunda.txt" || ! grep -q 'pg_hba.conf sem mudança' "$SAIDA/segunda.txt"; then
	echo "FALHOU: a segunda execução mudou os ajustes ou o pg_hba.conf" >&2
	exit 1
fi
if [[ $(docker exec "$NOME" grep -c '>>> pginstall.srv' /etc/postgresql/18/main/pg_hba.conf) != 1 ]]; then
	echo "FALHOU: o bloco do pg_hba.conf foi duplicado" >&2
	exit 1
fi
echo "ok: segunda execução sem mudança e um só bloco no pg_hba.conf"

passo "Tudo certo no Ubuntu $UBUNTU"
