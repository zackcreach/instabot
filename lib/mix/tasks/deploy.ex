defmodule Mix.Tasks.Deploy do
  @moduledoc """
  Automated Docker-based deployment task for Instabot.
  """

  use Mix.Task

  @repo_dir "/home/zack/dev/instabot"

  def run(args) do
    force? = "--force" in args

    log("Starting deployment check")

    File.cd!(@repo_dir)
    configure_git_credentials()

    log("Fetching from origin")
    git!(["fetch", "origin"])

    local_commit = "main" |> rev_parse() |> String.trim()
    remote_commit = "origin/main" |> rev_parse() |> String.trim()

    deploy_or_exit(force?, local_commit, remote_commit)

    log("Building Docker image")
    shell!("./scripts/docker-build.sh")

    log("Deploying with Docker Compose")
    shell!("./scripts/docker-deploy.sh")

    log("Deployment complete")
    log("Deployed commit: #{short_commit(remote_commit)}")
  end

  defp deploy_or_exit(false, commit, commit) do
    log("Already up-to-date: #{short_commit(commit)}")
    log("Use --force to deploy anyway")
    System.halt(0)
  end

  defp deploy_or_exit(true, commit, commit) do
    log("Force deploying current commit: #{short_commit(commit)}")
  end

  defp deploy_or_exit(_force?, local_commit, remote_commit) do
    log("New commits detected: #{short_commit(local_commit)} -> #{short_commit(remote_commit)}")
    log("Pulling latest changes")
    git!(["pull", "origin", "main"])
  end

  defp configure_git_credentials do
    case System.get_env("GITHUB_TOKEN") do
      nil ->
        log("Warning: GITHUB_TOKEN not set, git operations may fail")

      token ->
        helper_path = Path.join(System.tmp_dir!(), "instabot-git-credential-helper")

        File.write!(helper_path, """
        #!/bin/sh
        echo "username=git"
        echo "password=#{token}"
        """)

        File.chmod!(helper_path, 0o755)
        System.cmd("git", ["config", "credential.helper", ""], stderr_to_stdout: true)
        System.cmd("git", ["config", "--local", "credential.helper", "!#{helper_path}"], stderr_to_stdout: true)
    end
  end

  defp rev_parse(ref) do
    git!(["rev-parse", ref])
  end

  defp git!(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {output, 0} -> output
      {output, _status} -> error("Git command failed: #{output}")
    end
  end

  defp shell!(command) do
    case System.cmd("sh", ["-c", command], stderr_to_stdout: true, into: IO.stream()) do
      {_, 0} -> :ok
      {_, _status} -> error("Command failed: #{command}")
    end
  end

  defp log(message) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S")
    IO.puts("[#{timestamp}] #{message}")
  end

  defp error(message) do
    log("ERROR: #{message}")
    System.halt(1)
  end

  defp short_commit(commit) do
    String.slice(commit, 0..6)
  end
end
