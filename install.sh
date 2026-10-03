#!/usr/bin/env bash
# pginstall.srv: prepara um servidor Ubuntu para receber projetos em containers com o PostgreSQL no próprio host.
# Instala o PostgreSQL e o pgvector (travado numa versão), o Docker Engine oficial, ajusta o Postgres ao tamanho da
# máquina, libera as redes do Docker no pg_hba.conf e cria a pasta dos projetos. Termina conferindo tudo com um
# banco e um login temporários, apagados no fim.
#
#   sudo ./install.sh              explica, confere a máquina, mostra o plano e pede confirmação
#   sudo ./install.sh --checar     só confere a máquina e mostra o plano; não muda nada
#   sudo ./install.sh --ajuda      opções
#
# Pode rodar de novo no mesmo servidor: o que já está feito é conferido e mantido. Nada é apagado nem
# desinstalado. Detalhes no README.md.

set -Eeuo pipefail

VERSAO=0.1.0
NOME=pginstall.srv

# ---------------------------------------------------------------------------------------------------------------
# Opções

PG=18
PGVECTOR=""                    # vazio: a mais nova do PGDG na primeira instalação; depois, a que estiver instalada
PASTA=/docker
USUARIO=${SUDO_USER:-}
DISCO=auto                     # auto | ssd | hdd
CHECAR=0
SIM=0
ATUALIZAR=0
CLOUDFLARED=0
# Redes do Docker (daemon.json): a ponte padrão e de onde saem as redes do Compose. O pg_hba.conf libera as duas.
DOCKER_BIP=${PGI_DOCKER_BIP:-172.17.0.1/16}
DOCKER_POOL=${PGI_DOCKER_POOL:-172.18.0.0/16}
CLOUDFLARED_IMAGEM=${PGI_CLOUDFLARED_IMAGEM:-cloudflare/cloudflared:2026.9.3}

ajuda() {
	cat <<EOF
$NOME $VERSAO: prepara um servidor Ubuntu com PostgreSQL + pgvector no host e Docker para os projetos.

Uso: sudo ./install.sh [opções]

  --checar              só confere a máquina e mostra o plano; não muda nada
  -y, --sim             não pergunta antes de instalar (para automação)
  --pg N                versão principal do PostgreSQL (padrão: $PG)
  --pgvector X.Y.Z      versão exata do pgvector, travada (padrão: a mais nova, travada no que instalar)
  --pasta CAMINHO       pasta dos projetos (padrão: $PASTA)
  --usuario NOME        usuário que entra no grupo docker e fica dono da pasta (padrão: quem chamou o sudo)
  --disco ssd|hdd       tipo do disco, quando a detecção erra (comum em máquina virtual)
  --atualizar-sistema   roda um apt upgrade antes (recomendado num servidor recém-instalado)
  --cloudflared         prepara <pasta>/cloudflare para um Cloudflare Tunnel (não sobe sem o token)
  -h, --ajuda           esta ajuda

Variáveis de ambiente:
  PGI_DOCKER_BIP=$DOCKER_BIP       rede da ponte padrão do Docker
  PGI_DOCKER_POOL=$DOCKER_POOL     de onde saem as redes do Compose (blocos /24)
  PGI_CLOUDFLARED_IMAGEM=$CLOUDFLARED_IMAGEM
EOF
}

# ---------------------------------------------------------------------------------------------------------------
# Saída: tela resumida, registro completo em $LOG

if [[ -t 1 ]]; then
	B=$'\e[1m' G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' D=$'\e[2m' N=$'\e[0m'
else
	B='' G='' Y='' R='' D='' N=''
fi
LOG=''
ANTES_DO_LOG=''   # o que aconteceu antes do registro existir (a conferência), gravado nele quando nasce
AVISOS=()
ERROS=()

registrar() {
	if [[ -n $LOG ]]; then printf '%s\n' "$*" >>"$LOG"; else ANTES_DO_LOG+="$*"$'\n'; fi
}
titulo() { printf '\n%s\n' "${B}== $*${N}"; registrar "== $*"; }
info() { printf '  %s\n' "$*"; registrar "  $*"; }
ok() { printf '  %s %s\n' "${G}✓${N}" "$*"; registrar "  ok: $*"; }
aviso() { printf '  %s %s\n' "${Y}!${N}" "$*"; registrar "  aviso: $*"; AVISOS+=("$*"); }
erro() { printf '  %s %s\n' "${R}✗${N}" "$*"; registrar "  erro: $*"; ERROS+=("$*"); }
die() {
	printf '%s %s\n' "${R}✗${N}" "$*" >&2
	registrar "fatal: $*"
	exit 1
}

# rodar: a saída do comando vai só para o registro; se falhar, mostra o fim dele e para.
rodar() {
	registrar "\$ $*"
	if ! "$@" >>"${LOG:-/dev/null}" 2>&1; then
		printf '%s falhou: %s\n' "${R}✗${N}" "$*" >&2
		tail -n 20 "$LOG" | sed 's/^/    /' >&2
		die "registro completo: $LOG"
	fi
}

# shellcheck disable=SC2329 # chamada pelo trap ERR, logo abaixo
falha_inesperada() {
	printf '%s erro inesperado (linha %s, saída %s). Registro: %s\n' "${R}✗${N}" "$2" "$1" "${LOG:-ainda não criado}" >&2
	exit 1
}
trap 'falha_inesperada $? $LINENO' ERR

export DEBIAN_FRONTEND=noninteractive
# Espera até 10 minutos por outro apt (atualização automática, por exemplo) em vez de falhar.
apt_get() { rodar apt-get -y -q -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"; }

pgsql() { runuser -u postgres -- psql -X -At -v ON_ERROR_STOP=1 "$@"; }

instalado() { [[ $(dpkg-query -W -f='${Status}' "$1" 2>/dev/null) == "install ok installed" ]]; }
versao_instalada() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null; }

# rede_de 172.17.0.1/16 -> 172.17.0.0/16
rede_de() { python3 -c 'import ipaddress,sys; print(ipaddress.ip_network(sys.argv[1], strict=False))' "$1"; }

# scram: lê a senha na entrada e escreve o verificador SCRAM-SHA-256. A senha vai ao Postgres já assim: o texto do
# comando pode ficar no pg_stat_statements e nos logs, e nele nunca pode estar a senha em claro.
scram() {
	# shellcheck disable=SC2016 # é código Python, não shell
	python3 -c '
import base64, hashlib, hmac, os, sys
senha, sal, n = sys.stdin.buffer.read(), os.urandom(16), 4096
k = hashlib.pbkdf2_hmac("sha256", senha, sal, n)
b = lambda x: base64.b64encode(x).decode()
cli = hmac.new(k, b"Client Key", "sha256").digest()
srv = hmac.new(k, b"Server Key", "sha256").digest()
print(f"SCRAM-SHA-256${n}:{b(sal)}${b(hashlib.sha256(cli).digest())}:{b(srv)}")'
}

# Troca um arquivo só se o conteúdo mudou. Devolve 0 se trocou.
gravar_se_mudou() { # destino modo dono conteúdo
	local destino=$1 modo=$2 dono=$3 conteudo=$4 tmp
	if [[ -f $destino ]] && [[ $(cat "$destino") == "$conteudo" ]]; then
		return 1
	fi
	tmp=$(mktemp)
	printf '%s\n' "$conteudo" >"$tmp"
	install -m "$modo" -o "${dono%:*}" -g "${dono#*:}" "$tmp" "$destino"
	rm -f "$tmp"
	registrar "  gravado: $destino"
	return 0
}

ARGS=("$@")
while (($#)); do
	case $1 in
	--checar) CHECAR=1 ;;
	-y | --sim) SIM=1 ;;
	--pg) PG=${2:-} && shift ;;
	--pgvector) PGVECTOR=${2:-} && shift ;;
	--pasta) PASTA=${2:-} && shift ;;
	--usuario) USUARIO=${2:-} && shift ;;
	--disco) DISCO=${2:-} && shift ;;
	--atualizar-sistema) ATUALIZAR=1 ;;
	--cloudflared) CLOUDFLARED=1 ;;
	-h | --ajuda | --help) ajuda && exit 0 ;;
	*) die "opção desconhecida: $1 (veja --ajuda)" ;;
	esac
	shift
