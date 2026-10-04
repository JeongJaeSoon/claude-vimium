# The tap's copy is the real one: the release workflow fills in url and sha256 for each
# tag, which this file cannot hold, since it is part of the tarball it would hash.
class ClaudeVimium < Formula
  desc "Vimium-style keyboard hints for Claude Desktop"
  homepage "https://github.com/JeongJaeSoon/claude-vimium"
  url "https://github.com/JeongJaeSoon/claude-vimium/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/JeongJaeSoon/claude-vimium.git", branch: "main"

  depends_on "jq"
  depends_on macos: :ventura

  def install
    system "make", "app", "VERSION=#{version}", "ARCHS=#{Hardware::CPU.arch}"
    prefix.install "build/ClaudeVimium.app"
    bin.install "bin/claude-vimium"
    inreplace bin/"claude-vimium" do |s|
      s.gsub! "@VERSION@", version.to_s
      s.gsub! "@APP@", "#{opt_prefix}/ClaudeVimium.app"
      s.gsub! "@JQ@", "#{formula_opt_bin("jq")}/jq"
      s.gsub! "@SELF@", "#{opt_bin}/claude-vimium"
    end
  end

  def caveats
    <<~EOS
      Finish the install with:
        claude-vimium setup
      It installs the Claude plugin, starts the app and starts it at login.
      Then allow claude-vimium in System Settings > Privacy & Security > Accessibility.

      The app is built and signed on this Mac, so macOS asks for that permission
      again after each upgrade. Run `claude-vimium uninstall` before
      `brew uninstall claude-vimium` to undo what setup changed.
    EOS
  end

  test do
    assert_match "claude-vimium #{version}", shell_output("#{bin}/claude-vimium version")
    app = prefix/"ClaudeVimium.app/Contents/MacOS/ClaudeVimium"
    assert_match "claude-vimium #{version}", shell_output("#{app} --version")
  end
end
