#!/usr/bin/env bash
# Testa o install.sh num Ubuntu descartável (teste/comum.sh): um container privilegiado com systemd, que faz papel
# de servidor novo. Nada do host é alterado além dos containers, das redes e dos volumes do teste, apagados no fim.
#
#   teste/rodar.sh                  Ubuntu 26.04
#   teste/rodar.sh 24.04            outra versão (no 24.04 o PostgreSQL 18 vem do PGDG)
#   teste/rodar.sh 26.04 --manter   deixa o container de pé para olhar (docker exec -it pgr-teste-26.04 bash)
#
# Roteiro: (1) o que a conferência precisa recusar; (2) --checar, como root e como quem veio do sudo; (3)
# instalação sem opção nenhuma, pelo usuário "teste" via sudo: superusuário, .pgpass e pgtower; (4) o administrador
# libera uma aplicação no pg_hba.conf e roda de novo: nada muda, nem a senha, e a linha dele fica; (5) o mesmo
# servidor ganha --com-docker; (6) de novo, sem mudar nada.
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
APLICACAO="hostssl all             all             10.0.10.0/24            scram-sha-256"
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
	docker exec -e SUDO_USER=teste "$NOME" /pgrunway/install.sh --sim --disco ssd "$@" | tee "$arq"
	if grep -q 'erro inesperado' "$arq"; then falhou "erro inesperado na instalação ($*)"; fi
}

# sem_mudanca ARQUIVO: rodar de novo não pode mexer nos ajustes, no pg_hba.conf nem no sistema
sem_mudanca() {
	if ! grep -q 'ajustes sem mudança' "$SAIDA/$1" || ! grep -q 'pg_hba.conf sem mudança' "$SAIDA/$1"; then
		falhou "a execução de novo mudou os ajustes ou o pg_hba.conf"
	fi
	if grep -q 'sistema atualizado' "$SAIDA/$1"; then falhou "rodando de novo, não deveria atualizar o sistema"; fi
	echo "ok: sem mudança e sem atualizar o sistema"
}

# aplicacao_depois_do_bloco: a linha do administrador continua uma só, depois do bloco do pgrunway
aplicacao_depois_do_bloco() {
	local fim linha
	fim=$(docker exec "$NOME" grep -n '^# <<< pgrunway' "$HBA" | cut -d: -f1)
	linha=$(docker exec "$NOME" grep -n -F -x "$APLICACAO" "$HBA" | cut -d: -f1)
	if [[ -z $linha || $(wc -l <<<"$linha") != 1 || $linha -le $fim ]]; then
		docker exec "$NOME" tail -n 20 "$HBA"
		falhou "a linha da aplicação devia continuar uma só, depois do bloco do pgrunway"
	fi
	if [[ $(docker exec "$NOME" grep -c '^# >>> pgrunway' "$HBA") != 1 ]]; then falhou "o bloco do pgrunway foi duplicado"; fi
	echo "ok: a linha da aplicação continua depois do bloco, que é um só"
}

passo "servidor de teste: Ubuntu $UBUNTU com systemd, sem as listas do apt, como um recém-instalado"
construir_imagem "$UBUNTU"
limpar_docker # sobras de um teste anterior
docker network create --subnet "$SUBREDE" "$REDE" >/dev/null

passo "1. o que a conferência precisa recusar (container na rede padrão do Docker, 172.17.0.0/16)"
subir "$NOME-conflito" bridge "$UBUNTU"
recusa redes.txt 'cruza com a do Docker (172.17.0.0/16)' --com-docker --usuario teste
recusa sem-docker.txt 'só com --com-docker' --pasta /srv
recusa sem-usuario.txt 'não existe neste servidor' --usuario ninguem
if ! docker exec "$NOME-conflito" /pgrunway/install.sh --checar --com-docker --usuario teste \
	--docker-bip 10.200.0.1/16 --docker-pool 10.201.0.0/16 >"$SAIDA/outras-redes.txt" 2>&1; then
	cat "$SAIDA/outras-redes.txt"
	falhou "com --docker-bip e --docker-pool o --checar deveria aceitar"
