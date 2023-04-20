#!/bin/bash

# 1 for context, 0 for no context
HAS_CONTEXT=1

CONTEXT_FILE_PATH=""
MODEL="gpt-3.5-turbo"

# 1 for verbose, 0 for not verbose
VERBOSE=0
TEMPERATURE="0.7"

CURRENT_QUESTION_INDEX=0

MAX_TOKENS=1024
MAX_CONTEXT_TOKENS=$(($MAX_TOKENS - 100))

# set default model parameters
DEFAULT_INIT_PROMPT="You are a continuing a conversation where you answer questions from a user. Answer future questions as concisely as possible. A list of the $CURRENT_QUESTION_INDEX previous questions and answers are provided in the form of 'Q:...\nA:...'. Answer the last question."
WRITE_CODE_INIT_PROMPT="You are translating written prompts into code. Answer as concisely as possible."
EXPLAIN_CODE_INIT_PROMPT="You are summarizing a code snippet in natural language."

# set default init prompt
USER_INIT_PROMPT=$DEFAULT_INIT_PROMPT


function init_context_file {
        # check if context file exists
        if [ ! -d ".GPTerminal" ]; then
                # echo "Creating context folder..."
                mkdir ".GPTerminal"
                mkdir ".GPTerminal/History"
        fi
        if [ -z "$CONTEXT_FILE_PATH" ]; then
                # echo "Context file doesn't exists"
                timestamp=$(date +"%Y-%m-%d_%H:%M:%S")
                CONTEXT_FILE_PATH=".GPTerminal/History/$timestamp"
                # echo "$CONTEXT_FILE_PATH"
        fi
        touch "$CONTEXT_FILE_PATH"
        chmod 700 "$CONTEXT_FILE_PATH"
}

# DELETE THIS FUNCTION
# called before each ask_question request
function get_context_basic {
        # get context from context file
        context=$(cat "$CONTEXT_FILE_PATH")
        # may need to grep based on certain keywords? or is there some way I could summarize a text file?
        # first, will just make it work with basic context file and then try to make longer conversations last.
        # will drop the previous context files
        # echo "get context: $context"
}

function get_context_summarize {
        echo "in summarize"
}

function init_chat_context {
        if [ -z "$context" ]; then
                echo "Context is empty"
                echo -e "----INITIALIZATION PROMPT----\n" >> "$CONTEXT_FILE_PATH"
                ask_question "$USER_INIT_PROMPT"
                echo -e "----END INITIALIZATION PROMPT----\n" >> "$CONTEXT_FILE_PATH"
                context="$USER_INIT_PROMPT"
        fi
        # get context from context file, and replace newlines with \n
        context=$(cat "$CONTEXT_FILE_PATH")
        context=$(echo "$context" | sed -e 's/"/\\"/g')
}

# build_chat_context() {
#         chat_context="$1"
# 	escaped_prompt="$2"
# 	if [ -z "$chat_context" ]; then
# 		chat_context="$CHAT_INIT_PROMPT\nQ: $escaped_prompt"
# 	else
# 		chat_context="$chat_context\nQ: $escaped_prompt"
# 	fi
# 	request_prompt="${chat_context//$'\n'/\\n}"
# }

# chat history filenames are be of the form .GPTerminal/History/<timestamp> or <user-defined>
# stores Q: <user prompt> and A: <chat response> in the chat history file
# $1 is the user prompt/question, $2 is the chat response, $3 current question number
function write_to_chat_context {
        echo -e "-------------------QUESTION $3---------------------" >> "$CONTEXT_FILE_PATH"
        echo "context file path: $CONTEXT_FILE_PATH"
        echo -e "\nUser: $1\n" >> "$CONTEXT_FILE_PATH"
        echo -e "Response: $2\n" >> "$CONTEXT_FILE_PATH"
}

function get_token_count {
        char_count=$(echo "$context" | wc -c)
        approx_token_count=$(echo "scale=0; $char_count * 0.75" | bc)
        echo "approx token count: $approx_token_count"
}

