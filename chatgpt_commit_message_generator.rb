# frozen_string_literal: true

# This script uses the OpenAI API to generate a commit message based on the
# changes that have been staged. It then copies the commit message to the
# clipboard and prompts the user to either submit the commit with the generated
# message, edit the message before submitting, or exit without committing.
#
# You need to have an OpenAI API key to use this script.
# You can get an API key by signing up for an OpenAI account at
# https://beta.openai.com/.
#
# Requirements:
#   - Ruby 2.6 or higher
#   - Bundler
#   - OpenAI API key set in OPENAI_API_KEY environment variable
#   - OpenAI model ID set in OPENAI_MODEL environment variable
#
# Usage:
#  1. Stage changes you want to commit
#  2. Run this script from the root of your git repository
#  3. Follow the prompts provided by the script

# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# !!! IMPORTANT !!! IMPORTANT !!! IMPORTANT !!! IMPORTANT !!! IMPORTANT !!!
# This script sends your staged changes to the OpenAI API.
# That means that your staged changes will be sent to OpenAI's servers.
# Be careful not to run this script on any sensitive data.
# Make sure you are complying with the rules and terms of use for
# the codebase you are working on.
#
# Review OpenAI's Terms of Use at https://openai.com/policies/terms-of-use
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

# ==============================================================================
# Setup and Functions
# ==============================================================================

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'clipboard', require: true # A gem for interacting with the clipboard
  gem 'colorize', require: true # A gem for adding colors to the console output
  gem 'httparty', require: true # A gem for making HTTP requests
  gem 'pry', require: true # A gem for debugging
  gem 'tty-prompt', require: true # A gem for displaying prompts in the console
  gem 'tty-command', require: true # A gem for running shell commands
end

require 'json'
require 'ostruct'
require 'time'

module Constants
  # OpenAI API Configuration
  OPENAI_URL = 'https://api.openai.com/v1/chat/completions'
  OPENAI_API_KEY = ENV['OPENAI_API_KEY']
  OPENAI_MODEL = ENV['OPENAI_MODEL']

  # Commit Message Generation
  COMMIT_FUNCTION_DESCRIPTION = 'Generate a conventional commit message based on the staged changes.'
  COMMIT_FUNCTION_PROPERTIES = {
    "body": {
      "type": 'string',
      "description": 'The body of the commit message. Use multiple lines in a bulleted list to \
              succintly describe the changes. Lines wrap at 72 characters'
    },
    "subject": {
      "type": 'string',
      "description": "The subject line of the commit message. Briefly summarize the changes. \
              Concise, under 50 characters. Follows conventional commit message format, so the message \
              must start with `feat:`, `fix:`, `refactor:`, etc.. Does not use generic summaries \
              like 'Updated files'. Does not include filenames in the subject line."
    }
  }.freeze
  COMMIT_FUNCTION_QUESTION = <<~QUESTION
    Create a convnetional commit message based on these file changes:
    ```shell
    <-- STAGED CHANGES -->
    ```
  QUESTION

  # Pull Request Template Generation
  PR_FUNCTION_DESCRIPTION = 'Generate a title and description for a pull request based on the commit messages and the \
    changes in the current branch compared to the target branch.'
  PR_FUNCTION_PROPERTIES = {
    "title": {
      "type": 'string',
      "description": 'The title of the pull request. Concise, under 50 characters. Must start with a conventional \
              commit message prefix like `feat:`, `fix:`, `refactor:`, etc.'
    },
    "description": {
      "type": 'string',
      "description": 'The description of the pull request. Use multiple lines to describe the changes in detail. \
              Include references to issues or other PRs if applicable.'
    }
  }.freeze
  PR_FUNCTION_QUESTION = <<~QUESTION
    Fill out a Pull Request template based on the changes and commits in the branch for the PR.

    Here is the template:

    ```markdown
    ## Why?

    <-- PARAPGRAH(S) DESCRIBING WHY THESE CHANGES ARE NECESSARY -->


    ## What Changed?

    <-- BULLETED LIST OF CHANGES MADE IN THE PR -->

    ```

    ---

    Here are the commit messages for the PR:

    ```shell

    <-- COMMIT MESSAGES -->

    ```

    ---

    Here are the code changes for the PR:

    ```shell

    <-- CODE CHANGES -->

    ```

  QUESTION
end

