# frozen_string_literal: true

require "bundler"
ENV["BUNDLE_GEMFILE"] = File.join(__dir__, "../../omnibus/Gemfile")
Bundler.setup

require "aws-sdk-codecommit"

module Custom
  module Client
    class CodeCommit
      class NotFound < StandardError; end

      #######################
      # Constructor methods #
      #######################

      def self.for_source(credentials:)
        credential =
          credentials.
          select { |cred| cred["type"] == "git_source" }.
          find { |cred| cred["region"]}

        new(credential)
      end

      ##########
      # Client #
      ##########

      def initialize(credentials)
        @cc_client = Aws::CodeCommit::Client.new(
          access_key_id: credentials&.fetch("username"),
          secret_access_key: credentials&.fetch("password"),
          region: credentials&.fetch("region")
        )
      end

      def fetch_all_repos
        cc_client.list_repositories(
          sort_by: "repositoryName",
          order: "ascending"
        ).repositories
      end

      def fetch_default_branch(repo)
        cc_client.get_repository(
          repository_name: repo
        ).repository_metadata.default_branch
      end

      def fetch_commit(repo, branch)
        cc_client.get_branch(
          branch_name: branch,
          repository_name: repo
        ).branch.commit_id
      end

      def fetch_repo_contents(repo, commit = nil, path = nil)
        actual_path = path
        actual_path = '/' if path.to_s.empty?

        cc_client.get_folder(
          repository_name: repo,
          commit_specifier: commit,
          folder_path: actual_path
        )
      end

      def fetch_file_contents(repo, commit, path)
        cc_client.get_file(
          repository_name: repo,
          commit_specifier: commit,
          file_path: path
        ).file_content
      end

      private

      attr_reader :cc_client
    end
  end
end
