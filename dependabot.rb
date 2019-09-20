#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "updater"
require_relative "client"
require_relative "utils"

require "dependabot/file_fetchers"
require "logger"

logger = Logger.new("dependabot.log", 10, 1024000)
logger.level = Logger::INFO

credentials = [
  {
    "type" => "git_source",
    "host" => "github.com",
    "username" => "x-access-token",
    "password" => ENV["GITHUB_ACCESS_TOKEN"] # A GitHub access token with read access to public repos
  }
]

credentials << {
  "type" => "git_source",
  "region" => ENV["AWS_DEFAULT_REGION"],
  "username" => ENV["AWS_ACCESS_KEY_ID"],
  "password" => ENV["AWS_SECRET_ACCESS_KEY"]
}

cc_client = Custom::Client::CodeCommit.for_source(
  credentials: credentials
)

cc_client.fetch_all_repos.each do |repo|
  begin
    target_repo = repo.repository_name
    branch = cc_client.fetch_default_branch(target_repo)
    next if branch.to_s.strip.empty?

    commit = cc_client.fetch_commit(target_repo, branch)
    config_files = cc_client.fetch_repo_contents(
      target_repo,
      commit,
      ".dependabot"
    ).files
  rescue Aws::CodeCommit::Errors::FolderDoesNotExistException
    next
  end
  begin
    config_files.each do |file|
      next unless file.absolute_path.include? ".yml"

      config_contents = cc_client.fetch_file_contents(
        target_repo,
        commit,
        file.absolute_path
      )
      process_config(config_contents).each do |config|
        update(credentials, target_repo, config)
        logger.info "successfully processed dependabot config "\
        "for #{target_repo}"
      rescue Dependabot::DependencyFileNotFound
        logger.error " repo: \"#{target_repo}\"'s dependabot config "\
        "referenced a nonexistant file or folder"
        next
      end
    end
  rescue Aws::CodeCommit::Errors::FileDoesNotExistException
    next
  rescue Aws::CodeCommit::Errors::FolderDoesNotExistException
    next
  end
end
