#!/usr/bin/env bash
# Testa o install.sh num Ubuntu descartável (teste/comum.sh): um container privilegiado com systemd, que faz papel
# de servidor novo. Nada do host é alterado além dos containers, das redes e dos volumes do teste, apagados no fim.
#
#   teste/rodar.sh                  Ubuntu 26.04
#   teste/rodar.sh 24.04            outra versão (no 24.04 o PostgreSQL 18 vem do PGDG)
#   teste/rodar.sh 26.04 --manter   deixa o container de pé para olhar (docker exec -it pgr-teste-26.04 bash)
#
# Roteiro: (1) o que a conferência precisa recusar; (2) --checar; (3) instalação de um servidor só de banco, com
# --liberar; (4) a mesma de novo, sem mudar nada; (5) o mesmo servidor ganhando --com-docker; (6) de novo, sem mudar.
# Precisa de Docker no host e de internet (apt, Docker Hub e o repositório do Alpine).

set -Eeuo pipefail

UBUNTU=${1:-26.04}
MANTER=${2:-}
# shellcheck source=teste/comum.sh
. "$(dirname "$0")/comum.sh"
NOME=pgr-teste-$UBUNTU
REDE=pgr-teste-$UBUNTU
SUBREDE=10.251.${UBUNTU%%.*}.0/24   # uma por versão (testes em paralelo), fora das redes do Docker de dentro
HBA=/etc/postgresql/18/main/pg_hba.conf
SAIDA=$(mktemp -d)

passo() { printf '\n\e[1m### %s\e[0m\n' "$*"; }
falhou() {
	echo "FALHOU: $*" >&2
	exit 1
}
limpar_docker() {
	derrubar "$NOME" "$NOME-conflito"
	docker network rm "$REDE" >/dev/null 2>&1 || true
}
limpar() {
	rm -rf "$SAIDA"
	if [[ $MANTER != --manter ]]; then limpar_docker; fi
}
trap limpar EXIT

# recusa ARQUIVO MENSAGEM OPÇÕES...: o --checar tem de sair com erro e dizer MENSAGEM
recusa() {
	local arq=$SAIDA/$1 msg=$2
	shift 2
	if docker exec "$NOME-conflito" /pgrunway/install.sh --checar "$@" >"$arq" 2>&1; then
		cat "$arq"
		falhou "o --checar deveria recusar: $*"
	fi
	if ! grep -q -- "$msg" "$arq"; then
		cat "$arq"
		falhou "recusou ($*), mas sem dizer: $msg"
	fi
	if grep -q 'erro inesperado' "$arq"; then
		cat "$arq"
		falhou "recusou ($*) por um erro inesperado, não pela conferência"
	fi
	echo "ok: recusou $* ($msg)"
}

# instalar ARQUIVO OPÇÕES...: instala e guarda a saída
instalar() {
	local arq=$SAIDA/$1
	shift
	docker exec "$NOME" /pgrunway/install.sh --sim --disco ssd "$@" | tee "$arq"
	if grep -q 'erro inesperado' "$arq"; then falhou "erro inesperado na instalação ($*)"; fi
}

# sem_mudanca ARQUIVO: a segunda execução não pode mexer nos ajustes nem no pg_hba.conf
sem_mudanca() {
	if ! grep -q 'ajustes sem mudança' "$SAIDA/$1" || ! grep -q 'pg_hba.conf sem mudança' "$SAIDA/$1"; then
		falhou "a segunda execução mudou os ajustes ou o pg_hba.conf"
	fi
	if [[ $(docker exec "$NOME" grep -c '>>> pgrunway' "$HBA") != 1 ]]; then falhou "o bloco do pg_hba.conf foi duplicado"; fi
	echo "ok: sem mudança e um só bloco no pg_hba.conf"
}

passo "servidor de teste: Ubuntu $UBUNTU com systemd, sem as listas do apt, como um recém-instalado"
construir_imagem "$UBUNTU"
limpar_docker # sobras de um teste anterior
docker network create --subnet "$SUBREDE" "$REDE" >/dev/null

passo "1. o que a conferência precisa recusar (container na rede padrão do Docker, 172.17.0.0/16)"
subir "$NOME-conflito" bridge "$UBUNTU"
recusa redes.txt 'cruza com a do Docker (172.17.0.0/16)' --com-docker --usuario teste
recusa mundo.txt 'a internet inteira não' --liberar 0.0.0.0/0
recusa sem-docker.txt 'só com --com-docker' --usuario teste
if ! docker exec "$NOME-conflito" /pgrunway/install.sh --checar --com-docker --usuario teste \
	--docker-bip 10.200.0.1/16 --docker-pool 10.201.0.0/16 >"$SAIDA/outras-redes.txt" 2>&1; then
	cat "$SAIDA/outras-redes.txt"
	falhou "com --docker-bip e --docker-pool o --checar deveria aceitar"
fi
echo "ok: com --docker-bip e --docker-pool fora da rede da máquina, aceitou"
derrubar "$NOME-conflito"

passo "2. --checar"
subir "$NOME" "$REDE" "$UBUNTU"
docker exec "$NOME" /pgrunway/install.sh --checar --liberar "$SUBREDE"

passo "3. servidor só de banco, com as aplicações de $SUBREDE liberadas"
instalar so-banco.txt --liberar "$SUBREDE"
if docker exec "$NOME" sh -c 'command -v docker' >/dev/null; then falhou "sem --com-docker, o Docker não deveria estar instalado"; fi
if ! docker exec "$NOME" grep -q "^hostssl all             all             $SUBREDE" "$HBA"; then
	falhou "a rede liberada não está no pg_hba.conf"
fi
if [[ $(docker exec "$NOME" runuser -u postgres -- psql -XAtc "show listen_addresses") != '*' ]]; then
	falhou "listen_addresses deveria ser *"
fi
echo "ok: sem Docker, $SUBREDE liberada só com SSL e senha, Postgres escutando na rede"

passo "4. de novo: nada pode mudar"
instalar so-banco-2.txt --liberar "$SUBREDE"
sem_mudanca so-banco-2.txt

passo "5. o mesmo servidor ganha --com-docker"
instalar com-docker.txt --liberar "$SUBREDE" --com-docker --usuario teste
if ! grep -q 'de um container na rede do Compose' "$SAIDA/com-docker.txt"; then
	falhou "faltou a verificação de dentro dos containers"
fi

passo "6. de novo: nada pode mudar"
instalar com-docker-2.txt --liberar "$SUBREDE" --com-docker --usuario teste
sem_mudanca com-docker-2.txt

passo "Tudo certo no Ubuntu $UBUNTU"
