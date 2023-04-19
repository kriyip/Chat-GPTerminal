#!/bin/bash

# check if OpenAI API key is set as environment variable
if [[ -z "$OPENAI_API_KEY" ]]; then
        echo "Please set your OpenAI API key as the environment variable OPENAI_API_KEY by running: export OPENAI_API_KEY=..."
        echo "You can create an API key at https://beta.openai.com/account/api-keys"
        exit 1
fi

echo $OPENAI_API_KEY
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
        echo $response | python -c "import sys, json; print(json.load(sys.stdin))"
}

# answer=$(ask_question)
prompt=$1
ask_question
# echo $1