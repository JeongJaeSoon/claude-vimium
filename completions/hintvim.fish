set -l commands setup doctor mods toggle start stop uninstall version help
complete -c hintvim -f
complete -c hintvim -n "not __fish_seen_subcommand_from $commands" -a setup -d 'Start the app, start it at login, add the optional Claude plugin'
complete -c hintvim -n "not __fish_seen_subcommand_from $commands" -a doctor -d 'Check every piece and say how to fix what is missing'
complete -c hintvim -n "not __fish_seen_subcommand_from $commands" -a mods -d 'Match the mods switch to Claude Desktop'
complete -c hintvim -n "not __fish_seen_subcommand_from $commands" -a toggle -d 'Show or hide hints'
complete -c hintvim -n "not __fish_seen_subcommand_from $commands" -a start -d 'Start the app'
complete -c hintvim -n "not __fish_seen_subcommand_from $commands" -a stop -d 'Quit the app'
complete -c hintvim -n "not __fish_seen_subcommand_from $commands" -a uninstall -d 'Undo everything setup did'
complete -c hintvim -n "not __fish_seen_subcommand_from $commands" -a version -d 'Print the version'
complete -c hintvim -n "not __fish_seen_subcommand_from $commands" -a help -d 'Show usage'
complete -c hintvim -n "__fish_seen_subcommand_from setup" -l app-only -d 'App only, without the plugin and the mods switch'
