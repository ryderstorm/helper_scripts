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

OPENAI_URL = 'https://api.openai.com/v1/chat/completions'
OPENAI_API_KEY = ENV['OPENAI_API_KEY']
OPENAI_MODEL = ENV['OPENAI_MODEL']
if OPENAI_API_KEY.nil? || OPENAI_MODEL.nil?
  puts 'Please set the OPENAI_API_KEY and OPENAI_MODEL environment variables.'.red
  exit 1
end

@staged_content = `git --no-pager diff --staged --unified=1`
if @staged_content.empty?
  puts 'No changes have been staged. Please stage changes before running this script.'.red
  exit 1
end

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

def question
  <<~QUESTION
    I need you to create a commit message for me based on these guidelines:

    - Use the past tense for the commit message.
    - Include a subject line and a body with a bulleted list of more details.
    - The subject line should be followed by a blank line
    - The subject line should be a single line that is no longer than 50 characters
    - If the changes only include 1 file, then the subject line should include the file name.
    - The body should use bullets if appropriate.
    - The lines in the body should wrap at 72 characters

    Format your response as JSON with the following structure:
    ```json
    {
      "subject": "<SUBJECT_LINE>",
      "body": "<BODY>"
    }
    ```

    Here are the differences for the commit:
    ```#{@staged_content}```
  QUESTION
end

def headers
  {
    'Content-Type' => 'application/json',
    'Authorization' => "Bearer #{OPENAI_API_KEY}"
  }
end

def message_body
  formatted_question = question.gsub("\n", ' ')
  {
    "model": ENV['OPENAI_MODEL'],
    "messages": [{ "role": 'user', "content": formatted_question }],
    "temperature": 0.25
  }.to_json
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

# ==============================================================================
# Main Script
# ==============================================================================

begin
  prompt = TTY::Prompt.new

  puts "\n--------------------------------------------------------------------------------".white
  # Start timer
  start_time = Time.now

  # Send request to OpenAI API
  response = send_request_to_openai_api

  # Check for errors in the response
  if response['error']
    print "✗\n\nOpenAI API Error: #{response['error']}\n".red
    exit 1
  end
  print "✓\n".green

  # Extract the generated commit message from the response
  json_response = response['choices'][0]['message']['content']
  parsed_response = JSON.parse(json_response, object_class: OpenStruct)

  # Escape double quotes and tildes in the commit message
  message = <<~MESSAGE
    #{parsed_response.subject}

    #{parsed_response.body.gsub('"', '\"').gsub('`', "'")}

  MESSAGE

  # Commit message created with help from ChatGPT.
  Clipboard.copy(message) # Copy the generated commit message to the clipboard

  # End timer and display summary
  end_time = Time.now
  elapsed_time = end_time - start_time
  time_message = "\nTime to get message from ChatGPT: #{elapsed_time.round(2)} seconds"
  puts time_message.yellow
  puts "\nThe commit message has been copied to your clipboard and is displayed below".magenta
  puts message.cyan
  puts "\n--------------------------------------------------------------------------------".white

  # Prompt the user for how to proceed
  user_input = prompt.select("\nWhat would you like to do?") do |menu|
    menu.enum '.'

    menu.choice 'Submit commit with this message', 1
    menu.choice 'Edit message before committing', 2
    menu.choice 'Exit without committing', 3
    menu.choice 'Start a debugger session', 4
  end
rescue StandardError => e
  puts "\nEncountered an error:".yellow
  puts "#{e.class}: #{e.message}".red
  binding.pry
  puts "\nExiting debugger session...".yellow
rescue SystemExit, Interrupt
  # Gracefully handle exceptions like Ctrl-C or Ctrl-D
  puts "\nExiting without committing...".yellow
  exit 1
end

# Process the user's input
case user_input
when 1
  puts "\nSubmitting commit...".white
  system("git commit -m \"#{message}\"")
when 2
  puts "\nOpening editor...".white
  system("git commit -e -m \"#{message}\"")
when 3
  puts "\nExiting without committing...".yellow
  exit 1
when 4
  puts "\nStarting debugger session...".yellow
  binding.pry
  puts "\nExiting debugger session...".yellow
end
