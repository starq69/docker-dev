# configurazione standard per docker container gestito con docker-dev
#
HISTFILE=/app/.docker_container/.bash_history
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignorespace

# Prompt con hostname completo
#
PS1='\u@\H:\w\$ '

# Salva ogni comando eseguito
#
PROMPT_COMMAND='history -a; history -n'

# Scrive la history anche quando Bash termina
#
trap 'history -w' EXIT