# This class sends a question to the OpenAI API and retrieves a response.
# It is a base class that can be used to create other classes that interact
# with the OpenAI API.
class ChatGPTGenerator
  include Constants

  attr_reader :api_key, :function_description, :function_properties, :function_question, :message, :model, :prompt, :response,
              :response_obj

  def initialize(_args = nil)
    @api_key = ENV['OPENAI_API_KEY']
    @model = ENV['OPENAI_MODEL']
    puts "Using OpenAI Model: #{@model.blue}"
    @cmd = TTY::Command.new(printer: :null)
    @prompt = TTY::Prompt.new
    validate_required_variables
  end

  def generate_messages
    send_request_to_openai_api
    handle_api_errors
    extract_message_from_response
    display_summary
  end

  def send_request_to_openai_api
    @start_time = Time.now
    print 'Sending request to OpenAI API...'.white
    retries = 3
    @response = HTTParty.post(OPENAI_URL, headers: headers, body: message_body, timeout: 180)
    @end_time = Time.now
  rescue HTTParty::Error, Net::ReadTimeout => e
    retries -= 1
    raise e if retries.zero?

    puts "\nAttempt #{3 - retries} of 3 failed:".yellow
    puts "#{e.class}: #{e.message}".red
    sleep rand(1..5)
    retry
  end

  def extract_message_from_response
    obj = JSON.parse(response.body, object_class: OpenStruct)
    message = obj.choices[0].message
    function_response = message&.function_call&.arguments
    if function_response.nil?
      puts message.to_yaml.yellow
      raise 'Error: OpenAI API response does not contain the expected function response.'
    end
    @response_obj = JSON.parse(function_response, object_class: OpenStruct)
  end

  def display_summary
    elapsed_time = @end_time - @start_time
    time_message = "\nTime to get message from ChatGPT: #{elapsed_time.round(2)} seconds"
    puts time_message.yellow
  end

  def set_current_branch
    result = run_command('git rev-parse --abbrev-ref HEAD')
    @current_branch = result.out.strip
  end

  def get_commit_messages
    result = run_command("git --no-pager log --no-patch --pretty=format:\"=-=-=-=-=-=-=-=-=-=-%n%h | %cd%n%s%n%b\" #{target_branch}..#{current_branch}")
    @commit_messages = result.out.strip
  end

  def set_changes_from_branches
    set_current_branch
    prompt_for_target_branch if target_branch.nil?
    result = run_command("git --no-pager diff --unified=1 #{target_branch}..#{current_branch}")
    @code_changes = result.out.strip
  end

  def set_changes_from_staged
    result = run_command('git diff --cached --unified=1')
    @code_changes = result.out
  end

  def prompt_for_target_branch
    branch_options = run_command('git branch --format="%(refname:short)"').out.split("\n")
    @target_branch = prompt.select('Select the target branch for the PR:', branch_options)
  end

  def set_changes_from_commit
    commit_options = run_command('git log --oneline').out.split("\n")
    selected_commit = prompt.select('Select a commit to review:', commit_options)
    result = run_command("git --no-pager show --unified=1 --pretty=\"\" #{selected_commit.split(' ')[0]}")
    @code_changes = result.out
  end

  def validate_code_changes
    return unless code_changes.empty?

    raise 'No code changes found. Please stage some changes before running this script.'
  end

  def validate_commit_messages
    return unless commit_messages.empty?

    raise 'No commit messages found. Please make some commits before running this script.'
  end

  private

  def run_command(command)
    result = @cmd.run!(command)
    raise "Error: #{result.error}" if result.failure?

    result
  end

  def headers
    {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{@api_key}"
    }
  end

  def message_body
    message = {
      "model": @model,
      "messages": [{ "role": 'user', "content": question }],
      "functions": [function_definition],
      "temperature": 0.25
    }
    message.to_json
  end

  def function_definition
    {
      "name": 'chatgpt_response_data',
      "description": function_description,
      "parameters": {
        "type": 'object',
        "properties": function_properties
      }
    }
  end

  def validate_required_variables
    return unless api_key.nil? || model.nil?

    raise 'Please set the OPENAI_API_KEY and OPENAI_MODEL environment variables.'
  end

  def handle_api_errors
    if response['error']
      puts <<~API_ERROR

        ❌ OpenAI API Error ❌
        #{JSON.pretty_generate(response['error']).yellow}
      API_ERROR
      raise 'Exiting due to OpenAI API error.'
    end
    print "✓\n".green
  end
end