# keeps the size of the context to a maximum of MAX_TOKENS-100 tokens (100 left over for current prompt)
# $1 is chat context, $2 is processed question, $3 is processed response
function update_chat_context {
        context="$1\nQ: $2\nA: $3"
        # check context length 
        # approximately 1 token = 4 characters or ~.75 words (100 tokens = 75 words)
        echo "Q: $2"
        echo "A: $3"
        echo "new context: $context"
        get_token_count

        while [ $(echo "$approx_token_count > 184" | bc) -eq 1 ]; do
                echo "loop"
                # remove first/oldest QnA from prompt
                echo "$context" | sed -n '1,/A:/!p'
                context=$(echo "$context" | sed -n '1,/A:/d')
                # add back initialization prompt
                context="$USER_INIT_PROMPT\n$context"
                echo "$context"
                get_token_count
        done
}

# context="$USER_INIT_PROMPT\nQ: Give me a name\nA: Bob"
# update_chat_context "$context" "What is your name?" "My name is GPTerminal"

# use curl to send question data to OpenAI server and get the response
# use json import in python to parse the response and get the answer (because it keeps new line characters)
function ask_question {
        echo "PROMPT PARAMETER: $1"
        
        response=$(curl https://api.openai.com/v1/chat/completions \
                -H 'Content-Type: application/json' \
                -H "Authorization: Bearer $OPENAI_API_KEY" \
                -d '{
                "model": "'"$MODEL"'",
                "messages": [{"role": "user", "content": "'"$1"'"}],
                "temperature": '"$TEMPERATURE"'
                }')

        processed_response=$(echo "$response" | jq -r '.choices[0].message.content | @text')
        # processed_response=$(echo "$response" | python -c "import sys, json; print(json.load(sys.stdin)['choices'][0]['message']['content'])")
        echo "response: $processed_response"
        write_to_chat_context "$1" "$processed_response" "$CURRENT_QUESTION_INDEX"
}


# check if OpenAI API key is set as environment variable
if [[ -z "$OPENAI_API_KEY" ]]; then
        echo "Please set your OpenAI API key as the environment variable OPENAI_API_KEY by running:"
        echo "export OPENAI_API_KEY=YOUR_API_KEY"
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
                        if [ -n "$2" ]; then
                                if [ -e ".GPTerminal/History/$2" ]; then
                                        CONTEXT_FILE_PATH=".GPTerminal/History/$2"
                                else
                                        echo "Chat $2 does not exist"
                                        exit 1
                                fi
                        else
                                echo "Chat name cannot be the empty string"
                                exit 1
                        fi
                        shift
                        shift
                        ;;
                -n | --name-new-chat )
                        if [ -n "$2" ]; then
                                if [ -e ".GPTerminal/History/$2" ]; then
                                        echo "Chat $2 already exists"
                                        exit 1
                                fi
                                CONTEXT_FILE_PATH=".GPTerminal/History/$2"
                        else
                                echo "Chat name cannot be the empty string"
                                exit 1
                        fi
                        ;;
                --history ) # takes in chatname parameter, prints chat history
                        if [ -n ".GPTerminal/History/$2" ]; then
                                less ".GPTerminal/History/$2"
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
context=$(cat "$CONTEXT_FILE_PATH")

# context=""
# if [ $HAS_CONTEXT -eq 1 ]; then
#         context=$(get_context_basic)
# elif [ $HAS_CONTEXT -eq 2 ]; then
#         context=$(get_context_summarize)
# fi

# check if chat context is empty (i.e. it does not contain an init prompt)
# if yes, then add the init prompt to the context as question 0
echo "context: $context"

if [ -z "$context" ]; then
        echo "Context is empty"
        echo -e "----INITIALIZATION PROMPT----\n" >> "$CONTEXT_FILE_PATH"
        ask_question "$USER_INIT_PROMPT"
        echo -e "----END INITIALIZATION PROMPT----\n" >> "$CONTEXT_FILE_PATH"
fi

# get the last question number in the file
echo $CURRENT_QUESTION_INDEX
CURRENT_QUESTION_INDEX=$(sed -nE 's/^-------------------QUESTION ([0-9]+)---------------------$/\1/p' $CONTEXT_FILE_PATH | tail -n 1)

echo "$CONTEXT_FILE_PATH"
cat "$CONTEXT_FILE_PATH"
echo "last question: $CURRENT_QUESTION_INDEX"

# type exit to exit
while true; do
        read -p "Ask a question: " -e input
        if [ "$input" == "exit" ] || [ "$input" == "q" ]; then
                echo "Shutting down..."
                exit 0
        fi
        ask_question "$question"
done
