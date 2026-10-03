#!/usr/bin/env bash
# Grava a saída real do install.sh, com o tempo de cada linha, para as imagens do README (docs/demo/gravar.sh as
# reproduz no VHS). Roda num Ubuntu 26.04 descartável (teste/comum.sh), como o usuário "deploy" via sudo:
#   docs/demo/captura/instalacao.*   instalação completa, respondendo "s" à pergunta
#   docs/demo/captura/recusa.*       máquina cuja rede cruza com a do Docker: o instalador para e explica
# Precisa de Docker e de internet; apaga os containers no fim.

set -Eeuo pipefail

# shellcheck source=teste/comum.sh
. "$(dirname "$0")/../../teste/comum.sh"
SAIDA=$RAIZ/docs/demo/captura
NOME=pgi-demo
REDE=pgi-demo

limpar() {
	derrubar "$NOME" "$NOME-recusa"
	docker network rm "$REDE" >/dev/null 2>&1 || true
}
trap limpar EXIT

# gravar NOME_DO_ARQUIVO CONTAINER [RESPOSTA]: roda o instalador num terminal de verdade e grava saída e tempos. A
# resposta só é digitada quando a pergunta aparece, como faria uma pessoa.
gravar() {
	local arq=$SAIDA/$1 container=$2 resposta=${3:-}
	rm -f "$arq.log" "$arq.tempo"
	{
		if [[ -n $resposta ]]; then
			until grep -qs 'Seguir com a instalação' "$arq.log"; do sleep 0.3; done
			sleep 1.5
			printf '%s\n' "$resposta"
		fi
	} | script -q -f -E never --log-out "$arq.log" --log-timing "$arq.tempo" \
		-c "docker exec -it -e SUDO_USER=deploy -w /pginstall $container ./install.sh" >/dev/null || true
	sem_nulos "$arq"
	echo "gravado: docs/demo/captura/$1 ($(wc -l <"$arq.log") linhas)"
}

# sem_nulos ARQUIVO: o docker exec manda às vezes um byte nulo no começo, que chega cru ou já ecoado pelo terminal
# como "^@". Sai da saída, e a contagem de bytes de cada trecho no arquivo de tempos é refeita.
sem_nulos() {
	python3 - "$1" <<-'PY'
		import sys
		base = sys.argv[1]
		dados = open(base + ".log", "rb").read()
		cabecalho, resto = dados.split(b"\n", 1)
		saida, tempos, pos = [], [], 0
		for linha in open(base + ".tempo"):
		    espera, n = linha.split()
		    trecho = resto[pos:pos + int(n)].replace(b"\0", b"").replace(b"^@", b"")
		    pos += int(n)
		    if trecho:
		        saida.append(trecho)
		        tempos.append(f"{espera} {len(trecho)}\n")
		saida.append(resto[pos:])
		open(base + ".log", "wb").write(cabecalho + b"\n" + b"".join(saida))
		open(base + ".tempo", "w").writelines(tempos)
	PY
}

mkdir -p "$SAIDA"
construir_imagem 26.04
limpar
docker network create --subnet 10.251.99.0/24 "$REDE" >/dev/null

subir "$NOME-recusa" bridge 26.04 # a rede padrão do Docker de fora cruza com a do Docker que seria instalado
docker exec "$NOME-recusa" useradd -m deploy
gravar recusa "$NOME-recusa"

subir "$NOME" "$REDE" 26.04
docker exec "$NOME" useradd -m deploy
gravar instalacao "$NOME" s
