##############################################################
#
# orig .zshrc
#
#################################################################

#################################################################
# general options                                             {{{
#################################################################

# load some custom completions
fpath=(~/.zsh/completion ~/.zsh/completion/conda-zsh-completion $fpath)
# this is as directed in 20.2.1 of zsh manual
autoload -Uz compinit
compinit -i

# turn off all terminal beeps
unsetopt BEEP

export HISTSIZE=10000
export SAVEHIST=$HISTSIZE
export HISTFILE="$HOME/.zsh.history"
setopt EXTENDED_HISTORY          # Write the history file in the ":start:elapsed;command" format.
setopt SHARE_HISTORY             # Share history between all sessions.
setopt HIST_EXPIRE_DUPS_FIRST    # Expire duplicate entries first when trimming history.
setopt HIST_IGNORE_DUPS          # Don't record an entry that was just recorded again.
#setopt BANG_HIST                 # Treat the '!' character specially during expansion.
#setopt INC_APPEND_HISTORY        # Write to the history file immediately, not when the shell exits.
#setopt HIST_IGNORE_ALL_DUPS      # Delete old recorded entry if new entry is a duplicate.
#setopt HIST_FIND_NO_DUPS         # Do not display a line previously found.
#setopt HIST_IGNORE_SPACE         # Don't record an entry starting with a space.
#setopt HIST_SAVE_NO_DUPS         # Don't write duplicate entries in the history file.
#setopt HIST_REDUCE_BLANKS        # Remove superfluous blanks before recording entry.
#setopt HIST_VERIFY               # Don't execute immediately upon history expansion.
#setopt HIST_BEEP                 # Beep when accessing nonexistent history.

export SHELL=$(which zsh)
export EDITOR=nvim
export VISUAL=nvim
export LESS='-ifqm'         # set up the parameters for 'less'
export PAGER='less'     # use less for stuff (such as man)
#export PAGER='less -RM'

umask 077
limit coredumpsize 0        # Turn off core dumps

# report time for long-running commands (based on system+user time)
# can also notify with some hackery: https://superuser.com/a/578651
export REPORTTIME=5

#################################################################
# }}}
#################################################################




#################################################################
# specific environments                                       {{{
#################################################################

# disable gnome/kde-ssh keyring nonsense on remote servers
[ -n "$SSH_CONNECTION" ] && unset SSH_ASKPASS

#################################################################
# }}}
#################################################################




#################################################################
# keybindings, aliases, functions, abbreviations              {{{
#################################################################

# display existing key bindings with `bindkey`

# reset to emacs style
bindkey -e

# this is to get bash-style word treatment: most importantly, kill-word only
# goes to the directory delimeter, instead of killing the entire path
autoload -U select-word-style
select-word-style bash

bindkey '^D' kill-word
bindkey '^B' backward-word
bindkey '^F' forward-word

# for quick alternate command
# - can also use ^U (cut) ^Y (paste) as well
bindkey '^K' push-line
bindkey '^R' history-incremental-search-backward
bindkey '^Y' yank
bindkey '^U' kill-whole-line

# setting defaults
alias ls="ls --color=auto -F"
alias grep="grep --color=auto"
alias less="less -RM"
alias tmux="tmux -2"
[ $(command -v nvim) ] && alias vim="nvim"
alias vimall="nvim **/*(.)"

# shortcuts
alias dgit='git --git-dir=$HOME/.gentoo-configs/ --work-tree=/ -C /' # dotfile management
# for config file management
function git() {
  if [[ $(pwd) == ${HOME} || $(pwd) == /etc || $(pwd) == /etc/portage ]] ; then
    command git --git-dir=$HOME/.gentoo-configs/ --work-tree=/ -C / "$@"
  else
    command git "$@"
  fi
}

cpg() {
  # last argument is the destination
  dst="${@: -1}"
  cp "$@"
  chown -R graham:graham "$dst"
}

function brightness_set () {
  local max val backpath

  if [ -d /sys/class/backlight/intel_backlight ]; then # flattop, nvgen
    backpath=/sys/class/backlight/intel_backlight
  elif [ -d /sys/class/backlight/acpi_video0 ]; then # startop
    backpath=/sys/class/backlight/acpi_video0
  else
    echo "cannot find backlight" >&2
    return 1
  fi

  max=$(< ${backpath}/max_brightness) || {
    echo "Cannot read max_brightness" >&2
    return 1
  }

  case "$1" in
    1) val=$(( max * 1  / 100 )) ;;   # 1%
    2) val=$(( max * 5  / 100 )) ;;   # 5%
    3) val=$(( max * 10 / 100 )) ;;   # 10%
    4) val=$(( max * 25 / 100 )) ;;   # 25%
    5) val=$(( max * 40 / 100 )) ;;   # 40%
    6) val=$(( max * 60 / 100 )) ;;   # 60%
    7) val=$(( max * 80 / 100 )) ;;   # 80%
    8) val=$(( max * 100 / 100 )) ;;  # 100%
    *) echo "provide setting level 1-8" ; return 1 ;;
  esac

  echo "$val" > ${backpath}/brightness
}

