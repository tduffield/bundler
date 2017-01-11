# frozen_string_literal: true
namespace :release do
  def confirm(prompt = "")
    loop do
      print(prompt)
      print(": ") unless prompt.empty?
      break if $stdin.gets.strip == "y"
    end
  rescue Interrupt
    abort
  end

  desc "Make a patch release with the specified PRs from master"
  task :patch, :version do |_t, args|
    version = args.version
    prs = args.extras

    version ||= begin
      version = BUNDLER_SPEC.version
      segments = version.segments
      if segments.last.is_a?(String)
        segments << "1"
      else
        segments[-1] += 1
      end
      segments.join(".")
    end

    confirm "You are about to release #{version}, currently #{BUNDLER_SPEC.version}"

    version_file = "lib/bundler/version.rb"
    version_contents = File.read(version_file)
    unless version_contents.sub!(/^(\s*VERSION = )"#{Gem::Version::VERSION_PATTERN}"/, "\\1#{version.to_s.dump}")
      abort "failed to update #{version_file}, is it in the expected format?"
    end
    File.open(version_file, "w") {|f| f.write(version_contents) }

    BUNDLER_SPEC.version = version

    branch = version.split(".", 3)[0, 2].push("stable").join("-")
    sh("git", "checkout", branch)

    commits = `git log --oneline origin/master --`.split("\n").map {|l| l.split(/\s/, 2) }.reverse
    commits.select! {|_sha, message| message =~ /(Auto merge of|Merge pull request) ##{Regexp.union(*prs)}/ }

    unless system("git", "cherry-pick", "-x", "-m", "1", *commits.map(&:first))
      abort unless system("zsh")
    end

    prs.each do |pr|
      system("open", "https://github.com/bundler/bundler/pull/#{pr}")
      confirm "Add to the changelog"
    end

    confirm "Update changelog"
    sh("git", "commit", "-am", "Version #{version} with changelog")
    sh("rake", "release")
    sh("git", "checkout", "master")
    sh("git", "pull")
    sh("git", "merge", "v#{version}", "--no-edit")
    sh("git", "push")
  end

  desc "Open all PRs that have not been included in a stable release"
  task :open_unreleased_prs do
    def prs(on = "master")
      commits = `git log --oneline origin/#{on} --`.split("\n")
      commits.reverse_each.map {|c| c =~ /(Auto merge of|Merge pull request) #(\d+)/ && $2 }.compact
    end

    last_stable = `git ls-remote origin`.split("\n").map {|r| r =~ %r{refs/tags/v([\d.]+)$} && $1 }.compact.map {|v| Gem::Version.create(v) }.max
    last_stable = last_stable.segments[0, 2].<<("stable").join("-")

    in_release = prs("HEAD") - prs(last_stable)

    in_release.each do |pr|
      system("open", "https://github.com/bundler/bundler/pull/#{pr}")
      confirm
    end
  end
end
