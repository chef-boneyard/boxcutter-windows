#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'uri'
require 'logger'

# Environment Varibles which need to be set in the job config
BUILDKITE_ACCESS_TOKEN = ENV['BUILDKITE_ACCESS_TOKEN']
BUILDKITE_PROJECT = ENV['BUILDKITE_PROJECT'] ||= 'vsphere-baker-windows'
# Environment varibles defined by BuildKite automagically.
BUILDKITE_ORGANIZATION = ENV['BUILDKITE_ORGANIZATION_SLUG'] ||= 'chef'
BUILDKITE_BRANCH = ENV['BUILDKITE_BRANCH'] ||= 'master'
IGNORED_FILES = %w(
  gitignore
  dummy_metadata
  bin/buildkite.rb
  bin/compress.py
  scripts/common
  .tpl
  .md
).freeze

@logger = Logger.new(STDOUT)
@logger.level = Logger::INFO

@logger.debug(ENV)

def buildkite_api_uri(args = {})
  @logger.debug("buildkite_api_uri args: #{args}")
  raise Exception.new('Missing project argument') if args[:project].nil?
  raise Exception.new('Missing endpoint argument') if args[:endpoint].nil?
  raise Exception.new('Missing BuildKite access token environment variable') if BUILDKITE_ACCESS_TOKEN.nil?

  URI::HTTPS.build(
    host:   'api.buildkite.com',
    path:   "/v2/organizations/#{BUILDKITE_ORGANIZATION}/pipelines/#{args[:project]}/#{args[:endpoint]}",
    query:  "access_token=#{BUILDKITE_ACCESS_TOKEN}"
  )
end

# Returns an array of builds hashes for the environment defined project.
def buildkite_builds
  uri = buildkite_api_uri(project: BUILDKITE_PROJECT, endpoint: 'builds')
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request ||= Net::HTTP::Get.new(uri.request_uri)
  @response ||= http.request(request)

  @logger.debug(@response)
  @logger.debug(@response.code)
  @logger.debug(@response.body)

  if @response.code.to_i >= 400
    raise Exception.new("Unexpected response from BuildKite API: #{@response.code_type}")
  else
    JSON.parse(@response.body)
  end
end

# Finds the last passed build for a given working branch, and returns
# a SHA1 git hash as a string. If the branch is a new branch, this returns
# the string 'master' as a point of reference to determine changes.
def last_passed_build_git_hash
  git_hash = ''

  buildkite_builds.map do |build|
    if build['state'] == 'passed' && build['branch'] == BUILDKITE_BRANCH && commit_exits?(build['commit'])
      git_hash = build['commit']
      break
    else
      # Assume if there is no passed builds for a given branch, it is a net new
      # branch forked off of master.
      git_hash = 'master'
    end
  end

  if git_hash.empty?
    raise Exception.new('Unable to determine the commit hash of the last successful build.')
  else
    git_hash
  end
end

# Check to ensure the commit hash exists. This typically returns false when
# buildkite gives us a commit hash from a previously successful build and a
# subsequent force-push is done to rewrite history. If the commit ID exists,
# this will return true.
def commit_exits?(commit)
  system("git cat-file commit #{commit}")
end

# Return an array of files changed since the last successful build.
# Sorry for the long function name.
def changed_files_since_last_passed_build
  # Cache fileset so we don't need to regenerate the result each time.
  @changed_files_since_last_passed_build ||= begin
    # `rev-list commit_x..HEAD` shows the commit hashes for each commit from a
    # given commit to the current HEAD.
    # `--objects` shows the actual files which have changed in the series of
    # commits.
    # We strip the commit IDs via awk because its cheap and a lazy way to get only
    # the data back we need.
    objects = `git rev-list #{last_passed_build_git_hash}..HEAD  --objects | awk '{print $2}'`.split.uniq
    # Only return objects which are files, or files with a path.
    objects.select { |object| File.file?(object) && !IGNORED_FILES.include?(object) }
  end
end

# Compile the list of platforms whose boxes will be rebuilt.
buildlist = []

buildlist.concat(changed_files_since_last_passed_build.select { |b| b.include?('.json') })
buildlist.collect! { |b| b.gsub!('.json', '') }
if buildlist.empty?
  @logger.info("No template changes found to build.")
else
  # We need to do a more complex threading implementation to be able to build
  # these in parallel as Packer has a bug in which it fails when an output directory
  # already exists on the system. Attempting to use make to parallelize this will
  # result in the same
  buildlist.each do |template|
    @logger.info("Building #{template}...")
    # Create a space delimited string of make targets prefixed with vmware/
    # when invoking the make command.
    unless system("make #{template.prepend('vmware/')}")
      Kernel.exit
    end
  end
end
