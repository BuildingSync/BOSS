# frozen_string_literal: true

# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BuildingSync-gem/blob/develop/LICENSE.md
# *******************************************************************************

require 'fileutils'
require 'open3'
require 'yaml'

module BOSS
  # Manages non-gem measure repositories declared in a manifest file.
  class ExternalMeasureRepoManager
    def initialize(manifest_path: EXTERNAL_MEASURE_REPOS_MANIFEST_PATH, install_dir: EXTERNAL_MEASURE_REPOS_INSTALL_DIR)
      @manifest_path = manifest_path
      @install_dir = install_dir
    end

    def manifest_exists?
      File.file?(@manifest_path)
    end

    def configured?
      !repo_entries.empty?
    end

    def local_measure_directories
      return [LOCAL_MEASURES_DIR] if !manifest_exists?

      roots = manifest['local_measure_roots']
      roots = [LOCAL_MEASURES_DIR] if !roots.is_a?(Array) || roots.empty?

      directories = roots.map do |path|
        File.expand_path(path, File.expand_path('..', @manifest_path))
      end

      directories.select { |path| Dir.exist?(path) }.uniq
    end

    def install_all
      return [] if !manifest_exists?

      FileUtils.mkdir_p(@install_dir)

      repo_entries.each do |repo_entry|
        install_repo(repo_entry)
      end

      resolved_measure_directories(include_scenario_only: true)
    end

    # Repos marked scenario_only: true are left off baseline workflows and are only
    # returned when include_scenario_only is true.
    def resolved_measure_directories(include_scenario_only: false)
      return [] if !manifest_exists?

      directories = []
      repo_entries.each do |repo_entry|
        next if repo_entry['scenario_only'] && !include_scenario_only

        repo_root = repo_checkout_dir(repo_entry)
        if local_repo?(repo_entry) && !Dir.exist?(repo_root)
          raise StandardError, "Local measure repository '#{repo_entry['name']}' not found at #{repo_root}. " \
                               "Check out the repository there or update local_path in #{@manifest_path}."
        end

        if !Dir.exist?(repo_root)
          message = "Repository '#{repo_entry['name']}' is not installed at #{repo_root}. Run rake measures:install_external."
          if defined?(OpenStudio) && OpenStudio.respond_to?(:logFree)
            OpenStudio.logFree(OpenStudio::Warn, 'BOSS.ExternalMeasureRepoManager.resolved_measure_directories', message)
          else
            warn("BOSS.ExternalMeasureRepoManager.resolved_measure_directories: #{message}")
          end
          next
        end

        repo_entry['measure_roots'].each do |root_rel_path|
          root_abs_path = File.expand_path(File.join(repo_root, root_rel_path))
          if Dir.exist?(root_abs_path)
            directories << root_abs_path
          else
            message = "Configured measure root '#{root_rel_path}' does not exist for repository '#{repo_entry['name']}' (#{root_abs_path})."
            if defined?(OpenStudio) && OpenStudio.respond_to?(:logFree)
              OpenStudio.logFree(OpenStudio::Warn, 'BOSS.ExternalMeasureRepoManager.resolved_measure_directories', message)
            else
              warn("BOSS.ExternalMeasureRepoManager.resolved_measure_directories: #{message}")
            end
          end
        end
      end

      ordered_unique(directories)
    end

    private

    def manifest
      @manifest ||= begin
        parsed = YAML.safe_load(File.read(@manifest_path), permitted_classes: [], aliases: false)
        parsed.is_a?(Hash) ? parsed : {}
      end
    end

    def repo_entries
      return [] if !manifest_exists?

      repos = manifest.is_a?(Hash) ? manifest['repos'] : nil
      return [] if repos.nil?
      raise StandardError, "Expected 'repos' array in #{@manifest_path}" if !repos.is_a?(Array)

      repos.map do |repo|
        validate_repo_entry(repo)
      end
    end

    def validate_repo_entry(repo)
      if !repo.is_a?(Hash)
        raise StandardError, "Each repo entry in #{@manifest_path} must be a map"
      end

      required = repo.key?('local_path') ? %w[name local_path measure_roots] : %w[name url ref measure_roots]
      missing = required.select { |key| repo[key].nil? || repo[key].to_s.empty? }
      if !missing.empty?
        raise StandardError, "Repo entry is missing required keys #{missing.join(', ')} in #{@manifest_path}"
      end

      # Prevent path traversal / unexpected nesting in checkout dir.
      if !repo['name'].to_s.match?(/\A[\w.-]+\z/)
        raise StandardError, "Repo name '#{repo['name']}' must match /\\A[\\w.-]+\\z/ in #{@manifest_path}"
      end

      if !repo['measure_roots'].is_a?(Array) || repo['measure_roots'].empty?
        raise StandardError, "Repo '#{repo['name']}' must define a non-empty measure_roots array"
      end

      if repo.key?('local_path') && (repo.key?('url') || repo.key?('ref'))
        raise StandardError, "Repo '#{repo['name']}' must use either local_path or url/ref, not both"
      end

      if repo.key?('scenario_only') && ![true, false].include?(repo['scenario_only'])
        raise StandardError, "Repo '#{repo['name']}' scenario_only must be true or false"
      end

      repo
    end

    # Local checkouts are used in place; BOSS never runs Git against them.
    def install_repo(repo_entry)
      if local_repo?(repo_entry)
        repo_dir = repo_checkout_dir(repo_entry)
        if !Dir.exist?(repo_dir)
          raise StandardError, "Local measure repository '#{repo_entry['name']}' not found at #{repo_dir}. " \
                               "Check out the repository there or update local_path in #{@manifest_path}."
        end
        return
      end

      repo_dir = repo_checkout_dir(repo_entry)
      measure_roots = repo_entry['measure_roots']

      if Dir.exist?(File.join(repo_dir, '.git'))
        run_git(%W[-C #{repo_dir} remote set-url origin #{repo_entry['url']}])
      else
        FileUtils.mkdir_p(File.dirname(repo_dir))
        run_git(%W[clone --filter=blob:none --no-checkout #{repo_entry['url']} #{repo_dir}])
      end

      run_git(%W[-C #{repo_dir} sparse-checkout init --cone])
      run_git(['-C', repo_dir, 'sparse-checkout', 'set', *measure_roots])
      run_git(%W[-C #{repo_dir} fetch --depth 1 origin #{repo_entry['ref']}])
      run_git(%W[-C #{repo_dir} checkout --force FETCH_HEAD])
    end

    def local_repo?(repo_entry)
      repo_entry.key?('local_path')
    end

    def repo_checkout_dir(repo_entry)
      return File.expand_path(repo_entry['local_path'], File.dirname(File.expand_path(@manifest_path))) if local_repo?(repo_entry)

      File.join(@install_dir, repo_entry['name'])
    end

    def run_git(args)
      stdout, stderr, status = Open3.capture3('git', *args)
      if !status.success?
        raise StandardError, "git #{args.join(' ')} failed:\n#{stdout}\n#{stderr}"
      end
    end

    def ordered_unique(paths)
      seen = {}
      paths.each_with_object([]) do |path, acc|
        next if seen[path]

        seen[path] = true
        acc << path
      end
    end
  end
end
