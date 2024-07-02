# frozen_string_literal: true

# rubocop:disable Style/BlockComments
=begin
===============================================================================
This script is designed to interact with the OpenAI API to assist with
various Git tasks. It leverages the capabilities of OpenAI's GPT model to
generate commit messages, pull request descriptions, and code reviews based
on the changes made in your codebase.

The script is organized into a series of modules and classes. The Constants
module defines various constants and questions that are used to interact
with the OpenAI API. The ChatGPTGenerator class is the core of the script,
responsible for sending requests to the OpenAI API and handling the responses.

The ChatGPTGenerator class includes methods to retrieve the current branch,
commit messages, and code changes from your local Git repository. It also
includes methods to validate the retrieved data and to prompt the user for
input when necessary.

The script uses the OpenAI API to generate meaningful and conventional commit
messages, pull request descriptions, and code reviews based on the changes
made in your code. It does this by sending a formatted question to the API
and processing the response.

The ChatGPTGenerator class also includes methods to handle API errors, extract
messages from the API response, and display a summary of the operation.

You need to have an OpenAI API key to use this script.
You can get an API key by signing up for an OpenAI account at
https://beta.openai.com/.

Requirements:
  - Ruby 2.6 or higher
  - Bundler
  - OpenAI API key set in OPENAI_API_KEY environment variable
  - OpenAI model ID set in OPENAI_MODEL environment variable

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!! IMPORTANT !!! IMPORTANT !!! IMPORTANT !!! IMPORTANT !!! IMPORTANT !!!
This script sends your staged changes to the OpenAI API.
That means that your staged changes will be sent to OpenAI's servers.
Be careful not to run this script on any sensitive data.
Make sure you are complying with the rules and terms of use for
the codebase you are working on.

Review OpenAI's Terms of Use at https://openai.com/policies/terms-of-use
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
===============================================================================
=end
# rubocop:enable Style/BlockComments

# =============================================================================
# Setup and Functions
# =============================================================================

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'base64'
  gem 'bigdecimal'
  gem 'csv'
  gem 'clipboard', require: true # A gem for interacting with the clipboard
  gem 'colorize', require: true # A gem for adding colors to the console output
  gem 'httparty', require: true # A gem for making HTTP requests
  gem 'pry', require: true # A gem for debugging
  gem 'tty-prompt', require: true # A gem for displaying prompts in the console
end

require 'json'
require 'ostruct'
require 'time'