# bit-perfect compare two directories
function bit_diff_dirs {
    src=$1
    dst=$2
    (cd ${src}  && find . -type f -print0 | xargs -0 sha256sum | sort -k2 > /tmp/src.sha256)
    (cd ${dst}  && find . -type f -print0 | xargs -0 sha256sum | sort -k2 > /tmp/dst.sha256)
    diff --color /tmp/src.sha256 /tmp/dst.sha256
}

setopt extendedglob
typeset -Ag abbreviations
abbreviations=(
  "lxe"   "lxc exec __CURSOR__ -- sudo --login --user ubuntu"
  "lxg"   "lxc exec __CURSOR__ -- su --login graham"
  "no"    "~/Sync/notes/__CURSOR__"
)

magic-abbrev-expand() {
    local MATCH
    LBUFFER=${LBUFFER%%(#m)[_a-zA-Z0-9]#}
    command=${abbreviations[$MATCH]}
    LBUFFER+=${command:-$MATCH}

    if [[ "${command}" =~ "__CURSOR__" ]]
    then
        RBUFFER=${LBUFFER[(ws:__CURSOR__:)2]}
        LBUFFER=${LBUFFER[(ws:__CURSOR__:)1]}
    else
        zle self-insert
    fi
}

no-magic-abbrev-expand() {
  LBUFFER+=' '
}

zle -N magic-abbrev-expand
zle -N no-magic-abbrev-expand
bindkey " " magic-abbrev-expand
bindkey "^x " no-magic-abbrev-expand
bindkey -M isearch " " self-insert

#################################################################
# }}}
#################################################################




#################################################################
# Appearance and prompt                                       {{{
#################################################################
#
eval `/usr/bin/dircolors ~/.dir_colors`

# colored completion - use my LS_COLORS
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}

# Color shortcuts
  RED='%{[0;31m%}'
  LIGHTRED='%{[1;31m%}'

  GREEN='%{[0;32m%}'
  LIGHTGREEN='%{[1;32m%}'

  YELLOW='%{[0;33m%}'
  LIGHTYELLOW='%{[1;33m%}'

  BLUE='%{[0;34m%}'
  LIGHTBLUE='%{[1;34m%}'

  PURPLE='%{[0;35m%}'
  LIGHTPURPLE='%{[1;35m%}'

  CYAN='%{[0;36m%}'
  LIGHTCYAN='%{[1;36m%}'

  GRAY='%{[1;30m%}'
  LIGHTGRAY='%{[0;37m%}'

  WHITE='%{[0;37m%}'
  LIGHTWHITE='%{[1;37m%}'

  NOCOLOR='%{[0m%}'

  ARED='[0;31m'
  ANOCOLOR='[0;0m'
  AGREEN='[0;32m'
  ABLUE='[0;34m'
  ACYAN='[0;36'
  APURPLE='[0;35m'

# for git repo information
source ~/.zsh/git-prompt.sh
setopt prompt_subst

export GIT_PS1_SHOWDIRTYSTATE=true
export GIT_PS1_SHOWUPSTREAM="auto"
export GIT_PS1_SHOWCOLORHINTS=true

#PROMPT='$GREEN%m$CYAN:$CYAN%3~$YELLOW$(__git_ps1 "(%s)")$CYAN-| $NOCOLOR'
PROMPT='$RED%m$CYAN:$CYAN%3~$YELLOW$(__git_ps1 "(%s)")$CYAN-| $NOCOLOR' # root

RPROMPT='$RED%(?..[%?]) $CYAN|$WHITE%*$NOCOLOR'

export LESS_TERMCAP_mb=$'\e[1;31m'     # begin bold
export LESS_TERMCAP_md=$'\e[1;33m'     # begin blink
export LESS_TERMCAP_so=$'\e[01;44;37m' # begin reverse video
export LESS_TERMCAP_us=$'\e[01;37m'    # begin underline
export LESS_TERMCAP_me=$'\e[0m'        # reset bold/blink
export LESS_TERMCAP_se=$'\e[0m'        # reset reverse video
export LESS_TERMCAP_ue=$'\e[0m'        # reset underline
export GROFF_NO_SGR=1                  # for konsole and gnome-terminal

export MANPAGER='less -s -M +Gg'

#################################################################
# }}}
#################################################################
# useful in root shells
# function boot {
#     efibootmgr -n $1
#     reboot
# }
