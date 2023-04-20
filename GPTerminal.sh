#!/bin/bash

# set default model parameters
DEFAULT_INIT_PROMPT="Answer as concisely as possible. "
WRITE_CODE_INIT_PROMPT="You are translating a prompt into code. Answer as concisely as possible. "
EXPLAIN_CODE_INIT_PROMPT="You are summarizing a code snippet in natural language. "
TEMPERATURE="0.7"

# 1 for context, 0 for no context
HAS_CONTEXT=1

CONTEXT_FILE_PATH=""
MODEL="gpt-3.5-turbo"

# 1 for verbose, 0 for not verbose
VERBOSE=0

USER_INIT_PROMPT=""

function init_context_file {
        # check if context file exists
        if [ ! -d "~/.GPTerminal" ]; then
                mkdir "~/.GPTerminal"
                mkdir "~/.GPTerminal/History"
        fi
        if [ -n "$CONTEXT_FILE_PATH" ]; then
                timestamp=$(date +"%Y-%m-%d %H:%M:%S")
                CONTEXT_FILE_PATH="~/.GPTerminal/History/$timestamp"
        fi
        touch "$CONTEXT_FILE_PATH"
        chmod 700 "$CONTEXT_FILE_PATH"
}

# called before each ask_question request
function get_context {
        # get context from context file
        context=$(cat "$CONTEXT_FILE_PATH")
        # may need to grep based on certain keywords? or is there some way I could summarize a text file?
        # first, will just make it work with basic context file and then try to make longer conversations last.
        # will drop the previous context files
        echo $context
}

build_chat_context() {
	chat_context="$1"
	escaped_prompt="$2"
	if [ -z "$chat_context" ]; then
		chat_context="$CHAT_INIT_PROMPT\nQ: $escaped_prompt"
	else
		chat_context="$chat_context\nQ: $escaped_prompt"
	fi
	request_prompt="${chat_context//$'\n'/\\n}"
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




# check if OpenAI API key is set as environment variable
if [[ -z "$OPENAI_API_KEY" ]]; then
        echo "Please set your OpenAI API key as the environment variable OPENAI_API_KEY by running: export OPENAI_API_KEY=..."
        echo "You can create an API key at https://beta.openai.com/account/api-keys"
        exit 1
fi

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
                --context )
                        if [ "$2" = "drop" ]; then
                                HAS_CONTEXT=1
                        elif [ "$2" = "summarize"]; then
                                HAS_CONTEXT=2
                        elif [ "$2" = "off" ]; then
                                HAS_CONTEXT=0
                        else
                                echo "Invalid context: $2"
                                exit 1
                        fi
                        shift
                        shift
                        ;;
                -v | --verbose )
                        if [ "$2" = "on" ]; then
                                VERBOSE=1
                        elif [ "$2" = "off" ]; then
                                VERBOSE=0
                        else
                                echo "Invalid verbose: $2"
                                exit 1
                        fi
                        shift
                        shift
                        ;;
                -c | --continue-chat )
                        if [ -n $2 ]; then
                                if [ -e "~/.GPTerminal/History/$2" ]; then
                                        CONTEXT_FILE_PATH="~/.GPTerminal/History/$2"
                                else
                                        echo "Chat $2 does not exist"
                                        exit 1
                                fi
                        else
                                echo "Invalid chat name: $2"
                                exit 1
                        fi
                        shift
                        shift
                        ;;
                --history ) # takes in chatname parameter
                        if [ -n "~/.GPTerminal/History/$2" ]; then
                                less "~/.GPTerminal/History/$2"
                                exit 1
                        else
                                echo "No such chat exists"
                        fi
                        ;;
                -q | --question ) # ask question and exit. context/history will not be saved
                        ask_question "$2"
                        exit 1
                        ;;
                * )
                        echo "Invalid option: $1"
                        exit 1
                        ;;
        esac
done

echo "User init prompt: $USER_INIT_PROMPT"
echo "Model: $MODEL"
echo "Temperature: $TEMPERATURE"

init_context_file

# type exit to exit
while true; do
        read -p "Ask a question: " question
        if [ "$question" = "exit" ]; then
                break
        fi

        ask_question "$question"
done