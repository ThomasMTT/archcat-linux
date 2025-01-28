# Oh-my-zsh and powerlevel10k stuff

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git sudo zsh-autosuggestions zsh-syntax-highlighting history)
source $ZSH/oh-my-zsh.sh
source ~/.p10k.zsh

# Aliases

alias ls='lsd'
alias cat='bat'
