# shellcheck shell=bash
# Servidor Ubuntu descartável para o teste e para a captura das imagens do README: um container privilegiado com
# systemd. O Docker de dentro guarda imagens e containers em volumes (/var/lib/docker e /var/lib/containerd), porque
# overlay sobre overlay não monta. Carregado por teste/rodar.sh e docs/demo/capturar.sh.

RAIZ=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# construir_imagem VERSÃO: Ubuntu com systemd, sem as listas do apt, como um servidor recém-instalado
construir_imagem() {
	docker build -q -t "pginstall-teste:$1" - <<-EOF >/dev/null
		FROM ubuntu:$1
		RUN apt-get update && apt-get install -y --no-install-recommends systemd systemd-sysv dbus iproute2 sudo \
		      ca-certificates curl python3 util-linux && useradd -m -s /bin/bash teste && rm -rf /var/lib/apt/lists/*
		STOPSIGNAL SIGRTMIN+3
		CMD ["/sbin/init"]
	EOF
}

# subir NOME REDE VERSÃO: liga o servidor e espera o systemd
subir() {
	docker run -d --name "$1" --hostname "$1" --network "$2" --privileged --cgroupns=host \
		-v /sys/fs/cgroup:/sys/fs/cgroup:rw --tmpfs /run --tmpfs /run/lock \
		-v "$1-docker:/var/lib/docker" -v "$1-containerd:/var/lib/containerd" \
		-v "$RAIZ:/pginstall:ro" "pginstall-teste:$3" >/dev/null
	for _ in $(seq 1 60); do
		case $(docker exec "$1" systemctl is-system-running 2>/dev/null || true) in running | degraded) return 0 ;; esac
		sleep 1
	done
	echo "o systemd do container $1 não subiu" >&2
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
