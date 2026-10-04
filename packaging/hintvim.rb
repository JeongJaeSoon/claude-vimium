# The tap's copy is the real one: the release workflow fills in url and sha256 for each
# tag, which this file cannot hold, since it is part of the tarball it would hash.
class Hintvim < Formula
  desc "Vimium-style keyboard hints for Claude Desktop"
  homepage "https://github.com/JeongJaeSoon/hintvim"
  url "https://github.com/JeongJaeSoon/hintvim/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"
  head "https://github.com/JeongJaeSoon/hintvim.git", branch: "main"

  depends_on "jq"
  depends_on macos: :ventura

  def install
    system "make", "app", "VERSION=#{version}", "ARCHS=#{Hardware::CPU.arch}"
    prefix.install "build/Hintvim.app"
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

      The app is built and signed on this Mac, so macOS asks for that permission
      again after each upgrade. Run `hintvim uninstall` before
      `brew uninstall hintvim` to undo what setup changed.
    EOS
  end

  test do
    assert_match "hintvim #{version}", shell_output("#{bin}/hintvim version")
    app = prefix/"Hintvim.app/Contents/MacOS/Hintvim"
    assert_match "hintvim #{version}", shell_output("#{app} --version")
  end
end
