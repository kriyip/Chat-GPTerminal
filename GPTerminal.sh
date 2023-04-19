#!/bin/bash

# Set up OpenAI API Secret Key
# figure out a better way to do this latter
# OPENAI_API_KEY="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"

if [[ -z "$OPENAI_API_KEY" ]]; then
        echo "Please set your OpenAI API key as the environment variable OPENAI_API_KEY"
        echo "You can create an API key at https://beta.openai.com/account/api-keys"
        exit 1
fi

# Parse command line arguments (check right args given)
if [ $# -eq 0 ]; then
	echo "Please enter a question"
	exit 1
fi

# use curl to send question data to OpenAI server and get the response
# note that response is JSON-formatted result from making request with curl
# next steps: output response in a more readable form
function ask_question {
        echo "Asking question: $prompt"
        
        response=$(curl https://api.openai.com/v1/chat/completions \
                -H 'Content-Type: application/json' \
                -H "Authorization: Bearer $OPENAI_API_KEY" \
                -d '{
                "model": "gpt-3.5-turbo",
                "messages": [{"role": "user", "content": "'"$prompt"'"}],
                "temperature": 0.7
                }')
        echo $response
}

# answer=$(ask_question)
prompt=$1
ask_question
# echo $1