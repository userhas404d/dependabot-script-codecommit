# frozen_string_literal: true

$LOAD_PATH << "./bundler/lib"
$LOAD_PATH << "./cargo/lib"
$LOAD_PATH << "./common/lib"
$LOAD_PATH << "./composer/lib"
$LOAD_PATH << "./dep/lib"
$LOAD_PATH << "./docker/lib"
$LOAD_PATH << "./elm/lib"
$LOAD_PATH << "./git_submodules/lib"
$LOAD_PATH << "./github_actions/lib"
$LOAD_PATH << "./go_modules/lib"
$LOAD_PATH << "./gradle/lib"
$LOAD_PATH << "./hex/lib"
$LOAD_PATH << "./maven/lib"
$LOAD_PATH << "./npm_and_yarn/lib"
$LOAD_PATH << "./nuget/lib"
$LOAD_PATH << "./python/lib"
$LOAD_PATH << "./terraform/lib"

require "bundler"
ENV["BUNDLE_GEMFILE"] = File.join(__dir__, "../../omnibus/Gemfile")
Bundler.setup

require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"
require "dependabot/omnibus"

require "aws-sdk-codecommit"

def update(credentials, repo_name, update_config)
  package_manager = update_config.fetch("package_manager")
  directory = update_config.fetch("directory")

  source = Dependabot::Source.new(
    provider: "codecommit",
    hostname: ENV["AWS_REGION"],
    repo: repo_name,
    directory: directory,
    branch: "master"
  )

  ##############################
  # Fetch the dependency files #
  ##############################
  puts "Fetching #{package_manager} dependency files for #{repo_name}"
  fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).new(
    source: source,
    credentials: credentials
  )

  files = fetcher.files
  commit = fetcher.commit

  ##############################
  # Parse the dependency files #
  ##############################
  puts "Parsing dependencies information"
  parser = Dependabot::FileParsers.for_package_manager(package_manager).new(
    dependency_files: files,
    source: source,
    credentials: credentials
  )

  dependencies = parser.parse

  dependencies.select(&:top_level?).each do |dep|
    #########################################
    # Get update details for the dependency #
    #########################################
    checker = Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
      dependency: dep,
      dependency_files: files,
      credentials: credentials
    )

    next if checker.up_to_date?

    requirements_to_unlock =
      if !checker.requirements_unlocked_or_can_be?
        if checker.can_update?(requirements_to_unlock: :none) then :none
        else :update_not_possible
        end
      elsif checker.can_update?(requirements_to_unlock: :own) then :own
      elsif checker.can_update?(requirements_to_unlock: :all) then :all
      else :update_not_possible
      end

    next if requirements_to_unlock == :update_not_possible

    updated_deps = checker.updated_dependencies(
      requirements_to_unlock: requirements_to_unlock
    )

    #####################################
    # Generate updated dependency files #
    #####################################
    print "  - Updating #{dep.name} (from #{dep.version})…"
    updater = Dependabot::FileUpdaters.for_package_manager(package_manager).new(
      dependencies: updated_deps,
      dependency_files: files,
      credentials: credentials
    )

    updated_files = updater.updated_dependency_files

    ########################################
    # Create a pull request for the update #
    ########################################
    pr_creator = Dependabot::PullRequestCreator.new(
      source: source,
      base_commit: commit,
      dependencies: updated_deps,
      files: updated_files,
      credentials: credentials,
      assignees: [(ENV["PULL_REQUESTS_ASSIGNEE"] || ENV["GITLAB_ASSIGNEE_ID"])&.to_i],
      label_language: true
    )
    pull_request = pr_creator.create
    puts " submitted"

    next unless pull_request

    # Enable GitLab "merge when pipeline succeeds" feature.
    # Merge requests created and successfully tested will be merge automatically.
    if ENV["GITLAB_AUTO_MERGE"]
      g = Gitlab.client(
        endpoint: source.api_endpoint,
        private_token: ENV["GITLAB_ACCESS_TOKEN"]
      )
      g.accept_merge_request(
        source.repo,
        pull_request.iid,
        merge_when_pipeline_succeeds: true,
        should_remove_source_branch: true
      )
    end
  end
end
