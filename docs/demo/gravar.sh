#!/usr/bin/env bash
# Regrava as imagens do README (docs/img) a partir das capturas em docs/demo/captura, com o VHS num container.
# Para capturar de novo a saída real (depois de mudar as mensagens do install.sh): docs/demo/capturar.sh
set -Eeuo pipefail
RAIZ=$(cd "$(dirname "$0")/../.." && pwd)
VHS=ghcr.io/charmbracelet/vhs:v0.12.1
for fita in demo recusa; do
	docker run --rm -v "$RAIZ:/vhs" -w /vhs "$VHS" "docs/demo/$fita.tape" >"$RAIZ/docs/demo/.vhs-$fita.log" 2>&1 || { tail -n 20 "$RAIZ/docs/demo/.vhs-$fita.log" >&2; exit 1; }
	echo "gravado: docs/demo/$fita.tape"
done
ls -la "$RAIZ/docs/img"
