_hintvim() {
  local cur=${COMP_WORDS[COMP_CWORD]}
  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=($(compgen -W "setup doctor mods toggle start stop uninstall version help" -- "$cur"))
  elif [ "$COMP_CWORD" -eq 2 ] && [ "${COMP_WORDS[1]}" = setup ]; then
    COMPREPLY=($(compgen -W "--app-only" -- "$cur"))
  fi
}
complete -F _hintvim hintvim