# This class generates commit messages based on staged changes.
class CommitMessageGenerator < ChatGPTGenerator
  attr_reader :code_changes

  def initialize
    super
    @function_properties = COMMIT_FUNCTION_PROPERTIES
    @function_description = COMMIT_FUNCTION_DESCRIPTION
    @function_question = COMMIT_FUNCTION_QUESTION

    set_changes_from_staged
    validate_code_changes
  end

  def question
    base_question = function_question.sub('<-- STAGED CHANGES -->', code_changes)
    base_question.gsub("\n", ' ')
  end

  def extract_message_from_response
    super
    @message = <<~MESSAGE
      #{response_obj.subject}

      #{response_obj.body.gsub('"', '\"').gsub('`', "'")}

    MESSAGE
    Clipboard.copy(message)
  end

  def display_summary
    super
    puts "\nThe commit message has been copied to your clipboard and is displayed below:\n".magenta
    puts message.cyan
    puts "\n--------------------------------------------------------------------------------".white
  end

  def submit_commit
    @cmd.run("git commit -m \"#{message}\"")
  end

  def edit_and_submit_commit
    @cmd.run("git commit -e -m \"#{message}\"")
  end
end

  end
end

# This class generates a title and description for a pull request.
# It uses the commit messages and the changes in the in the current branch
# compared to the target branch to generate the PR content.
class PRMessageGenerator < ChatGPTGenerator
  attr_reader :target_branch, :current_branch, :commit_messages, :code_changes

  def initialize(target_branch)
    super
    @function_properties = PR_FUNCTION_PROPERTIES
    @function_description = PR_FUNCTION_DESCRIPTION
    @function_question = PR_FUNCTION_QUESTION

    @target_branch = target_branch

    get_commit_messages
    set_changes_from_branches
    validate_branches
    validate_code_changes
    validate_commit_messages
  end

  def question
    base_question = function_question
                    .sub('<-- COMMIT MESSAGES -->', commit_messages)
                    .sub('<-- CODE CHANGES -->', code_changes)
    base_question.gsub("\n", ' ')
  end

  def extract_message_from_response
    super
    @message = <<~MESSAGE
      PR Title: #{response_obj.title}

      PR Description:
      #{response_obj.description}

    MESSAGE
    Clipboard.copy(message)
  end

  def display_summary
    super
    puts "\nThe PR description has been copied to your clipboard. The PR title and description are displayed below:\n".magenta
    puts message.cyan
    puts "\n--------------------------------------------------------------------------------".white
  end

  private

  def validate_branches
    if current_branch.empty? || target_branch.empty?
      raise 'Unable to determine the current branch or the target branch. Please check your git configuration.'
    end

    return unless current_branch == target_branch

    raise 'The current branch and the target branch are the same. Please provide a different target branch.'
  end


  end
end

# This class handles user interaction and provides options for the user
# to submit the generated message, edit the message, or exit.
class UserInteractionHandler
  attr_reader :generator, :prompt, :message

  def initialize(operation_type, target_branch)
    @prompt = TTY::Prompt.new
    case operation_type.downcase
    when 'commit'
      @generator = CommitMessageGenerator.new
    when 'pr'
      @generator = PRMessageGenerator.new(target_branch)
    else
      raise "Invalid operation type: [#{operation_type}]. Please provide a valid operation type."
    end
  end

  def run_generator
    generator.generate_messages
    handle_user_input
  rescue StandardError => e
    handle_error(e)
  rescue SystemExit, Interrupt
    exit_gracefully
  end

  private

  def handle_user_input
    user_input = prompt.select("\nWhat would you like to do?") do |menu|
      menu.enum '.'
      menu.choice 'Submit commit with this message'
      menu.choice 'Edit message before committing'
      menu.choice 'Exit without committing'
      menu.choice 'Regenerate'
      menu.choice 'Start a debugger session'
    end

    process_user_input(user_input)
  end

  def process_user_input(user_input)
    case user_input
    when 'Submit commit with this message'
      generator.submit_commit
    when 'Edit message before committing'
      generator.edit_and_submit_commit
    when 'Exit without committing'
      exit_gracefully
    when 'Regenerate'
      run_generator
    when 'Start a debugger session'
      start_debugger
    end
  end

  def handle_error(e)
    puts "\nEncountered an error:".yellow
    puts "#{e.class}: #{e.message}".red
    puts e.backtrace.join("\n").yellow
    binding.pry
    puts "\nExiting debugger session...".yellow
  end

  def exit_gracefully
    puts "\nExiting...".yellow
    exit 1
  end

  def start_debugger
    puts "\nStarting debugger session...".yellow
    binding.pry
    puts "\nExiting debugger session...".yellow
  end
end

# ==============================================================================
# Main Script
# ==============================================================================

operation_type = ARGV[0] # Get operation type from command line argument
target_branch = ARGV[1] # Get target branch from command line argument
handler = UserInteractionHandler.new(operation_type, target_branch)

handler.run_generator
