#!/usr/bin/env bash
# Testa o install.sh num Ubuntu descartável: um container privilegiado com systemd, que faz papel de servidor novo.
# Nada do host é alterado além dos containers, da rede e dos volumes do teste, apagados no fim. O Docker de dentro
# guarda imagens e containers em volumes (/var/lib/docker e /var/lib/containerd): overlay sobre overlay não monta.
#
#   teste/rodar.sh              Ubuntu 26.04
#   teste/rodar.sh 24.04        outra versão (no 24.04 o PostgreSQL 18 vem do PGDG)
#   teste/rodar.sh 26.04 --manter   deixa o container de pé para olhar (docker exec -it pgi-teste-26.04 bash)
#
# Roteiro: (1) --checar num container ligado à rede padrão do Docker precisa recusar (as redes cruzam);
# (2) --checar no servidor de teste; (3) a instalação; (4) a segunda instalação não muda nada.
# Precisa de Docker no host e de internet (apt e Docker Hub).

set -Eeuo pipefail

UBUNTU=${1:-26.04}
MANTER=${2:-}
RAIZ=$(cd "$(dirname "$0")/.." && pwd)
NOME=pgi-teste-$UBUNTU
IMAGEM=pginstall-teste:$UBUNTU
REDE=pgi-teste-$UBUNTU
SUBREDE=10.251.${UBUNTU%%.*}.0/24   # uma por versão (testes em paralelo), fora das redes do Docker de dentro

SAIDA=$(mktemp -d)
passo() { printf '\n\e[1m### %s\e[0m\n' "$*"; }
limpar_docker() {
	docker rm -f "$NOME" "$NOME-conflito" >/dev/null 2>&1 || true
	docker volume rm "$NOME-docker" "$NOME-containerd" >/dev/null 2>&1 || true
	docker network rm "$REDE" >/dev/null 2>&1 || true
}
limpar() {
	rm -rf "$SAIDA"
	if [[ $MANTER != --manter ]]; then limpar_docker; fi
}
trap limpar EXIT

passo "imagem do servidor de teste (Ubuntu $UBUNTU com systemd, sem as listas do apt, como um servidor recém-instalado)"
docker build -q -t "$IMAGEM" - <<EOF >/dev/null
FROM ubuntu:$UBUNTU
RUN apt-get update && apt-get install -y --no-install-recommends systemd systemd-sysv dbus iproute2 sudo \
      ca-certificates curl python3 util-linux && useradd -m -s /bin/bash teste && rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
EOF

subir() { # nome rede
	docker run -d --name "$1" --hostname "$1" --network "$2" --privileged --cgroupns=host \
		-v /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /run/lock \
		-v "$NOME-docker:/var/lib/docker" -v "$NOME-containerd:/var/lib/containerd" \
		-v "$RAIZ:/pginstall:ro" "$IMAGEM" >/dev/null
	for _ in $(seq 1 60); do
		case $(docker exec "$1" systemctl is-system-running 2>/dev/null || true) in running | degraded) return 0 ;; esac
		sleep 1
	done
	echo "o systemd do container $1 não subiu" >&2
	return 1
}
limpar_docker   # sobras de um teste anterior
docker network create --subnet "$SUBREDE" "$REDE" >/dev/null

passo "1. redes cruzadas: na rede padrão do Docker (172.17.0.0/16) o --checar precisa recusar"
subir "$NOME-conflito" bridge
if docker exec "$NOME-conflito" /pginstall/install.sh --checar --usuario teste >"$SAIDA/conflito.txt" 2>&1; then
	cat "$SAIDA/conflito.txt"
	echo "FALHOU: o --checar deveria recusar redes cruzadas" >&2
	exit 1
fi
if ! grep -q 'cruza com 172.17.0.0/16' "$SAIDA/conflito.txt"; then
	cat "$SAIDA/conflito.txt"
	echo "FALHOU: recusou, mas não pelas redes cruzadas" >&2
	exit 1
fi
echo "ok: recusou ($(grep -c 'cruza' "$SAIDA/conflito.txt") rede(s) cruzada(s))"
docker rm -f "$NOME-conflito" >/dev/null

passo "2. --checar no servidor de teste"
subir "$NOME" "$REDE"
docker exec "$NOME" /pginstall/install.sh --checar --usuario teste

passo "3. instalação"
docker exec "$NOME" /pginstall/install.sh --sim --usuario teste --disco ssd

passo "4. de novo: nada pode mudar"
docker exec "$NOME" /pginstall/install.sh --sim --usuario teste --disco ssd | tee "$SAIDA/segunda.txt"
if ! grep -q 'ajustes sem mudança' "$SAIDA/segunda.txt" || ! grep -q 'pg_hba.conf sem mudança' "$SAIDA/segunda.txt"; then
	echo "FALHOU: a segunda execução mudou os ajustes ou o pg_hba.conf" >&2
	exit 1
fi
[[ $(docker exec "$NOME" grep -c '>>> pginstall.srv' /etc/postgresql/18/main/pg_hba.conf) == 1 ]] ||
	{ echo "FALHOU: o bloco do pg_hba.conf foi duplicado" >&2; exit 1; }
echo "ok: segunda execução sem mudança e um só bloco no pg_hba.conf"

passo "Tudo certo no Ubuntu $UBUNTU"
