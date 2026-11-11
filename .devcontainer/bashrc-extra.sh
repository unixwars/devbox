if ! shopt -oq posix && [ -f /usr/share/bash-completion/bash_completion ]; then
  . /usr/share/bash-completion/bash_completion
fi
command_not_found_handle() {
  if [ -x /usr/lib/command-not-found ]; then
    /usr/lib/command-not-found -- "$1"
    return $?
  fi
  echo "$1: command not found" >&2
  return 127
}
