#!/bin/bash

# Set up OpenAI API Secret Key
# figure out a better way to do this latter
OPENAI_API_KEY="PLACEHOLDER_API_KEY"

# Parse command line arguments (check right args given)
if [ $# -eq 0 ]
	echo "Enter your question as an argument"
	exit 1
fi

# use curl to send question data to OpenAI server and get the response
# note that response is JSON-formatted result from making request with curl
# next steps: output response in a more readable form
function ask_question {
	response=$(curl -s -X POST https://api.openai.com/v1/engines/davinci-codex/completions -H "Content-Type: "application/json" -H "Authorization: Bearer $OPENAI_API_KEY" -d "{
        \"prompt\": \"$1\",
        \"temperature\": 0.7,
        \"max_tokens\": 1024,
        \"top_p\": 1,
        \"frequency_penalty\": 0,
        \"presence_penalty\": 0
   	 }")
	echo $response
}