module Constants
  # OpenAI API Configuration
  OPENAI_URL = 'https://api.openai.com/v1/chat/completions'
  OPENAI_API_KEY = ENV.fetch('OPENAI_API_KEY', nil)
  OPENAI_MODEL = ENV.fetch('OPENAI_MODEL', nil)

  # Commit Message Generation
  COMMIT_FUNCTION_DESCRIPTION = 'Generate a conventional commit message based on the staged changes.'
  COMMIT_FUNCTION_PROPERTIES = {
    body: {
      type: 'string',
      description: 'The body of the commit message. Use multiple lines in a bulleted list to \
              succinctly describe the changes. Lines wrap at 72 characters'
    },
    subject: {
      type: 'string',
      description: "The subject line of the commit message. Briefly summarize the changes. \
              Concise, under 50 characters. Follows conventional commit message format, so the message \
              must start with `feat:`, `fix:`, `refactor:`, etc.. Does not use generic summaries \
              like 'Updated files'. Does not include filenames in the subject line."
    }
  }.freeze
  COMMIT_FUNCTION_QUESTION = <<~QUESTION
    Create a conventional commit message based on these file changes:
    ```shell
    <-- STAGED CHANGES -->
    ```
  QUESTION

  # Pull Request Template Generation
  PR_FUNCTION_DESCRIPTION = 'Generate a title and description for a pull request based on the commit messages and the \
    changes in the current branch compared to the target branch.'
  PR_FUNCTION_PROPERTIES = {
    title: {
      type: 'string',
      description: 'The title of the pull request.'
    },
    description: {
      type: 'string',
      description: 'The description of the pull request.'
    }
  }.freeze
  PR_FUNCTION_QUESTION = <<~QUESTION
    I need you to help me write a pull request for the changes in my branch. I need a title for the pull request that is concise and less than 50 characters. The title must be in conventional commit message format starting with `feat:`, `fix:`, `refactor:`, etc. I also need a description for the pull request. Fill out the provided template for the pull request description based on the provided changes and commit messages.

    For the description you should analyze the commits and generate a summary. Do not just list the commit messages from the branch.

    Here is the template:

    ```markdown
    ## Why?

    <-- BRIEF PARAGRAPH(S) DESCRIBING PURPOSE OF THE CHANGES -->


    ## What Changed?

    <-- BULLETED LIST SUMMARIZING THE CHANGES MADE IN THE PR -->

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
  REVIEW_FUNCTION_DESCRIPTION = 'Generate a summary and a code review based on the changes provided.'
  REVIEW_FUNCTION_PROPERTIES = {
    summary: {
      type: 'string',
      description: 'A summary of the changes made in the code. Include the purpose of the changes and the \
              high-level impact.'
    },
    review: {
      type: 'string',
      description: 'The code review message. Include any issues found and suggestions for improvement.'
    }
  }.freeze
  REVIEW_FUNCTION_QUESTION = <<~QUESTION
    Review the changes provided and provide feedback on the code.

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

  attr_reader :api_key, :code_changes, :function_description, :function_properties, :function_question, :message,
              :model, :prompt, :response, :response_obj

  def initialize(_args = nil)
    @api_key = ENV.fetch('OPENAI_API_KEY', nil)
    @model = ENV.fetch('OPENAI_MODEL', nil)
    puts "Using OpenAI Model: #{@model.blue}"
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
    @current_branch = `git --no-pager rev-parse --abbrev-ref HEAD`
  end

  def get_commit_messages
    @commit_messages = `git --no-pager log --no-patch --pretty=format:\"=-=-=-=-=-=-=-=-=-=-%n%h | %cd%n%s%n%b\" #{target_branch}..#{current_branch}`
  end

  def set_changes_from_local
    @code_changes = `git --no-pager diff --unified=1`
  end

  def set_changes_from_branches
    set_current_branch
    prompt_for_target_branch if target_branch.nil?
    @code_changes = `git --no-pager diff --unified=1 #{target_branch}..#{current_branch}`
  end

  def set_changes_from_staged
    @code_changes = `git diff --cached --unified=1`
  end

  def prompt_for_target_branch
    branch_options = `git --no-pager branch --format="%(refname:short)"`.split("\n")
    branch_options.delete(current_branch)
    branch_options.delete('main')
    branch_options.prepend('main')
    @target_branch = prompt.select('Select the target branch for the PR:', branch_options)
  end

  def set_changes_from_commit
    commit_options = `git --no-pager log --oneline`.strip.split("\n")
    selected_commit = prompt.select('Select a commit to review:', commit_options)
    @code_changes = `git --no-pager show --unified=1 --pretty=\"\" #{selected_commit.split(' ')[0]}`
  end

  def validate_code_changes
    return unless code_changes.empty?

    raise 'No code changes found. Please try again.'
  end

  def validate_commit_messages
    return unless commit_messages.empty?

    raise 'No commit messages found. Please make some commits before running this script.'
  end

  private

  def headers
    {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{@api_key}"
    }
  end

  def message_body
    message = {
      model: @model,
      messages: [{ role: 'user', content: question }],
      functions: [function_definition],
      temperature: 0.25
    }
    message.to_json
  end

  def function_definition
    {
      name: 'chatgpt_response_data',
      description: function_description,
      parameters: {
        type: 'object',
        properties: function_properties
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

    setup
  end

  def setup
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

  def additional_actions
    {
      'Submit commit with this message' => -> { submit_commit },
      'Edit message before committing' => -> { edit_and_submit_commit }
    }
  end

  def submit_commit
    system("git --no-pager commit --message \"#{message}\"")
  end

  def edit_and_submit_commit
    system("git --no-pager commit --edit --message \"#{message}\"")
  end
end

# This class rewrites a selected commit message.
# It prompts the user to select a commit to rewrite and then retrieves the changes
# for that commit.
class CommitMessageRewriter < CommitMessageGenerator
  attr_reader :commit_list, :selected_commit

  def setup
    retrieve_commits
    prompt_for_commit
    retrieve_commit_changes
  end

  def prompt_for_commit
    # Prompts the user to select a commit to rewrite
    options = commit_list.strip.split("\n")
    selection = prompt.select('Select a commit to rewrite:', options)
    @selected_commit = selection.split(' ')[0]
  end

  def retrieve_commits
    @commit_list = `git --no-pager log --oneline`
  end

  def retrieve_commit_changes
    @code_changes = `git --no-pager show --unified=1 #{selected_commit}`
  end

  def additional_actions
    {
      'Submit commit with this message' => -> { submit_commit },
      'Edit message before committing' => -> { edit_and_submit_commit }
    }
  end

  def submit_commit
    message = <<~MESSAGE

      ⚠️ !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! ⚠️
      This script cannot rewrite commits yet.
      Please use Lazygit or another tool to rewrite the commit.

      The commit message has been copied to your clipboard.
      ⚠️ !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! ⚠️

    MESSAGE
    puts message.yellow
  end

  def edit_and_submit_commit
    message = <<~MESSAGE

      ⚠️ !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! ⚠️
      This script cannot rewrite commits yet.
      Please use Lazygit or another tool to rewrite the commit.

      The commit message has been copied to your clipboard.
      ⚠️ !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! ⚠️

    MESSAGE
    puts message.yellow
  end
end

# This class generates a title and description for a pull request.
# It uses the commit messages and the changes in the in the current branch
# compared to the target branch to generate the PR content.
class PRMessageGenerator < ChatGPTGenerator
  attr_reader :target_branch, :current_branch, :commit_messages

  def initialize(target_branch = nil)
    super
    @function_properties = PR_FUNCTION_PROPERTIES
    @function_description = PR_FUNCTION_DESCRIPTION
    @function_question = PR_FUNCTION_QUESTION

    @target_branch = target_branch
    if target_branch.nil?
      set_current_branch
      prompt_for_target_branch
    end

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

# This class generates a code review of the changes supplied.
# Changes can be the staged content, the current differences in the branch,
# a specific commit, or the diff between two branches.
class CodeReviewer < ChatGPTGenerator
  attr_reader :code_changes, :target_branch, :current_branch

  def initialize
    super

    @function_properties = REVIEW_FUNCTION_PROPERTIES
    @function_description = REVIEW_FUNCTION_DESCRIPTION
    @function_question = REVIEW_FUNCTION_QUESTION

    prompt_for_code_source
    validate_code_changes
  end

  def prompt_for_code_source
    review_actions = {
      'Current changes' => method(:set_changes_from_local),
      'Staged changes' => method(:set_changes_from_staged),
      'Changes between branches' => method(:set_changes_from_branches),
      'Specific commit' => method(:set_changes_from_commit)
    }

    review_type = prompt.select('What would you like to review?', review_actions.keys)
    review_actions[review_type].call
  end

  def question
    base_question = function_question.sub('<-- CODE CHANGES -->', code_changes)
    base_question.gsub("\n", ' ')
  end

  def extract_message_from_response
    super
    @message = <<~MESSAGE
      Summary:
      #{response_obj.summary}

      Review:
      #{response_obj.review}

    MESSAGE
    Clipboard.copy(message)
  end

  def display_summary
    super
    puts "\nThe code review has been copied to your clipboard and is displayed below:\n".magenta
    puts message.cyan
    puts "\n--------------------------------------------------------------------------------".white
  end
end

# This class handles user interaction and provides options for the user
# to submit the generated message, edit the message, or exit.
class UserInteractionHandler
  attr_reader :generator, :prompt, :message

  def initialize(operation_type, target_branch)
    @prompt = TTY::Prompt.new
    case operation_type&.downcase
    when 'commit'
      @generator = CommitMessageGenerator.new
    when 'pr'
      @generator = PRMessageGenerator.new(target_branch)
    when 'rewrite'
      @generator = CommitMessageRewriter.new
    when 'review'
      @generator = CodeReviewer.new
    else
      prompt_for_operation_type
    end
  end

  def run_generator
    generator.generate_messages
    prompt_for_next_action
  rescue StandardError => e
    handle_error(e)
  rescue Interrupt
    exit_gracefully 1
  end

  private

  def prompt_for_operation_type
    operation_types = {
      'Generate a commit message for the currently staged changes' => 'CommitMessageGenerator',
      'Generate a Pull Request message' => 'PRMessageGenerator',
      'Rewrite a commit message' => 'CommitMessageRewriter',
      'Review code changes' => 'CodeReviewer',
      'Exit' => 'Exit'
    }

    user_input = prompt.select('What would you like to do?', operation_types.keys)
    exit_gracefully if user_input == 'Exit'
    puts "\nStarting the #{operation_types[user_input]}...".yellow
    @generator = Object.const_get(operation_types[user_input]).new
  end

  def prompt_for_next_action
    user_actions = {
      'Regenerate (does not load code changes)' => method(:run_generator),
      'Start a debugger session' => method(:start_debugger),
      'Exit' => method(:exit_gracefully)
    }

    user_actions = generator.additional_actions.merge!(user_actions) if generator.respond_to?(:additional_actions)

    user_input = prompt.select("\nWhat would you like to do?", user_actions.keys)
    user_actions[user_input].call
  end

  def handle_error(e)
    puts "\nEncountered an error:".yellow
    puts "#{e.class}: #{e.message}".red
    puts e.backtrace.join("\n").yellow
    start_debugger
  end

  def exit_gracefully(exit_code = 0)
    puts "\nExiting application...".yellow
    exit exit_code
  end

  def start_debugger
    puts "\nStarting debugger session...".yellow
    binding.pry
    exit_gracefully
  end
end

# =============================================================================
# Main Script
# =============================================================================

operation_type = ARGV[0] # Get operation type from command line argument
target_branch = ARGV[1] # Get target branch from command line argument
handler = UserInteractionHandler.new(operation_type, target_branch)

handler.run_generator