done
[[ $PG =~ ^[0-9]{2}$ ]] || die "--pg precisa da versão principal, ex.: --pg 18"
[[ -z $PGVECTOR || $PGVECTOR =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--pgvector precisa de uma versão X.Y.Z, ex.: --pgvector 0.8.1"
[[ $PASTA == /?* && $PASTA != *[[:space:]]* ]] || die "--pasta precisa de um caminho absoluto, sem espaços, ex.: /docker"
PASTA=${PASTA%/}
[[ -z $USUARIO || $USUARIO =~ ^[a-z_][a-z0-9_-]*$ ]] || die "--usuario inválido: $USUARIO"
[[ $DISCO =~ ^(auto|ssd|hdd)$ ]] || die "--disco aceita ssd ou hdd"

# ---------------------------------------------------------------------------------------------------------------
# 0. O que este script faz

explicar() {
	cat <<EOF
${B}$NOME $VERSAO${N}: prepara este servidor para projetos em containers, com o PostgreSQL no próprio host.

  1. Confere a máquina: sistema, memória, disco, redes e o que já está instalado
  2. PostgreSQL $PG e pgvector, com a versão do pgvector travada (um apt upgrade não troca)
  3. Docker Engine, Buildx e Compose, do repositório oficial do Docker
  4. Ajusta o Postgres ao tamanho da máquina e libera no pg_hba.conf as redes do Docker
     (o superusuário postgres nunca entra por elas; os outros logins, só com senha)
  5. Pasta dos projetos ($PASTA), do grupo docker
  6. Teste final com um banco e um login temporários, apagados no fim

${D}Nada é apagado nem desinstalado. Rodar de novo confere e mantém o que já está feito.${N}
EOF
}

# ---------------------------------------------------------------------------------------------------------------
# 1. Conferência da máquina

COD='' ARQ='' RAM_MB=0 CPUS=0 DISCO_GB=0 SSD=0 PG_ORIGEM='' PGPORT=5432
REDE_BIP='' REDE_POOL='' DAEMON_JSON_EXISTE=0

checar_maquina() {
	titulo "1. Conferência da máquina"

	[[ $EUID -eq 0 ]] || die "rode como root: sudo ./install.sh"

	# shellcheck source=/dev/null
	. /etc/os-release
	COD=${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}
	if [[ ${ID:-} != ubuntu || -z $COD ]]; then
		erro "sistema não suportado: ${PRETTY_NAME:-desconhecido} (este instalador é para Ubuntu)"
	else
		ok "sistema: $PRETTY_NAME ($COD)"
	fi
	ARQ=$(dpkg --print-architecture 2>/dev/null || uname -m)
	if [[ $ARQ == amd64 || $ARQ == arm64 ]]; then ok "arquitetura: $ARQ"; else erro "arquitetura não suportada: $ARQ (amd64 ou arm64)"; fi
	if [[ -d /run/systemd/system ]]; then ok "systemd ativo"; else erro "systemd não está rodando (os serviços do Postgres e do Docker dependem dele)"; fi

	RAM_MB=$(awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo)
	CPUS=$(nproc)
	if ((RAM_MB < 1900)); then
		erro "memória: ${RAM_MB} MB (mínimo 2 GB)"
	elif ((RAM_MB < 3800)); then
		aviso "memória: ${RAM_MB} MB, pouco para o Postgres e os containers juntos (recomendado: 4 GB ou mais)"
	else
		ok "memória: $((RAM_MB / 1024)) GB, $CPUS núcleo(s)"
	fi
	DISCO_GB=$(df -B1G --output=avail / | tail -n 1 | tr -d ' ')
	if ((DISCO_GB < 10)); then
		erro "disco: ${DISCO_GB} GB livres em / (mínimo 10 GB)"
	elif ((DISCO_GB < 30)); then
		aviso "disco: ${DISCO_GB} GB livres em / (bancos e imagens crescem; recomendado: 30 GB ou mais)"
	else
		ok "disco: ${DISCO_GB} GB livres em /"
	fi
	local rota
	rota=$(lsblk -nso ROTA "$(findmnt -no SOURCE /)" 2>/dev/null | tail -n 1 | tr -d ' ' || true)
	case $DISCO in
	ssd) SSD=1 ;;
	hdd) SSD=0 ;;
	*) [[ $rota == 0 ]] && SSD=1 || SSD=0 ;;
	esac
	if ((SSD)); then info "disco do sistema: SSD"; else info "disco do sistema: rotativo ou não informado (em máquina virtual sobre SSD, use --disco ssd)"; fi
	if lsblk -nso TYPE "$(findmnt -no SOURCE /)" 2>/dev/null | grep -qx crypt && ! instalado clevis-luks; then
		aviso "o disco do sistema é criptografado (LUKS) sem desbloqueio automático: a cada reinício alguém digita a senha no console"
	fi
	if [[ $(timedatectl show -p NTPSynchronized --value 2>/dev/null || true) != yes ]]; then
		aviso "relógio não sincronizado (NTP): certificados e o apt podem falhar com a hora errada"
	fi

	if ! command -v python3 >/dev/null; then
		erro "python3 não encontrado (vem em toda instalação do Ubuntu Server; usado para conferir redes e senhas)"
	fi

	# apt rodando agora (a atualização automática, por exemplo): a instalação espera
	local apt_pids
	apt_pids=$(pgrep -d, -x 'apt|apt-get|dpkg' || true)
	apt_pids+=$(pgrep -d, -f 'unattended-upgrade( |$)' | sed 's/^/,/' || true)
	apt_pids=${apt_pids#,}
	if [[ -n $apt_pids ]]; then
		aviso "o apt está em uso agora (pid $apt_pids): a instalação espera ele terminar"
	fi

	# repositórios alcançáveis para esta versão do Ubuntu
	if command -v curl >/dev/null; then
		if curl -fsSI -m 15 "https://apt.postgresql.org/pub/repos/apt/dists/${COD}-pgdg/Release" >/dev/null 2>&1; then
			ok "repositório do PostgreSQL (PGDG) tem o $COD"
		else
			erro "repositório do PostgreSQL (PGDG) não responde ou não tem o $COD (apt.postgresql.org)"
		fi
		if curl -fsSI -m 15 "https://download.docker.com/linux/ubuntu/dists/${COD}/Release" >/dev/null 2>&1; then
			ok "repositório do Docker tem o $COD"
		else
			erro "repositório do Docker não responde ou não tem o $COD (download.docker.com)"
		fi
	else
		info "curl ausente: os repositórios são conferidos depois de instalá-lo"
	fi

	checar_postgres
	checar_docker
	checar_pasta
}

