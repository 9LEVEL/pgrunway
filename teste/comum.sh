# shellcheck shell=bash
# Servidor descartável (Ubuntu ou Debian) para o teste e para a captura das imagens do README: um container
# privilegiado com systemd. O Docker de dentro guarda imagens e containers em volumes (/var/lib/docker e
# /var/lib/containerd), porque overlay sobre overlay não monta. Carregado por teste/rodar.sh e docs/demo/capturar.sh.
#
# SISTEMA, nos parâmetros abaixo: a versão do Ubuntu (26.04, 24.04) ou debian-N (debian-13).

RAIZ=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

imagem_base() {
	case $1 in
	debian-*) echo "debian:${1#debian-}" ;;
	*) echo "ubuntu:$1" ;;
	esac
}

nome_sistema() {
	case $1 in
	debian-*) echo "Debian ${1#debian-}" ;;
	*) echo "Ubuntu $1" ;;
	esac
}

# construir_imagem SISTEMA: o sistema com systemd, sem as listas do apt, como um servidor recém-instalado
construir_imagem() {
	docker build -q -t "pgrunway-teste:$1" - <<-EOF >/dev/null
		FROM $(imagem_base "$1")
		RUN apt-get update && apt-get install -y --no-install-recommends systemd systemd-sysv dbus iproute2 sudo \
		      ca-certificates curl python3 util-linux procps && useradd -m -s /bin/bash teste && rm -rf /var/lib/apt/lists/*
		STOPSIGNAL SIGRTMIN+3
		CMD ["/sbin/init"]
	EOF
}

# subir NOME REDE SISTEMA [ARGS...]: liga o servidor e espera o systemd. ARGS vão para o docker run (um disco
# montado em /var/lib/postgresql, por exemplo).
subir() {
	local nome=$1 rede=$2 sistema=$3
	shift 3
	docker run -d --name "$nome" --hostname "$nome" --network "$rede" --privileged --cgroupns=host \
		-v /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /run/lock \
		-v "$nome-docker:/var/lib/docker" -v "$nome-containerd:/var/lib/containerd" \
		-v "$RAIZ:/pgrunway:ro" "$@" "pgrunway-teste:$sistema" >/dev/null
	for _ in $(seq 1 60); do
		case $(docker exec "$nome" systemctl is-system-running 2>/dev/null || true) in running | degraded) return 0 ;; esac
		sleep 1
	done
	echo "o systemd do container $nome não subiu" >&2
	return 1
}

# derrubar NOME...: apaga os containers e os volumes deles
derrubar() {
	local n
	for n in "$@"; do
		docker rm -f "$n" >/dev/null 2>&1 || true
		docker volume rm "$n-docker" "$n-containerd" >/dev/null 2>&1 || true
	done
}