fi
echo "ok: com --docker-bip e --docker-pool fora da rede da máquina, aceitou"
derrubar "$NOME-conflito"

passo "2. --checar"
subir "$NOME" "$REDE" "$UBUNTU"
docker exec "$NOME" /pgrunway/install.sh --checar >"$SAIDA/checar-root.txt"
if ! grep -q 'o superusuário se chama dba' "$SAIDA/checar-root.txt"; then falhou "rodando como root, o superusuário devia ser dba"; fi
docker exec -e SUDO_USER=teste "$NOME" /pgrunway/install.sh --checar | tee "$SAIDA/checar.txt"
if ! grep -q 'Primeira instalação: antes de tudo, atualiza o sistema' "$SAIDA/checar.txt"; then
	falhou "o plano da primeira instalação devia atualizar o sistema"
fi
if ! grep -q 'quem administra: teste' "$SAIDA/checar.txt"; then falhou "quem veio do sudo devia administrar"; fi

passo "3. instalação sem opção nenhuma"
instalar so-banco.txt
if ! grep -q 'sistema atualizado' "$SAIDA/so-banco.txt"; then falhou "a primeira instalação devia atualizar o sistema"; fi
if docker exec "$NOME" sh -c 'command -v docker' >/dev/null; then falhou "sem --com-docker, o Docker não deveria estar instalado"; fi
if ! docker exec "$NOME" grep -q '^host    all             postgres        0.0.0.0/0               reject' "$HBA"; then
	falhou "falta a linha que recusa o postgres de outra máquina"
fi
if [[ $(docker exec "$NOME" runuser -u postgres -- psql -XAtc "show listen_addresses") != '*' ]]; then
	falhou "listen_addresses deveria ser *"
fi
echo "ok: sistema atualizado, sem Docker, postgres recusado de fora, Postgres escutando na rede"
for msg in 'superusuário teste criado' 'superusuário teste entra com a senha' 'pelo socket, sem senha' \
	'pgtower: este servidor cadastrado'; do
	if ! grep -q "$msg" "$SAIDA/so-banco.txt"; then falhou "faltou: $msg"; fi
done
if [[ $(docker exec "$NOME" stat -c '%U %a' /home/teste/.pgpass) != 'teste 600' ]]; then
	falhou "o .pgpass devia ser do teste, com permissão 600"
fi
if ! docker exec "$NOME" grep -q 'host_ram_mb' /home/teste/.config/pgtower/config.yml; then
	falhou "o config do pgtower devia ter a memória da máquina"
fi
PGPASS_ANTES=$(docker exec "$NOME" sha256sum /home/teste/.pgpass)
echo "ok: superusuário teste com a senha no .pgpass, pgtower instalado e apontado para cá"

passo "4. o administrador libera uma aplicação depois do bloco e roda de novo"
docker exec "$NOME" sh -c "printf '%s\n' '$APLICACAO' >>$HBA"
instalar so-banco-2.txt
sem_mudanca so-banco-2.txt
aplicacao_depois_do_bloco
if [[ $(docker exec "$NOME" sha256sum /home/teste/.pgpass) != "$PGPASS_ANTES" ]]; then falhou "rodar de novo trocou a senha"; fi
if ! grep -q 'superusuário teste já existe: fica como está' "$SAIDA/so-banco-2.txt"; then falhou "o superusuário devia ficar"; fi
echo "ok: o superusuário e a senha ficaram"

passo "5. o mesmo servidor ganha --com-docker"
instalar com-docker.txt --com-docker
if ! grep -q 'de um container na rede do Compose' "$SAIDA/com-docker.txt"; then
	falhou "faltou a verificação de dentro dos containers"
fi
aplicacao_depois_do_bloco

passo "6. de novo: nada pode mudar"
instalar com-docker-2.txt --com-docker
sem_mudanca com-docker-2.txt
aplicacao_depois_do_bloco

passo "Tudo certo no Ubuntu $UBUNTU"
