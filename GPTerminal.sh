#!/bin/bash

# set default model parameters
DEFAULT_INIT_PROMPT="Answer as concisely as possible. "
WRITE_CODE_INIT_PROMPT="You are translating a prompt into code. Answer as concisely as possible. "
EXPLAIN_CODE_INIT_PROMPT="You are summarizing a code snippet in natural language. "
TEMPERATURE="0.7"

# 1 for context, 0 for no context
CONTEXT=1

CONTEXT_FILE_PATH="~/GPTerminal_History/chat_1"
MODEL="gpt-3.5-turbo"

# 1 for verbose, 0 for not verbose
VERBOSE=0

USER_INIT_PROMPT=""

# check if OpenAI API key is set as environment variable
if [[ -z "$OPENAI_API_KEY" ]]; then
        echo "Please set your OpenAI API key as the environment variable OPENAI_API_KEY by running: export OPENAI_API_KEY=..."
        echo "You can create an API key at https://beta.openai.com/account/api-keys"
        exit 1
fi

function init {
        # check if context file exists
        if [ ! -f "$CONTEXT_FILE_PATH" ]; then
                touch "$CONTEXT_FILE_PATH"
                chmod 700 "$CONTEXT_FILE_PATH"
        fi
}

# use curl to send question data to OpenAI server and get the response
# note that response is JSON-formatted result from making request with curl
# next steps: output response in a more readable form
function ask_question {
        echo "First parameter: $1"
        
        response=$(curl https://api.openai.com/v1/chat/completions \
                -H 'Content-Type: application/json' \
                -H "Authorization: Bearer $OPENAI_API_KEY" \
                -d '{
                "model": "'"$MODEL"'",
                "messages": [{"role": "user", "content": "'"$1"'"}],
                "temperature": '"$TEMPERATURE"'
                }')
        # echo $response
        echo $response | python -c "import sys, json; print(json.load(sys.stdin)['choices'][0]['message']['content'])"
}

ask_question "$1"

# parse flags/cli
while [[ $# -gt 0 ]]; do
        case $1 in
                -i | --init-chat-prompt ) 
                        if [ "$2" = "write-code" ]; then
                                USER_INIT_PROMPT="$WRITE_CODE_INIT_PROMPT"
                        elif [ "$2" = "explain-code" ]; then
                                USER_INIT_PROMPT="$EXPLAIN_CODE_INIT_PROMPT"
                        else
                                echo "Invalid init prompt: $2"
                                exit 1
                        fi
                        shift
                        shift
                        ;;
                -m | --model ) # check for other models to include
                        if [ "$2" = "gpt-3.5-turbo" ]; then
                                MODEL="$2"
                        elif [ "$2" = "gpt-3.5" ]; then
                                MODEL="$2"
                        elif [ "$2" = "gpt-3" ]; then
                                MODEL="$2"
                        else
                                echo "Invalid model: $2"
                                exit 1
                        fi
                        shift
                        shift
                        ;;
                -t | --temperature )
                        if (( $(echo "$2 > 0" | bc -l) )) && (( $(echo "$2 < 1" | bc -l) )); then
                                TEMPERATURE="$2"
                        else
                                echo "Invalid temperature: $2"
                                echo "Temperature must be between 0 and 1"
                                exit 1
                        fi
                        shift
                        shift
                        ;;
                -c | --context )
                        if [ "$2" = "on" ]; then
                                CONTEXT=1
                        elif [ "$2" = "off" ]; then
                                CONTEXT=0
                        else
                                echo "Invalid context: $2"
                                exit 1
                        fi
                        shift
                        shift
                        ;;
                -q | --question )
                        ask_question "$2"
                        ;;
                *)
                        echo "Invalid option: $1"
                        exit 1
                        ;;
        esac
done

echo "User init prompt: $USER_INIT_PROMPT"
echo "Model: $MODEL"
echo "Temperature: $TEMPERATURE"

# Parse command line arguments (check right args given)
if [ $# -eq 0 ]; then
	echo "Please enter a question"
	exit 1
fi

# type exit to exit
while true; do
        read -p "Ask a question: " question
        if [ "$question" = "exit" ]; then
                break
        fi

        ask_question "$question"
done