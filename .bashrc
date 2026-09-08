[[ $- != *i* ]] && return

export TERM=xterm-256color

if [ "$TERM" = "linux" ]; then
    echo -en "\e]P0282828" #bg0
    echo -en "\e]P8928374" #grey
    echo -en "\e]P1cc241d" #darkred
    echo -en "\e]P9fb4934" #red
    echo -en "\e]P298971a" #darkgreen
    echo -en "\e]PAb8bb26" #green
    echo -en "\e]P3d79921" #darkyellow
    echo -en "\e]PBfabd2f" #yellow
    echo -en "\e]P4458588" #darkblue
    echo -en "\e]PC83a598" #blue
    echo -en "\e]P5b16286" #darkmagenta
    echo -en "\e]PDd3869b" #magenta
    echo -en "\e]P6689d6a" #darkcyan
    echo -en "\e]PE8ec07c" #cyan
    echo -en "\e]P7a89984" #fg4
    echo -en "\e]PFebdbb2" #fg1
    clear #for background artifacting
fi

force_color_prompt=yes
COLOR_DEF='\[\033[0m\]'
COLOR_USER='\[\033[01;32m\]'
COLOR_PATH='\[\033[01;34m\]'
COLOR_GIT='\[\033[01;33m\]'
COLOR_DOLLAR='\[\033[01;31m\]'

parse_git_branch() {
    git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ (\1)/'
}

PS1="$COLOR_USER\u@\h$COLOR_DEF: $COLOR_PATH\w$COLOR_GIT\$(parse_git_branch)$COLOR_DEF $COLOR_DOLLAR\$ $COLOR_DEF"

alias ls="exa --icons --color=always --group-directories-first"
alias v="vim"
alias nv="nvim"
alias dv="doas vim"
alias dnv="doas nvim"
alias ff="fastfetch"
alias ff-small="ff --config /usr/local/share/fastfetch/presets/examples/13.jsonc"
alias nf="neofetch"
alias lg="lazygit"
alias sudo="doas"
alias mkln="make clean"
alias install="doas pkg install"
alias update="doas pkg update -f && doas pkg upgrade"
alias remove="doas pkg remove"
alias mkop="cd ~/open-delta/code/kernel && make"

eval "$(zoxide init bash)"
