# shellcheck shell=bash
# Ambiente das gravações do VHS (docs/demo/*.tape): o prompt de um servidor e um "sudo ./install.sh" que reproduz a
# captura de uma execução real (docs/demo/capturar.sh) no ritmo dela, com as esperas longas do apt encurtadas.
# CAPTURA diz qual: instalacao ou recusa.
PS1='\[\e[1;32m\]deploy@servidor\[\e[0m\]:\[\e[1;34m\]~/pginstall.srv\[\e[0m\]$ '
sudo() { scriptreplay --divisor 1.3 --maxdelay 1.2 -t "docs/demo/captura/$CAPTURA.tempo" -s "docs/demo/captura/$CAPTURA.log"; }
