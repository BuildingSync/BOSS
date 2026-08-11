# *******************************************************************************
# OpenStudio(R), Copyright (c) Alliance for Energy Innovation, LLC.
# BuildingSync(R), Copyright (c) Alliance for Energy Innovation, LLC.
# See also https://github.com/BuildingSync/BOSS/blob/develop/LICENSE.md
# *******************************************************************************

require 'tmpdir'
require 'fileutils'
require 'BOSS/constants'
require 'BOSS/external_measure_repo_manager'

RSpec.describe BOSS::ExternalMeasureRepoManager do
  # Helpers to write a manifest YAML to a temp dir
  def write_manifest(dir, content)
    path = File.join(dir, 'external_measure_repos.yml')
    File.write(path, content)
    path
  end

  def manager_for(manifest_path, install_dir)
    described_class.new(manifest_path: manifest_path, install_dir: install_dir)
  end

  # ---------------------------------------------------------------------------
  describe '#manifest_exists?' do
    it 'returns true when the manifest file is present' do
      Dir.mktmpdir do |dir|
        path = write_manifest(dir, "repos: []\n")
        mgr = manager_for(path, dir)
        expect(mgr.manifest_exists?).to be true
      end
    end

    it 'returns false when the manifest file is absent' do
      Dir.mktmpdir do |dir|
        mgr = manager_for(File.join(dir, 'missing.yml'), dir)
        expect(mgr.manifest_exists?).to be false
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe '#configured?' do
    it 'returns false when manifest has no repos' do
      Dir.mktmpdir do |dir|
        path = write_manifest(dir, "repos: []\n")
        expect(manager_for(path, dir).configured?).to be false
      end
    end

    it 'returns false when manifest has no repos key' do
      Dir.mktmpdir do |dir|
        path = write_manifest(dir, "local_measure_roots:\n  - ./measures\n")
        expect(manager_for(path, dir).configured?).to be false
      end
    end

    it 'returns true when at least one repo is declared' do
      Dir.mktmpdir do |dir|
        yaml = <<~YAML
          repos:
            - name: my_repo
              url: https://example.com/repo.git
              ref: main
              measure_roots:
                - measures
        YAML
        path = write_manifest(dir, yaml)
        expect(manager_for(path, dir).configured?).to be true
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe '#local_measure_directories' do
    it 'returns the default LOCAL_MEASURES_DIR when no manifest exists' do
      Dir.mktmpdir do |dir|
        mgr = manager_for(File.join(dir, 'missing.yml'), dir)
        expect(mgr.local_measure_directories).to eq [LOCAL_MEASURES_DIR]
      end
    end

    it 'expands paths relative to the manifest directory' do
      Dir.mktmpdir do |dir|
        # Create a real sub-directory so Dir.exist? passes
        measures_dir = File.join(dir, 'my_measures')
        FileUtils.mkdir_p(measures_dir)

        yaml = "local_measure_roots:\n  - my_measures\n"
        path = write_manifest(dir, yaml)

        result = manager_for(path, dir).local_measure_directories
        expect(result).to eq [measures_dir]
      end
    end

    it 'filters out paths that do not exist' do
      Dir.mktmpdir do |dir|
        yaml = "local_measure_roots:\n  - nonexistent_dir\n"
        path = write_manifest(dir, yaml)

        result = manager_for(path, dir).local_measure_directories
        expect(result).to be_empty
      end
    end

    it 'deduplicates identical paths' do
      Dir.mktmpdir do |dir|
        measures_dir = File.join(dir, 'measures')
        FileUtils.mkdir_p(measures_dir)

        yaml = "local_measure_roots:\n  - measures\n  - measures\n"
        path = write_manifest(dir, yaml)

        result = manager_for(path, dir).local_measure_directories
        expect(result).to eq [measures_dir]
      end
    end

    it 'falls back to LOCAL_MEASURES_DIR when local_measure_roots is empty' do
      Dir.mktmpdir do |dir|
        yaml = "local_measure_roots: []\n"
        path = write_manifest(dir, yaml)

        result = manager_for(path, dir).local_measure_directories
        expect(result).to eq [LOCAL_MEASURES_DIR]
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe '#resolved_measure_directories' do
    it 'returns empty array when manifest does not exist' do
      Dir.mktmpdir do |dir|
        mgr = manager_for(File.join(dir, 'missing.yml'), dir)
        expect(mgr.resolved_measure_directories).to eq []
      end
    end

    it 'returns empty array when repos list is empty' do
      Dir.mktmpdir do |dir|
        path = write_manifest(dir, "repos: []\n")
        expect(manager_for(path, dir).resolved_measure_directories).to eq []
      end
    end

    it 'returns existing measure root directories for installed repos' do
      Dir.mktmpdir do |dir|
        install_dir = File.join(dir, 'vendor')
        repo_root   = File.join(install_dir, 'my_repo')
        mroot       = File.join(repo_root, 'measures')
        FileUtils.mkdir_p(mroot)

        yaml = <<~YAML
          repos:
            - name: my_repo
              url: https://example.com/repo.git
              ref: main
              measure_roots:
                - measures
        YAML
        path = write_manifest(dir, yaml)

        result = manager_for(path, install_dir).resolved_measure_directories
        expect(result).to eq [mroot]
      end
    end

    it 'skips repo if checkout directory does not exist' do
      Dir.mktmpdir do |dir|
        install_dir = File.join(dir, 'vendor')
        FileUtils.mkdir_p(install_dir)

        yaml = <<~YAML
          repos:
            - name: missing_repo
              url: https://example.com/repo.git
              ref: main
              measure_roots:
                - measures
        YAML
        path = write_manifest(dir, yaml)

        # Silence the OpenStudio warning — stub module + constant
        stub_const('OpenStudio', Module.new)
        stub_const('OpenStudio::Warn', 0)
        allow(OpenStudio).to receive(:logFree)

        result = manager_for(path, install_dir).resolved_measure_directories
        expect(result).to eq []
      end
    end

    it 'skips a measure_root sub-path that does not exist inside the repo' do
      Dir.mktmpdir do |dir|
        install_dir = File.join(dir, 'vendor')
        repo_root   = File.join(install_dir, 'my_repo')
        FileUtils.mkdir_p(repo_root) # repo exists but measure sub-dir does not

        yaml = <<~YAML
          repos:
            - name: my_repo
              url: https://example.com/repo.git
              ref: main
              measure_roots:
                - measures
        YAML
        path = write_manifest(dir, yaml)

        stub_const('OpenStudio', Module.new)
        stub_const('OpenStudio::Warn', 0)
        allow(OpenStudio).to receive(:logFree)

        result = manager_for(path, install_dir).resolved_measure_directories
        expect(result).to eq []
      end
    end

    it 'deduplicates identical resolved paths across repos' do
      Dir.mktmpdir do |dir|
        install_dir = File.join(dir, 'vendor')
        repo_root   = File.join(install_dir, 'repo_a')
        mroot       = File.join(repo_root, 'measures')
        FileUtils.mkdir_p(mroot)

        # Two entries pointing at the same resolved path
        yaml = <<~YAML
          repos:
            - name: repo_a
              url: https://example.com/a.git
              ref: main
              measure_roots:
                - measures
                - measures
        YAML
        path = write_manifest(dir, yaml)

        result = manager_for(path, install_dir).resolved_measure_directories
        expect(result).to eq [mroot]
      end
    end

    it 'returns multiple measure roots from one repo' do
      Dir.mktmpdir do |dir|
        install_dir = File.join(dir, 'vendor')
        repo_root   = File.join(install_dir, 'my_repo')
        mroot_a     = File.join(repo_root, 'measures')
        mroot_b     = File.join(repo_root, 'resources', 'measures')
        FileUtils.mkdir_p(mroot_a)
        FileUtils.mkdir_p(mroot_b)

        yaml = <<~YAML
          repos:
            - name: my_repo
              url: https://example.com/repo.git
              ref: main
              measure_roots:
                - measures
                - resources/measures
        YAML
        path = write_manifest(dir, yaml)

        result = manager_for(path, install_dir).resolved_measure_directories
        expect(result).to contain_exactly(mroot_a, mroot_b)
      end
    end
  end

  # ---------------------------------------------------------------------------
  describe 'manifest validation' do
    it 'raises when repos key is not an array' do
      Dir.mktmpdir do |dir|
        path = write_manifest(dir, "repos: not_an_array\n")
        expect { manager_for(path, dir).configured? }.to raise_error(StandardError, /Expected 'repos' array/)
      end
    end

    it 'raises when a repo entry is missing required keys' do
      Dir.mktmpdir do |dir|
        yaml = <<~YAML
          repos:
            - name: incomplete_repo
              url: https://example.com/repo.git
        YAML
        path = write_manifest(dir, yaml)
        expect { manager_for(path, dir).configured? }.to raise_error(StandardError, /missing required keys/)
      end
    end

    it 'raises when measure_roots is empty' do
      Dir.mktmpdir do |dir|
        yaml = <<~YAML
          repos:
            - name: my_repo
              url: https://example.com/repo.git
              ref: main
              measure_roots: []
        YAML
        path = write_manifest(dir, yaml)
        expect { manager_for(path, dir).configured? }.to raise_error(StandardError, /non-empty measure_roots/)
      end
    end

    it 'raises when a repo entry is not a hash' do
      Dir.mktmpdir do |dir|
        yaml = "repos:\n  - just_a_string\n"
        path = write_manifest(dir, yaml)
        expect { manager_for(path, dir).configured? }.to raise_error(StandardError, /must be a map/)
      end
    end
  end
end
