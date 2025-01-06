#!/usr/bin/env ruby

require 'httparty'
require 'colorize'
require 'json'
require 'tty-spinner'
require 'tty-prompt'

# ===============================
# ChatGPT CLI Script
# ===============================
#
# This script sends a user-provided question to OpenAI's ChatGPT API
# and prints the response with colorized output.
#
# Dependencies:
#   - httparty
#   - colorize
#
# Usage:
#   ruby chatgpt.rb "Your question here"
#
# Example:
#   ruby chatgpt.rb "Explain the theory of relativity."
#
# ===============================

# Function to display usage instructions
def display_usage
  puts "\nUsage: ruby chatgpt.rb \"Your question here\"\n\n".yellow
  exit 1
end

def spacer
  puts "\n#{'=' * 100}\n".white
end

spacer
# Retrieve the API key from environment variables
api_key = ENV['OPENAI_API_KEY_PERSONAL']
model = 'gpt-4o-mini'

# Validate the presence of the API key
if api_key.nil? || api_key.strip.empty?
  puts 'Error: OPENAI_API_KEY environment variable is not set.'.red
  puts 'Please set it using the following command:'
  puts "export OPENAI_API_KEY=\"your_openai_api_key_here\"\n\n".yellow
  exit 1
end

# Retrieve the user's question from command-line arguments
# if ARGV.empty?
#   puts 'Error: No question provided.'.red
#   display_usage
# end

# Combine all arguments to support multi-word questions
user_question = ARGV.join(' ').strip

# Validate the user's question
if user_question.empty?
  prompt = TTY::Prompt.new
  user_question = prompt.ask('Please enter your question:', required: true)
end

# Define the API endpoint
api_endpoint = 'https://api.openai.com/v1/chat/completions'

# Construct the payload as per OpenAI's API requirements
payload = {
  model: model,
  messages: [
    {
      role: 'system',
      content: 'You are a helpful assistant. Your interface is a CLI in a terminal. Keep your responses concise and informative. Include ANSI color codes for text formatting in your responses.'
    },
    {
      role: 'user',
      content: user_question
    }
  ],
  max_tokens: 500,      # Adjust as needed
  temperature: 0.7      # Adjust for creativity
}

# Set up the headers, including the authorization token
headers = {
  'Content-Type' => 'application/json',
  'Authorization' => "Bearer #{api_key}"
}

# Start a spinner to indicate that the request is being processed
spinner = TTY::Spinner.new('[:spinner] Thinking...', format: :bouncing)
spinner.auto_spin

# Make the POST request within a begin-rescue block for error handling
begin
  response = HTTParty.post(
    api_endpoint,
    headers: headers,
    body: payload.to_json,
    timeout: 15 # seconds
  )
rescue SocketError => e
  spinner.stop('Failed!'.red)
  puts "Network connection error: #{e.message}".red
  spacer
  exit 1
rescue Net::OpenTimeout, Net::ReadTimeout => e
  spinner.stop('Failed!'.red)
  puts "Request timed out: #{e.message}".red
  spacer
  exit 1
rescue HTTParty::Error => e
  spinner.stop('Failed!'.red)
  puts "HTTParty error: #{e.message}".red
  spacer
  exit 1
rescue StandardError => e
  spinner.stop('Failed!'.red)
  puts "An unexpected error occurred: #{e.message}".red
  spacer
  exit 1
end

# Check if the response was successful
unless response.code == 200
  spinner.stop('Failed!'.red)
  puts "API Error (Status Code: #{response.code}):".red
  begin
    error_details = JSON.parse(response.body)
    if error_details['error'] && error_details['error']['message']
      puts error_details['error']['message'].yellow
    else
      puts response.body.yellow
    end
  rescue JSON::ParserError
    puts response.body.yellow
  end
  spacer
  exit 1
end

spinner.success
# Parse the successful response
begin
  parsed_response = JSON.parse(response.body)
  # Navigate through the JSON structure to extract the assistant's reply
  assistant_message = parsed_response.dig('choices', 0, 'message', 'content')

  if assistant_message.nil? || assistant_message.strip.empty?
    puts 'Received an empty response from the API.'.red
    spacer
    exit 1
  end

  # Print the assistant's message with colorization
  puts "\nChatGPT:".green
  wrapped_message = assistant_message.strip.scan(/.{1,100}/).join("\n")
  puts wrapped_message
  spacer
rescue JSON::ParserError => e
  puts "Failed to parse JSON response: #{e.message}".red
  spacer
  exit 1
rescue NoMethodError => e
  puts "Unexpected response structure: #{e.message}".red
  spacer
  exit 1
end
