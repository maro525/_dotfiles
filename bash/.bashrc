# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=50000
HISTFILESIZE=100000
HISTTIMEFORMAT='%F %T '
HISTIGNORE='ls:ll:cd:exit:history'

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
# handy extras: autocd (type a dir name to cd), cdspell/dirspell (typo tolerance)
shopt -s globstar autocd cdspell dirspell

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# NOTE: prompt (PS1) is set by starship at the bottom of this file

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
command -v mise >/dev/null && eval "$(mise activate bash)"
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

command -v zoxide >/dev/null && eval "$(zoxide init bash)"

if command -v eza >/dev/null; then
    alias ls="eza -la --icons"
    alias ll="eza -l --icons"
    alias l="eza --icons"
    alias lt="eza --tree --icons"
fi
command -v batcat >/dev/null && ! command -v bat >/dev/null && alias bat="batcat"

[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# env
# Secrets (LINEAR_API_KEY, GITHUB_PERSONAL_ACCESS_TOKEN, etc.) live in
# ~/.bashrc.local, which is intentionally NOT committed to this repo.
[[ -f ~/.bashrc.local ]] && source ~/.bashrc.local

# Disable bracketed paste mode
bind 'set enable-bracketed-paste off'

# starship
command -v starship >/dev/null && eval "$(starship init bash)"

[ -f "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"

if command -v atuin >/dev/null; then
    [[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh
    eval "$(atuin init bash)"
fi

# --- PATH additions (dedup-guarded) ---
path_prepend() {
    case ":$PATH:" in
        *":$1:"*) ;;
        *) export PATH="$1:$PATH" ;;
    esac
}
path_prepend "$HOME/.local/share/pnpm/bin"   # pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
path_prepend "$HOME/.fly/bin"                # flyctl
export FLYCTL_INSTALL="$HOME/.fly"
path_prepend "$HOME/.opencode/bin"           # opencode
unset -f path_prepend

# ターミナル (zellij / WezTerm 等) のタブ・ウィンドウタイトルをカレントディレクトリ名に強制設定 (OSC 0 エスケープシーケンス)。
# CLAUDE_CODE_DISABLE_TERMINAL_TITLE で Claude Code によるタイトル上書きも抑止。
# 注意: 代入で上書きすると zoxide / atuin が登録した PROMPT_COMMAND フックが消えて
# cd 履歴が記録されなくなるため、必ず既存値への「追記」にすること。
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}printf '\033]0;%s\007' \"\${PWD##*/}\""
export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1
