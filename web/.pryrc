# frozen_string_literal: true

Pry.config.editor = "vim --noplugin"

if defined?(PryByebug)
  Pry.commands.alias_command 'c', 'continue'
  Pry.commands.alias_command 's', 'step'
  Pry.commands.alias_command 'n', 'next'
  Pry.commands.alias_command 'f', 'finish'
  Pry.commands.alias_command 'b', 'break'
  Pry.commands.alias_command 'bda', 'break --disable-all'
end

if defined? PryRescue
  Pry.commands.alias_command 'ta', 'try-again'
  Pry.commands.alias_command 'rc', 'reload-code'
end

Pry.commands.alias_command 'l', 'whereami'
Pry.commands.alias_command 'e', 'exit'
Pry.commands.alias_command 'ed', 'edit'
Pry.commands.alias_command 'r', 'reload-code'

# Hit Enter to repeat last command
Pry::Commands.command /^$/, "repeat last command" do
  pry_instance.run_command Pry.history.to_a.last
end

Pry.config.color = true
Pry.config.theme = "solarized"
Pry.config.ls.separator = "\n" # new lines between methods
Pry.config.ls.heading_color = :magenta
Pry.config.ls.public_method_color = :green
Pry.config.ls.protected_method_color = :yellow
Pry.config.ls.private_method_color = :bright_black
