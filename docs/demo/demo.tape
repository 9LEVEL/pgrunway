# Grava docs/img/demo.gif, docs/img/inicio.png e docs/img/instalacao.png. A saída é a de uma execução real num
# Ubuntu 26.04 recém-instalado (docs/demo/capturar.sh); o VHS só a reproduz. Regravar: docs/demo/gravar.sh

Output docs/img/demo.gif

Set Shell "bash"
Set FontFamily "JetBrains Mono"
Set FontSize 16
Set Width 1040
Set Height 1060
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 65ms
Set Framerate 12
Set WaitTimeout 3m

Hide
Type "CAPTURA=instalacao; source docs/demo/ambiente.sh && clear"
Enter
Show

Sleep 800ms
Type "sudo ./install.sh"
Sleep 500ms
Enter

Wait+Screen /Seguir com a instalação/
Sleep 200ms
Screenshot docs/img/inicio.png
Sleep 2s

# A reprodução dura uns 15 s. Aqui um tempo fixo: depois que a tela rola, o Wait do VHS lê o topo do histórico.
Sleep 22s
Screenshot docs/img/instalacao.png
Sleep 4s
