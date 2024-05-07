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
end

require 'json'
require 'ostruct'
require 'time'

# This class sends a question to the OpenAI API and retrieves a response.
# It is a base class that can be used to create other classes that interact
# with the OpenAI API.
class ChatGPTGenerator
  OPENAI_URL = 'https://api.openai.com/v1/chat/completions'
  OPENAI_API_KEY = ENV['OPENAI_API_KEY']
  OPENAI_MODEL = ENV['OPENAI_MODEL']

  attr_reader :api_key, :function_description, :function_properties, :model

  def initialize
    @api_key = ENV['OPENAI_API_KEY']
    @model = ENV['OPENAI_MODEL']
  end

  def headers
    {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{@api_key}"
    }
  end

  def message_body
    formatted_question = question
    functions = function_definition
    message = {
      "model": @model,
      "messages": [{ "role": 'user', "content": formatted_question }],
      "functions": [functions],
      "temperature": 0.25
    }
    message.to_json
  end

  def function_definition
    {
      "name": 'commit_message',
      "description": function_description,
      "parameters": {
        "type": 'object',
        "properties": function_properties
      }
    }
  end

  def send_request_to_openai_api
    print 'Sending request to OpenAI API...'.white
    retries = 3
    HTTParty.post(OPENAI_URL, headers: headers, body: message_body, timeout: 180)
  rescue HTTParty::Error, Net::ReadTimeout => e
    retries -= 1
    raise e if retries.zero?

    puts "\nAttempt #{3 - retries} of 3 failed:".yellow
    puts "#{e.class}: #{e.message}".red
    sleep rand(1..5)
    retry
  end
end

# This class generates commit messages based on staged changes.
class CommitMessageGenerator < ChatGPTGenerator
  FUNCTION_DESCRIPTION = 'Generate a conventional commit message based on the staged changes.'
  FUNCTION_PROPERTIES = {
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

  attr_reader :staged_content

  def initialize
    super
    @staged_content = `git --no-pager diff --staged --unified=1`
    if @staged_content.empty?
      puts 'No changes have been staged. Please stage changes before running this script.'.red
      exit 1
    end
    @function_properties = FUNCTION_PROPERTIES
    @function_description = FUNCTION_DESCRIPTION
  end

  def question
    new_question = <<~QUESTION
      Create a convnetional commit message based on these file changes:
      ```#{staged_content}```
    QUESTION
    new_question.gsub("\n", ' ')
  end
end

# This class generates a title and description for a pull request.
# It uses the commit messages and the changes in the in the current branch
# compared to the target branch to generate the PR content.
class PRMessageGenerator < ChatGPTGenerator
end

class CommitMessageHandler
  attr_reader :generator, :prompt, :message

  def initialize
    @generator = CommitMessageGenerator.new
    @prompt = TTY::Prompt.new
  end

  def handle_commit_message
    start_time = Time.now
    response = generator.send_request_to_openai_api
    handle_api_errors(response)
    extract_commit_message(response)
    end_time = Time.now
    display_summary(start_time, end_time)
    handle_user_input
  rescue StandardError => e
    handle_error(e)
  rescue SystemExit, Interrupt
    exit_gracefully
  end

  private

  def handle_api_errors(response)
    if response['error']
      puts "✗\n\nOpenAI API Error:\n#{response['error']}\n".red
      exit 1
    end
    print "✓\n".green
  end

  def extract_commit_message(response)
    json_response = response['choices'][0]['message']['function_call']['arguments']
    parsed_response = JSON.parse(json_response, object_class: OpenStruct)
    @message = <<~MESSAGE
      #{parsed_response.subject}

      #{parsed_response.body.gsub('"', '\"').gsub('`', "'")}

    MESSAGE
    Clipboard.copy(message)
  end

  def display_summary(start_time, end_time)
    elapsed_time = end_time - start_time
    time_message = "\nTime to get message from ChatGPT: #{elapsed_time.round(2)} seconds"
    puts time_message.yellow
    puts "\nThe commit message has been copied to your clipboard and is displayed below:\n".magenta
    puts message.cyan
    puts "\n--------------------------------------------------------------------------------".white
  end

  def handle_user_input
    user_input = prompt.select("\nWhat would you like to do?") do |menu|
      menu.enum '.'
      menu.choice 'Submit commit with this message', 1
      menu.choice 'Edit message before committing', 2
      menu.choice 'Exit without committing', 3
      menu.choice 'Start a debugger session', 4
    end

    process_user_input(user_input)
  end

  def process_user_input(user_input)
    case user_input
    when 1
      puts "\nSubmitting commit...".white
      system("git commit -m \"#{message}\"")
    when 2
      puts "\nOpening editor...".white
      system("git commit -e -m \"#{message}\"")
    when 3
      exit_gracefully
    when 4
      start_debugger
    end
  end

  def handle_error(e)
    puts "\nEncountered an error:".yellow
    puts "#{e.class}: #{e.message}".red
    binding.pry
    puts "\nExiting debugger session...".yellow
  end

  def exit_gracefully
    puts "\nExiting without committing...".yellow
    exit 1
  end

  def start_debugger
    puts "\nStarting debugger session...".yellow
    binding.pry
    puts "\nExiting debugger session...".yellow
  end
end

# Use the new class in your main script
handler = CommitMessageHandler.new
handler.handle_commit_message
