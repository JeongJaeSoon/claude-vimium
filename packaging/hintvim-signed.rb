# The release workflow fills in the signed archive's sha256 before publishing to the tap.
class Hintvim < Formula
  SIGNING_TEAM_ID = "@SIGNING_TEAM_ID@".freeze

  desc "Vimium-style keyboard hints for Claude Desktop"
  homepage "https://github.com/JeongJaeSoon/hintvim"
  url "https://github.com/JeongJaeSoon/hintvim/releases/download/v1.1.0/hintvim-1.1.0-macos-universal.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  depends_on "jq"
  depends_on macos: :ventura

  def install
    system "/usr/bin/codesign", "--verify", "--strict", "-R",
           "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"#{SIGNING_TEAM_ID}\" and identifier \"io.github.jeongjaesoon.hintvim\"",
           "Hintvim.app"
    prefix.install "Hintvim.app"
    bin.install "bin/hintvim"
    inreplace bin/"hintvim" do |s|
      s.gsub! "@VERSION@", version.to_s
      s.gsub! "@APP@", "#{opt_prefix}/Hintvim.app"
      s.gsub! "@JQ@", "#{formula_opt_bin("jq")}/jq"
      s.gsub! "@SELF@", "#{opt_bin}/hintvim"
    end
    bash_completion.install "completions/hintvim.bash" => "hintvim"
    zsh_completion.install "completions/_hintvim"
    fish_completion.install "completions/hintvim.fish"
  end

  def caveats
    <<~EOS
      Finish the install with:
        hintvim setup
      It installs the Claude plugin, starts the app and starts it at login.
      Then allow hintvim in System Settings > Privacy & Security > Accessibility.

      This app is signed with Developer ID. Allow Accessibility once on the first
      install or when switching from the source-built version. Later upgrades using
      the same signing identity are intended to retain that permission.
      Run `hintvim uninstall` before
      `brew uninstall hintvim` to undo what setup changed.
    EOS
  end

  test do
    assert_match "hintvim #{version}", shell_output("#{bin}/hintvim version")
    app = prefix/"Hintvim.app/Contents/MacOS/Hintvim"
    system "/usr/bin/codesign", "--verify", "--strict", prefix/"Hintvim.app"
    assert_match "hintvim #{version}", shell_output("#{app} --version")
  end
end
