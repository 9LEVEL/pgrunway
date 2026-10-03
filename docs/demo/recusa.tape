# Grava docs/img/recusa.png: numa máquina cuja rede cruza com a do Docker, o instalador para e explica. A saída é a
# de uma execução real (docs/demo/capturar.sh). Regravar: docs/demo/gravar.sh

Output "/tmp/recusa.gif"

Set Shell "bash"
Set FontFamily "JetBrains Mono"
Set FontSize 16
Set Width 1040
Set Height 760
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 65ms
Set WaitTimeout 1m

Hide
Type "CAPTURA=recusa; source docs/demo/ambiente.sh && clear"
Enter
Show

Type "sudo ./install.sh"
Enter
Wait+Screen /Não dá para seguir/
Sleep 1.5s
Screenshot docs/img/recusa.png
