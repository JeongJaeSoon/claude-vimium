cask "hintvim" do
  version "1.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/JeongJaeSoon/hintvim/releases/download/v#{version}/hintvim-#{version}-macos-universal.dmg"
  name "Hintvim"
  desc "Vimium-style keyboard hints for Claude Desktop"
  homepage "https://github.com/JeongJaeSoon/hintvim"

  depends_on formula: "jq"
  depends_on macos: ">= :ventura"
  conflicts_with formula: "hintvim"

  preflight do
    system_command "/usr/bin/sed",
                   args: ["-i", "", "-e", "s|@VERSION@|#{version}|g",
                          "-e", "s|@APP@|#{appdir}/Hintvim.app|g",
                          "-e", "s|@JQ@|#{HOMEBREW_PREFIX}/opt/jq/bin/jq|g",
                          "-e", "s|@SELF@|#{HOMEBREW_PREFIX}/bin/hintvim|g",
                          "#{staged_path}/bin/hintvim"]
  end

  app "Hintvim.app"
  binary "bin/hintvim"
  bash_completion "completions/hintvim.bash", target: "hintvim"
  zsh_completion "completions/_hintvim"
  fish_completion "completions/hintvim.fish"

  caveats <<~EOS
    Finish the install with:
      hintvim setup
    It installs the Claude plugin, starts the app and starts it at login.
    Then allow Hintvim in System Settings > Privacy & Security > Accessibility.

    Run `hintvim uninstall` before `brew uninstall --cask hintvim` to remove
    the login item, Claude plugin, state, logs and Accessibility entry.
  EOS
end