checar_postgres() {
	local outras=() v
	for v in $(dpkg-query -W -f='${Package}\n' 'postgresql-[0-9]*' 2>/dev/null | sed -nE 's/^postgresql-([0-9]+)$/\1/p' || true); do
		if instalado "postgresql-$v" && [[ $v != "$PG" ]]; then outras+=("$v"); fi
	done
	if ((${#outras[@]})); then
		erro "já há PostgreSQL ${outras[*]} neste servidor: o $PG ficaria noutra porta. Use --pg ${outras[0]} ou um servidor novo"
	fi
	if instalado "postgresql-$PG"; then
		ok "PostgreSQL $PG já instalado ($(versao_instalada "postgresql-$PG")): fica, e os ajustes são conferidos"
		PGPORT=$(pg_conftool -s "$PG" main show port 2>/dev/null || echo 5432)
	elif ss -Hltn 'sport = :5432' 2>/dev/null | grep -q .; then
		erro "a porta 5432 já está em uso por outro programa: $(ss -Hltnp 'sport = :5432' | grep -o 'users:(("[^"]*' | head -n 1 | cut -d'"' -f2 || true)"
	fi

	decidir_origem

	if instalado "postgresql-$PG-pgvector"; then
		v=$(versao_instalada "postgresql-$PG-pgvector")
		if [[ -n $PGVECTOR && ${v%%-*} != "$PGVECTOR" ]]; then
			aviso "pgvector instalado: ${v%%-*}; pedido: $PGVECTOR. Ele é trocado, e cada banco precisa de ALTER EXTENSION vector UPDATE"
		else
			ok "pgvector já instalado: ${v%%-*} (fica travado)"
		fi
	fi
}

checar_docker() {
	local conflitos=() p
	# Pacotes que brigam com o Docker oficial (lista da documentação do Docker). Não removemos nada sozinhos.
	for p in docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc; do
		instalado "$p" && conflitos+=("$p")
	done
	if ((${#conflitos[@]})); then
		erro "pacotes que conflitam com o Docker oficial: ${conflitos[*]} (remova com: apt-get remove ${conflitos[*]})"
	fi
	if command -v snap >/dev/null && snap list docker >/dev/null 2>&1; then
		erro "Docker instalado pelo snap: remova antes (snap remove docker)"
	fi
	if instalado docker-ce; then
		ok "Docker já instalado ($(versao_instalada docker-ce)): fica como está"
	fi

	# As redes do Docker: as do daemon.json, se ele já existe; senão as do pginstall.srv
	if [[ -f /etc/docker/daemon.json ]]; then
		DAEMON_JSON_EXISTE=1
		local lidas
		if lidas=$(python3 -c '
import json, sys
d = json.load(open("/etc/docker/daemon.json"))
bip = d.get("bip", "")
pools = d.get("default-address-pools") or []
print(bip, pools[0]["base"] if pools else "")' 2>/dev/null) && [[ $lidas != " " ]]; then
			read -r bip pool <<<"$lidas"
			if [[ -n ${bip:-} ]]; then DOCKER_BIP=$bip; fi
			if [[ -n ${pool:-} ]]; then DOCKER_POOL=$pool; fi
			info "/etc/docker/daemon.json já existe e fica como está (redes: ${DOCKER_BIP} e ${DOCKER_POOL})"
			if [[ -z ${bip:-} || -z ${pool:-} ]]; then
				aviso "o daemon.json não define bip e default-address-pools: o pg_hba.conf libera $DOCKER_BIP e $DOCKER_POOL; confira se são as redes dos seus containers"
			fi
		else
			aviso "/etc/docker/daemon.json existe mas não foi lido: o pg_hba.conf libera $DOCKER_BIP e $DOCKER_POOL"
		fi
	fi
	if ! REDE_BIP=$(rede_de "$DOCKER_BIP") || ! REDE_POOL=$(rede_de "$DOCKER_POOL"); then
		erro "redes do Docker inválidas: $DOCKER_BIP e $DOCKER_POOL"
		return
	fi

	# As redes do Docker não podem cruzar com as da máquina: os containers perderiam a rota até ela
	local cruzam
	cruzam=$(python3 - "$REDE_BIP" "$REDE_POOL" <<-'EOF'
		import ipaddress, json, subprocess, sys
		docker = [ipaddress.ip_network(r) for r in sys.argv[1:]]
		def ip(*a):
		    return json.loads(subprocess.run(["ip", "-j", *a], capture_output=True, text=True).stdout or "[]")
		def nosso(dev):
		    return dev == "docker0" or dev.startswith(("br-", "veth"))
		achadas = set()
		for i in ip("-4", "addr"):
		    if nosso(i.get("ifname", "")):
		        continue
		    for a in i.get("addr_info", []):
		        achadas.add((ipaddress.ip_network(f'{a["local"]}/{a["prefixlen"]}', strict=False), i["ifname"]))
		for r in ip("-4", "route"):
		    if r.get("dst", "default") != "default" and not nosso(r.get("dev", "")):
		        achadas.add((ipaddress.ip_network(r["dst"] if "/" in r["dst"] else r["dst"] + "/32", strict=False), r.get("dev", "?")))
		for rede, dev in sorted(achadas, key=str):
		    for d in docker:
		        if rede.overlaps(d):
		            print(f"{rede} ({dev}) cruza com {d}")
	EOF
	) || true
	if [[ -n $cruzam ]]; then
		while IFS= read -r l; do erro "rede da máquina $l: escolha outras com PGI_DOCKER_BIP e PGI_DOCKER_POOL"; done <<<"$cruzam"
	else
		ok "redes do Docker livres: $REDE_BIP (ponte) e $REDE_POOL (Compose)"
	fi
}

checar_pasta() {
	if [[ -n $USUARIO ]]; then
		if id -u "$USUARIO" >/dev/null 2>&1; then
			ok "usuário dos projetos: $USUARIO"
		else
			erro "usuário $USUARIO não existe (use --usuario)"
		fi
	else
		aviso "nenhum usuário entra no grupo docker (rodando como root direto): use --usuario NOME"
	fi
	if [[ -e $PASTA && ! -d $PASTA ]]; then
		erro "$PASTA existe e não é uma pasta"
	elif [[ -d $PASTA ]] && [[ -n $(ls -A "$PASTA") ]]; then
		info "$PASTA já existe e tem conteúdo: dono e permissões ficam como estão"
	fi
}

# Do Ubuntu, quando ele tem a versão pedida; senão, do PGDG. Sem as listas do apt (servidor recém-instalado), a
# conferência não sabe: decide de novo depois do apt update.
decidir_origem() {
	if apt-cache madison "postgresql-$PG" 2>/dev/null | grep -v apt.postgresql.org | grep -q .; then
		PG_ORIGEM=ubuntu
	elif [[ -z $(find /var/lib/apt/lists -maxdepth 1 -name '*_Packages*' -print -quit 2>/dev/null) ]]; then
		PG_ORIGEM=''
	else
		PG_ORIGEM=pgdg
	fi
}

# ---------------------------------------------------------------------------------------------------------------
# Plano: os ajustes do Postgres, proporcionais à máquina (os containers dividem a memória com ele)

AJUSTES=''
calcular_ajustes() {
	local sb=$((RAM_MB * 20 / 100)) ec=$((RAM_MB * 60 / 100)) mwm=$((RAM_MB / 16)) wm=$((RAM_MB / 1000))
	local par=$((CPUS / 2)) mwp=$((CPUS > 8 ? CPUS : 8)) wal=4GB
	((sb < 128)) && sb=128
	((mwm > 2048)) && mwm=2048
	((mwm < 64)) && mwm=64
	((wm < 4)) && wm=4
	((wm > 64)) && wm=64
	((par < 1)) && par=1
	((par > 4)) && par=4
	((DISCO_GB < 50)) && wal=2GB
	AJUSTES="# Gerado pelo $NOME $VERSAO em $(date +%Y-%m-%d) para ${RAM_MB} MB de memória, $CPUS núcleo(s) e disco $( ((SSD)) && echo SSD || echo rotativo).
# Rodar o $NOME de novo regrava este arquivo. Para mudar um valor só neste servidor, use ALTER SYSTEM: o
# postgresql.auto.conf vale por cima daqui.

# Os containers chegam pela ponte do Docker; quem entra e como é o pg_hba.conf que decide.
listen_addresses = '*'
password_encryption = scram-sha-256

# Memória: 20% para o cache do Postgres, porque os containers dividem a máquina com ele.
shared_buffers = ${sb}MB
effective_cache_size = ${ec}MB
maintenance_work_mem = ${mwm}MB
work_mem = ${wm}MB

max_worker_processes = $mwp
max_parallel_workers = $CPUS
max_parallel_workers_per_gather = $par
max_parallel_maintenance_workers = $par

min_wal_size = 1GB
max_wal_size = $wal

# Estatística das consultas (pg_stat_statements). Sem os comandos utilitários: um CREATE/ALTER ROLE ... PASSWORD
# ficaria guardado com a senha em claro.
shared_preload_libraries = 'pg_stat_statements'
pg_stat_statements.track_utility = off

log_min_duration_statement = 1s"
	if ((SSD)); then
		AJUSTES+="

# Disco SSD
random_page_cost = 1.1
effective_io_concurrency = 200"
	fi
}

mostrar_plano() {
	titulo "Plano"
	local origem
	case $PG_ORIGEM in
	ubuntu) origem="do Ubuntu" ;;
	pgdg) origem="do repositório oficial do PostgreSQL (PGDG): o Ubuntu $COD não tem a $PG" ;;
	*) origem="do Ubuntu, se ele tiver a $PG; senão do PGDG (decidido depois do apt update)" ;;
	esac
	info "PostgreSQL $PG $origem; pgvector do PGDG, versão ${PGVECTOR:-mais nova}, travada"
	info "Docker Engine, Buildx e Compose do repositório oficial; redes $REDE_BIP e $REDE_POOL"
	info "Ajustes do Postgres em /etc/postgresql/$PG/main/conf.d/90-pginstall.conf:"
	grep -E '^(shared_buffers|effective_cache_size|work_mem|maintenance_work_mem|max_parallel_workers|random_page_cost)' <<<"$AJUSTES" |
		sed "s/^/      ${D}/; s/$/${N}/"
	info "pg_hba.conf: postgres recusado nas redes do Docker; os outros logins, com senha (scram-sha-256)"
	info "Pasta $PASTA (grupo docker${USUARIO:+, dono $USUARIO})$( ((CLOUDFLARED)) && echo ", com $PASTA/cloudflare")"
	if ((ATUALIZAR)); then info "Antes de tudo: apt upgrade do sistema"; fi
}

# ---------------------------------------------------------------------------------------------------------------
# 2. PostgreSQL e pgvector

instalar_base() {
	titulo "2. Pacotes base"
	apt_get update
	if ((ATUALIZAR)); then
		apt_get upgrade
		ok "sistema atualizado"
	fi
	apt_get install ca-certificates curl gnupg jq python3 postgresql-common
	ok "ca-certificates, curl, gnupg, jq, python3, postgresql-common"
	decidir_origem
	[[ -n $PG_ORIGEM ]] || PG_ORIGEM=pgdg
}

instalar_postgres() {
	titulo "3. PostgreSQL $PG e pgvector"

	# Repositório do PGDG: o de um script anterior (apt.postgresql.org.sh, por exemplo) é reaproveitado
	local chave=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg
	if grep -rlsq 'apt.postgresql.org' /etc/apt/sources.list /etc/apt/sources.list.d/ --exclude=pgdg.sources; then
		info "repositório do PGDG já configurado por outro arquivo: reaproveitado"
	else
		if [[ ! -f $chave ]]; then
			install -d -m 0755 /etc/apt/keyrings
			rodar curl -fsSL -o /etc/apt/keyrings/pgdg.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc
			chave=/etc/apt/keyrings/pgdg.asc
		fi
		gravar_se_mudou /etc/apt/sources.list.d/pgdg.sources 644 root:root "# Repositório oficial do PostgreSQL (PGDG). Gerado pelo $NOME.
Types: deb
URIs: https://apt.postgresql.org/pub/repos/apt
Suites: ${COD}-pgdg
Components: main
Signed-By: $chave" || true
	fi
	apt_get update

	# De onde vem cada pacote, e o pgvector na versão travada
	local alvo instalada candidatos
	instalada=$(versao_instalada "postgresql-$PG-pgvector" || true)
	candidatos=$(apt-cache madison "postgresql-$PG-pgvector" 2>/dev/null | awk -F'|' '$3 ~ /apt.postgresql.org/ {gsub(/ /, "", $2); print $2}' | sort -rV || true)
	if [[ -n $PGVECTOR ]]; then
		alvo=$(grep -E "^${PGVECTOR//./\\.}-" <<<"$candidatos" | head -n 1 || true)
		[[ -n $alvo ]] || die "pgvector $PGVECTOR não existe no PGDG para o PostgreSQL $PG no $COD. Disponíveis: $(cut -d- -f1 <<<"$candidatos" | sort -uV | tr '\n' ' ')"
	elif [[ -n $instalada ]]; then
		alvo=$instalada
	else
		alvo=$(head -n 1 <<<"$candidatos")
		[[ -n $alvo ]] || die "o PGDG não tem pgvector para o PostgreSQL $PG no $COD"
	fi

	local pin="# Gerado pelo $NOME. O pgvector fica travado na versão abaixo (com apt-mark hold também), para que um
# apt upgrade não troque a extensão dos bancos sem querer. Para trocar: sudo ./install.sh --pgvector X.Y.Z
Package: postgresql-$PG-pgvector
Pin: version $alvo
Pin-Priority: 1001"
	if [[ $PG_ORIGEM == ubuntu ]]; then
		pin="# Gerado pelo $NOME. O PostgreSQL vem do Ubuntu; do PGDG, na prática, só o pgvector.
Package: *
Pin: release o=apt.postgresql.org
Pin-Priority: 100

$pin"
	fi
	if gravar_se_mudou /etc/apt/preferences.d/pginstall-pgdg 644 root:root "$pin"; then apt_get update; fi

	if instalado "postgresql-$PG"; then
		ok "PostgreSQL $PG: $(versao_instalada "postgresql-$PG")"
	else
		apt_get install "postgresql-$PG" "postgresql-client-$PG"
		ok "PostgreSQL $PG instalado: $(versao_instalada "postgresql-$PG") ($PG_ORIGEM)"
	fi

	if [[ $instalada != "$alvo" ]]; then
		rodar apt-mark unhold "postgresql-$PG-pgvector"
		apt_get install --allow-downgrades --allow-change-held-packages "postgresql-$PG-pgvector=$alvo"
		if [[ -n $instalada ]]; then
			aviso "pgvector trocado de ${instalada%%-*} para ${alvo%%-*}: rode ALTER EXTENSION vector UPDATE em cada banco"
		fi
	fi
	rodar apt-mark hold "postgresql-$PG-pgvector"
	ok "pgvector ${alvo%%-*} ($alvo), travado"

	PGPORT=$(pg_conftool -s "$PG" main show port 2>/dev/null || echo 5432)
	export PGPORT
	systemctl is-active --quiet "postgresql@$PG-main" || rodar systemctl start "postgresql@$PG-main"
}

# ---------------------------------------------------------------------------------------------------------------
# 3. Docker

instalar_docker() {
	titulo "4. Docker"
	if ! grep -rlsq 'download.docker.com' /etc/apt/sources.list /etc/apt/sources.list.d/ --exclude=docker.sources; then
		install -d -m 0755 /etc/apt/keyrings
		[[ -s /etc/apt/keyrings/docker.asc ]] || rodar curl -fsSL -o /etc/apt/keyrings/docker.asc https://download.docker.com/linux/ubuntu/gpg
		chmod a+r /etc/apt/keyrings/docker.asc
		gravar_se_mudou /etc/apt/sources.list.d/docker.sources 644 root:root "# Repositório oficial do Docker (as versões do Ubuntu ficam para trás). Gerado pelo $NOME.
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $COD
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc" || true
		apt_get update
	fi

	if ((!DAEMON_JSON_EXISTE)); then
		install -d -m 0755 /etc/docker
		gravar_se_mudou /etc/docker/daemon.json 644 root:root "{
  \"bip\": \"$DOCKER_BIP\",
  \"default-address-pools\": [ { \"base\": \"$DOCKER_POOL\", \"size\": 24 } ],
  \"log-driver\": \"local\",
  \"log-opts\": { \"max-size\": \"20m\", \"max-file\": \"5\" },
  \"builder\": { \"gc\": { \"enabled\": true, \"defaultMaxUsedSpace\": \"30GB\", \"defaultMinFreeSpace\": \"15GB\", \"defaultReservedSpace\": \"5GB\" } }
}" || true
		ok "/etc/docker/daemon.json: redes $DOCKER_BIP e $DOCKER_POOL, logs com rotação, limpeza do cache de build"
	fi

	if instalado docker-ce; then
		ok "Docker: $(versao_instalada docker-ce)"
	else
		apt_get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
		ok "Docker instalado"
	fi
	rodar systemctl enable --now docker containerd
	if [[ -n $USUARIO ]]; then
		if id -nG "$USUARIO" | tr ' ' '\n' | grep -qx docker; then
			ok "$USUARIO já está no grupo docker"
		else
			rodar usermod -aG docker "$USUARIO"
			ok "$USUARIO no grupo docker (vale no próximo login)"
		fi
	fi
}

# ---------------------------------------------------------------------------------------------------------------
# 4. Ajustes do Postgres e pg_hba.conf

configurar_postgres() {
	titulo "5. Ajustes do PostgreSQL e pg_hba.conf"
	local dir=/etc/postgresql/$PG/main
	if ! grep -Eq "^[[:space:]]*include_dir[[:space:]]*=[[:space:]]*'conf\.d'" "$dir/postgresql.conf"; then
		aviso "$dir/postgresql.conf não lê conf.d: os ajustes não valem até incluir a linha include_dir = 'conf.d'"
	fi
	install -d -m 755 -o postgres -g postgres "$dir/conf.d"
	if gravar_se_mudou "$dir/conf.d/90-pginstall.conf" 644 postgres:postgres "$AJUSTES"; then
		ok "ajustes gravados em $dir/conf.d/90-pginstall.conf"
	else
		ok "ajustes sem mudança"
	fi

	# O bloco do pginstall.srv no fim do pg_hba.conf: regravado a cada execução, o resto do arquivo fica como está
	local hba=$dir/pg_hba.conf tmp
	tmp=$(mktemp)
	awk '/^# >>> pginstall.srv/ {f = 1} !f {print} /^# <<< pginstall.srv/ {f = 0}' "$hba" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' >"$tmp"
	cat >>"$tmp" <<-EOF

		# >>> pginstall.srv: gerado; o $NOME regrava este bloco. Linhas suas, fora dele.
		# Containers do Docker: a ponte padrão e as redes do Compose (/etc/docker/daemon.json). O superusuário postgres
		# nunca entra por elas; os outros logins, com senha. A primeira linha que casar decide: um "reject" de outro
		# superusuário entra acima destas.
		host    all             postgres        $(printf '%-23s' "$REDE_BIP") reject
		host    all             postgres        $(printf '%-23s' "$REDE_POOL") reject
		host    all             all             $(printf '%-23s' "$REDE_BIP") scram-sha-256
		host    all             all             $(printf '%-23s' "$REDE_POOL") scram-sha-256
		# <<< pginstall.srv
	EOF
	if cmp -s "$tmp" "$hba"; then
		ok "pg_hba.conf sem mudança"
	else
		cp -p "$hba" "$hba.antes-pginstall"
		install -m 640 -o postgres -g postgres "$tmp" "$hba"
		ok "pg_hba.conf: bloco das redes do Docker (cópia anterior em pg_hba.conf.antes-pginstall)"
	fi
	rm -f "$tmp"

	rodar systemctl reload "postgresql@$PG-main"
	sleep 1
	local erros_hba erros_conf
	erros_hba=$(pgsql -c "select count(*) from pg_hba_file_rules where error is not null")
	# "setting could not be applied" não é erro: é um parâmetro que só vale reiniciando (tratado logo abaixo)
	erros_conf=$(pgsql -c "select count(*) from pg_file_settings where error is not null and error <> 'setting could not be applied'")
	[[ $erros_hba == 0 ]] || die "o pg_hba.conf tem erro: select * from pg_hba_file_rules where error is not null"
	[[ $erros_conf == 0 ]] || die "a configuração tem erro: select * from pg_file_settings where error is not null and error <> 'setting could not be applied'"

	local por_cima
	por_cima=$(pgsql -c "select string_agg(name, ', ') from pg_file_settings where sourcefile like '%postgresql.auto.conf' and applied")
	if [[ -n $por_cima ]]; then info "valem por cima (ALTER SYSTEM, postgresql.auto.conf): $por_cima"; fi

	local pendentes conexoes
	pendentes=$(pgsql -c "select string_agg(name, ', ') from pg_settings where pending_restart")
	if [[ -n $pendentes ]]; then
		conexoes=$(pgsql -c "select count(*) from pg_stat_activity where backend_type = 'client backend' and pid <> pg_backend_pid()")
		if ((conexoes == 0)) || { ((!SIM)) && [[ -t 0 ]] && perguntar "O Postgres precisa reiniciar ($pendentes) e há $conexoes conexão(ões) abertas. Reiniciar agora?"; }; then
			rodar systemctl restart "postgresql@$PG-main"
			ok "Postgres reiniciado para valer: $pendentes"
		else
			aviso "falta reiniciar o Postgres para valer: $pendentes (systemctl restart postgresql@$PG-main)"
		fi
	fi
}

# ---------------------------------------------------------------------------------------------------------------
# 5. Pasta dos projetos

preparar_pasta() {
	titulo "6. Pasta dos projetos"
	local dono=${USUARIO:-root}
	if [[ ! -d $PASTA ]] || [[ -z $(ls -A "$PASTA") ]]; then
		install -d -m 2775 -o "$dono" -g docker "$PASTA"
		ok "$PASTA ($dono:docker, 2775: o que nascer aqui fica do grupo docker)"
	else
		ok "$PASTA mantida como está ($(stat -c '%U:%G %a' "$PASTA"))"
	fi

	local leia=$PASTA/SERVIDOR.md
	if [[ ! -e $leia ]] || head -n 1 "$leia" | grep -q "gerado pelo $NOME"; then
		gravar_se_mudou "$leia" 664 "$dono:docker" "$(servidor_md)" || true
		ok "$leia: o que está instalado e como criar o banco de um projeto"
	fi

	if ((CLOUDFLARED)); then
		local cf=$PASTA/cloudflare
		install -d -m 2770 -o "$dono" -g docker "$cf"
		[[ -e $cf/compose.yaml ]] || gravar_se_mudou "$cf/compose.yaml" 664 "$dono:docker" "# Cloudflare Tunnel: publica serviços deste servidor na internet com HTTPS, sem abrir porta no firewall.
# O token do túnel (painel Zero Trust → Networks → Tunnels) vai no .env desta pasta. Subir: docker compose up -d
name: cloudflare

services:
  cloudflared:
    image: $CLOUDFLARED_IMAGEM   # versão fixa; para atualizar, troque aqui e rode pull + up -d
    container_name: cloudflared
    restart: unless-stopped
    # Rede do host: o túnel chega a cada serviço pela porta dele em localhost, e as portas dos projetos podem
    # ficar presas em 127.0.0.1, fora da rede local.
    network_mode: host
    command: tunnel --no-autoupdate --metrics 127.0.0.1:20241 run
    environment:
      TUNNEL_TOKEN: \${TUNNEL_TOKEN:?coloque o token do túnel no .env desta pasta}" || true
		[[ -e $cf/.env ]] || gravar_se_mudou "$cf/.env" 600 "$dono:docker" "# Token do Cloudflare Tunnel. Segredo: este arquivo fica com permissão 600 e fora de qualquer git.
TUNNEL_TOKEN=" || true
		ok "$cf: compose.yaml e .env (600) com TUNNEL_TOKEN vazio; o túnel sobe quando o token estiver lá"
	fi
}

servidor_md() {
	cat <<EOF
<!-- gerado pelo $NOME $VERSAO; regravado a cada execução. Para escrever o seu, apague esta linha. -->
# Este servidor

Preparado pelo $NOME em $(date +%Y-%m-%d). Uma pasta por projeto aqui dentro, com o compose e o \`.env\` dele
(permissão 600).

| | |
|---|---|
| PostgreSQL | $(versao_instalada "postgresql-$PG"), no host, porta $PGPORT |
| pgvector | $(versao_instalada "postgresql-$PG-pgvector"), travado (\`/etc/apt/preferences.d/pginstall-pgdg\` e \`apt-mark hold\`) |
| Docker | $(versao_instalada docker-ce); redes $REDE_BIP e $REDE_POOL (\`/etc/docker/daemon.json\`) |
| Ajustes | \`/etc/postgresql/$PG/main/conf.d/90-pginstall.conf\` (o \`ALTER SYSTEM\` vale por cima) |

## Banco de um projeto

Os containers chegam ao Postgres por \`host.docker.internal\` (no compose:
\`extra_hosts: ["host.docker.internal:host-gateway"]\`). Cada projeto tem o seu login, **dono** do banco dele, sem
superusuário. A senha entra pelo \`\\password\`, que manda só o hash (nunca \`PASSWORD '...'\` num comando):

\`\`\`bash
sudo -u postgres psql -c "CREATE ROLE app LOGIN"
sudo -u postgres psql -c "\\password app"
sudo -u postgres psql -c "CREATE DATABASE app OWNER app"
sudo -u postgres psql -d app -c "CREATE EXTENSION vector"   # o pgvector não é "trusted": cria como postgres
\`\`\`

Para restaurar um dump, crie o banco assim antes e restaure com \`pg_restore --no-owner --role=app\` (ou com uma
ferramenta que entregue tudo ao dono do banco de destino).
EOF
}

# ---------------------------------------------------------------------------------------------------------------
# 6. Verificação: banco e login temporários, apagados no fim

TESTE_BANCO='' TESTE_ROLE='' TESTE_REDE=''
limpar_teste() {
	[[ -n $TESTE_REDE ]] && docker network rm "$TESTE_REDE" >/dev/null 2>&1 || true
	[[ -n $TESTE_BANCO ]] && pgsql -q -c "DROP DATABASE IF EXISTS $TESTE_BANCO WITH (FORCE)" >/dev/null 2>&1 || true
	[[ -n $TESTE_ROLE ]] && pgsql -q -c "DROP ROLE IF EXISTS $TESTE_ROLE" >/dev/null 2>&1 || true
	return 0
}

verificar() {
	titulo "7. Verificação"
	local sufixo senha
	sufixo=$(tr -dc 'a-z0-9' </dev/urandom | head -c 8 || true)
	TESTE_BANCO=pginstall_teste_$sufixo
	TESTE_ROLE=pginstall_teste_$sufixo
	trap limpar_teste EXIT

	pgsql -q -c "CREATE DATABASE $TESTE_BANCO"
	local r
	r=$(pgsql -q -d "$TESTE_BANCO" <<-'SQL'
		CREATE EXTENSION vector;
		CREATE TABLE t (id int, v vector(3));
		INSERT INTO t SELECT i, ARRAY[random(), random(), random()]::vector FROM generate_series(1, 200) i;
		CREATE INDEX ON t USING hnsw (v vector_cosine_ops);
		SET hnsw.iterative_scan = relaxed_order;
		SELECT (SELECT extversion FROM pg_extension WHERE extname = 'vector') || ' ' || count(*)
		FROM (SELECT id FROM t ORDER BY v <=> '[1,0,0]' LIMIT 5) x;
	SQL
	)
	ok "pgvector ${r% *}: extensão, índice HNSW e busca iterativa"

	senha=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)
	pgsql -q -c "CREATE ROLE $TESTE_ROLE LOGIN PASSWORD '$(printf '%s' "$senha" | scram)'"

	# Do jeito que um projeto vai usar: de dentro de um container, pela ponte padrão e por uma rede do Compose, com
	# login e senha; e o postgres tem de ser recusado. A senha entra pela entrada padrão do container, nem no comando
	# nem na configuração dele. Precisa do Docker Hub (alpine) e do repositório do Alpine (cliente do Postgres).
	local imagem=alpine:3 tinha_imagem=0 rede saida codigo nome_rede
	if docker image inspect "$imagem" >/dev/null 2>&1; then tinha_imagem=1; fi
	TESTE_REDE=$TESTE_BANCO
	if ! docker network create "$TESTE_REDE" >>"$LOG" 2>&1; then
		aviso "não deu para criar uma rede do Docker para o teste: veja o registro"
		TESTE_REDE=''
	fi
	for rede in bridge $TESTE_REDE; do
		nome_rede="ponte padrão"
		[[ $rede == bridge ]] || nome_rede="rede do Compose"
		codigo=0
		# shellcheck disable=SC2016 # o script entre aspas simples roda no container, com os argumentos dele
		saida=$(printf '%s\n' "$senha" | timeout 300 docker run --rm -i --network "$rede" \
			--add-host host.docker.internal:host-gateway "$imagem" sh -c '
				apk add -q --no-cache postgresql-client >/dev/null 2>&1 || exit 10
				read -r PGPASSWORD && export PGPASSWORD
				c="host=host.docker.internal port=$1 dbname=$2 connect_timeout=5"
				psql -X -At "$c user=$3" -c "select inet_client_addr()" || exit 20
				if psql -X -At "$c user=postgres" -c "select 1" 2>/tmp/e; then exit 30; fi
				grep -q "rejects connection" /tmp/e || { cat /tmp/e >&2; exit 31; }' \
			sh "$PGPORT" "$TESTE_BANCO" "$TESTE_ROLE" 2>>"$LOG") || codigo=$?
		registrar "  container ($rede): saída $codigo, origem $saida"
		case $codigo in
		0) ok "de um container na $nome_rede (${saida:-?}): login com senha entra, postgres é recusado" ;;
		20) erro "de um container na $nome_rede o login com senha não entrou: veja o pg_hba.conf e o registro" ;;
		30) erro "de um container na $nome_rede o postgres entrou: confira o pg_hba.conf" ;;
		31) erro "de um container na $nome_rede o postgres não foi recusado pelo pg_hba.conf: veja o registro" ;;
		*) aviso "não deu para testar de um container na $nome_rede (sem acesso ao Docker Hub ou ao repositório do Alpine?): veja o registro" ;;
		esac
	done
	if ((!tinha_imagem)); then docker image rm "$imagem" >>"$LOG" 2>&1 || true; fi
	limpar_teste
	TESTE_BANCO='' TESTE_ROLE='' TESTE_REDE=''
	ok "banco, login e rede temporários apagados"
}

perguntar() {
	local r
	read -r -p "$1 [s/N] " r
	[[ ${r,,} == s || ${r,,} == sim ]]
}

# ---------------------------------------------------------------------------------------------------------------

main() {
	explicar
	checar_maquina
	calcular_ajustes
	if ((${#ERROS[@]})); then
		printf '\n%s\n' "${R}${B}Não dá para seguir:${N}"
		printf '  %s %s\n' "${R}✗${N}" "${ERROS[@]}"
		exit 1
	fi
	mostrar_plano
	if ((CHECAR)); then
		printf '\n%s\n' "${G}Máquina pronta para a instalação.${N} Nada foi alterado (--checar)."
		exit 0
	fi
	if ((!SIM)); then
		[[ -t 0 ]] || die "sem terminal para confirmar: rode com --sim"
		printf '\n'
		perguntar "Seguir com a instalação?" || die "nada foi alterado"
	fi

	exec 9>/run/lock/pginstall.srv.lock
	flock -n 9 || die "outro $NOME está rodando neste servidor"
	install -d -m 700 /var/log/pginstall.srv
	LOG=/var/log/pginstall.srv/$(date +%Y%m%d-%H%M%S).log
	: >"$LOG" && chmod 600 "$LOG"
	printf '%s %s: %s\n%s' "$NOME" "$VERSAO" "${ARGS[*]:-sem opções}" "$ANTES_DO_LOG" >>"$LOG"

	instalar_base
	instalar_postgres
	instalar_docker
	configurar_postgres
	preparar_pasta
	verificar

	titulo "Pronto"
	info "PostgreSQL $(versao_instalada "postgresql-$PG") · pgvector $(versao_instalada "postgresql-$PG-pgvector" | sed 's/-.*//') · $(docker --version | sed 's/,.*//') · $(docker compose version --short 2>/dev/null | sed 's/^/Compose /')"
	if ((${#AVISOS[@]})); then
		printf '\n%s\n' "${Y}Avisos:${N}"
		printf '  %s %s\n' "${Y}!${N}" "${AVISOS[@]}"
	fi
	if ((${#ERROS[@]})); then
		printf '\n%s\n' "${R}${B}A verificação achou problema:${N}"
		printf '  %s %s\n' "${R}✗${N}" "${ERROS[@]}"
		printf '%s\n' "${D}Registro completo: $LOG${N}"
		exit 1
	fi
	printf '\n%s\n' "Próximos passos: $PASTA/SERVIDOR.md (banco de um projeto).${USUARIO:+ O grupo docker vale para $USUARIO no próximo login.}"
	printf '%s\n' "${D}Registro completo: $LOG${N}"
}

# Numa linha só: o bash não volta a ler o arquivo depois do main, mesmo que ele mude durante a execução.
main; exit
