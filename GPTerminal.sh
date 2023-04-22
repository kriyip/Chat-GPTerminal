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
MAX_CONTEXT_TOKENS=$((MAX_TOKENS - 244)) # leave 244 tokens for prompt (780 for context). let this be user adjustable. note that higher token allowances for the current question will decrease the capacity of the context.

# set default model parameters
SYSTEM_INIT_PROMPT="You are ChatGPT, a large language model trained by OpenAI. Answer as concisely as possible. Current date: $(date +%d/%m/%Y). Knowledge cutoff: 9/1/2021."
SYSTEM_INIT_PROMPT="You are ChatGPT, a large language model trained by OpenAI. You will be answering questions from users.  You answer as concisely as possible for each response (don’t be verbose). If you are generating a list, keep the number of items short. Before each user prompt you will be given the chat history in Q&A form. Output your answer directly, with no labels in front. Do not start your answers with A or Answer. Knowledge cutoff: 9/1/2021."

DEFAULT_INIT_PROMPT="You are ChatGPT, a Large Language Model trained by OpenAI. You will be answering questions from users. You answer as concisely as possible for each response (e.g. don’t be verbose). If you are generating a list, do not have too many items. Keep the number of items short. Before each user prompt you will be given the chat history in Q&A form. Output your answer directly, with no labels in front. Do not start your answers with A or Answer. You were trained on data up until 2021. Today's date is $(date +%d/%m/%Y)"
DEFAULT_INIT_PROMPT="hello how are you"
WRITE_CODE_INIT_PROMPT="You are translating written prompts into code. Answer as concisely as possible."
EXPLAIN_CODE_INIT_PROMPT="You are summarizing a code snippet in natural language."

# set default init prompt"
USER_INIT_PROMPT="$DEFAULT_INIT_PROMPT"


# color and style codes
GREEN=`tput setaf 10`
BLUE=`tput setaf 12`
RED=`tput setaf 9`
GRAY=`tput setaf 8`
BOLD=$(tput bold)
UL=$(tput smul)
NC=`tput sgr0`


# returns the number of questions in the context file. Stores the result in CURRENT_QUESTION_INDEX.
function get_questions_count {
        CURRENT_QUESTION_INDEX=$(sed -nE 's/^-------------------QUESTION ([0-9]+):.*---------------------$/\1/p' $CONTEXT_FILE_PATH | tail -n 1)
        if [ -z "$CURRENT_QUESTION_INDEX" ]; then
                CURRENT_QUESTION_INDEX=0
        fi
}

#######################################
# returns the approximate token count of its input
# approximately 1 token = 4 characters or ~.75 words (100 tokens = 75 words)
# ARGUMENTS:
#   $1: the input string
# OUTPUTS:
#   The approximate token count in approx_token_count
#######################################
function get_token_count {
        char_count=$(echo "$1" | wc -c)
        approx_token_count=$(echo "scale=0; $char_count * 0.75" | bc)
        echo "approx token count: $approx_token_count"
}


# preprocesses a string by replacing newlines with spaces and escaping double quotes
# also escapes all control characters from U+0000 through U+001F (unprintable characters)
# Arguments: $1 is the string to be preprocessed
function preprocess {
        preprocessed_text=$(echo "$1" | tr '\n' ' ' | tr -d '\r' | sed -e 's/"/\\"/g')
}


#######################################
# This function initializes the context file and adds the initialization prompt. The context file stores the chat history in Q&A form.
# Chat history filenames are be of the form .GPTerminal/History/<timestamp> or <user-defined>
# GLOBAL VARIABLES:
#   CONTEXT_FILE_PATH: the path to the context file
# OUTPUTS:
#   None
#######################################
function init_context_file {
        # create contents directory if it doesn't exist
        if [ ! -d ".GPTerminal" ]; then
                mkdir ".GPTerminal"
                mkdir ".GPTerminal/History"
        fi
        # if context name is not user-defined, use timestamp
        if [ -z "$CONTEXT_FILE_PATH" ]; then 
                timestamp=$(date +"%Y-%m-%d_%H:%M:%S")
                CONTEXT_FILE_PATH=".GPTerminal/History/$timestamp"
        fi
        touch "$CONTEXT_FILE_PATH"
        chmod 700 "$CONTEXT_FILE_PATH"

        echo -e "----INITIALIZATION PROMPT----" >> "$CONTEXT_FILE_PATH"
        ask_question "$USER_INIT_PROMPT"
        write_to_context_file "$USER_INIT_PROMPT" "$processed_response" "$CURRENT_QUESTION_INDEX"
        echo -e "----END INITIALIZATION PROMPT----" >> "$CONTEXT_FILE_PATH"

}


#######################################
# Write a question and answer to the context file
# ARGUMENTS:
#   $1: the user's question (without preprocessing)
#   $2: the chat's answer (without preprocessing)
#   $3: the current question number
# OUTPUTS:
#   None
#######################################
function write_to_context_file {
        timestamp=$(date +"%Y-%m-%d_%H:%M:%S")
        echo -e "-------------------QUESTION $3: $timestamp---------------------" >> "$CONTEXT_FILE_PATH"
        echo -e "Q: $1" >> "$CONTEXT_FILE_PATH"
        echo -e "A: $2" >> "$CONTEXT_FILE_PATH"
        echo -e "-------------------END OF QUESTION $3---------------------" >> "$CONTEXT_FILE_PATH"
}


#######################################
# This function creates the chat request json to be sent
# ARGUMENTS:
#   $1: the processed question string
# OUTPUTS:
#   The chat request json in chat_request
#######################################
function make_request_json_array {
        if [ -z "$chat_request" ]; then # initialize chat request if it doesn't exist
                chat_request="{\"role\": \"user\", \"content\": \"$1\"}"
        else # append new question to chat message
                chat_request="$chat_request, {\"role\": \"user\", \"content\": \"$1\"}"
        fi
}

#######################################
# This function updates the chat request with a response and maintains the
# context size to be within MAX_CONTEXT_TOKENS
# Approximately 1 token = 4 characters or ~.75 words (100 tokens = 75 words).
# This translates to ~1.3 tokens per word
# ARGUMENTS:
#   $1: the processed response string
# OUTPUTS:
#   The chat request json in chat_request
#######################################
function update_chat_request_with_response {
        
        # add response to chat message
        chat_request="$chat_request, {\"role\": \"assistant\", \"content\": \"$1\"}"

        # transform to json array to parse with jq
	request_json_array="[ $chat_request ]"


        num_tokens=$(echo "$chat_request" | wc -c)
        num_tokens=$(echo "$num_tokens * 1.3" | bc)
        exceeds_max=$(echo "$num_tokens > $MAX_CONTEXT_TOKENS" | bc)

        while [ $exceeds_max = 1 ]; do
                # remove the first question/answer pair
                new_json_array=$(echo "$request_json_array" | jq -c '.[2:]' | jq -s . | jq -c '.[0]')

                # assign the new_json_array to request_json_array
                request_json_array="$new_json_array"

                # convert array string to json string. Assign this to chat_request
                chat_request=$(echo "$new_json_array" | awk '{print substr($0, 2, length($0) - 2)}')
                
                # get updated token count
                num_tokens=$(echo "$chat_request" | wc -c)
                num_tokens=$(echo "$num_tokens * 1.3" | bc)

                exceeds_max=$(echo "$num_tokens > $MAX_CONTEXT_TOKENS" | bc)
        done

}


#######################################
# Sends the chat request to the OpenAI API and gets the response
# This function updates the chat request to contain the new question, response pair
# ARGUMENTS:
#   $1: the preprocessed question string
# OUTPUTS:
#   the chatbot response in extracted_response
#   the processed response in processed_response
#   returns 1 if an error occurred, 0 otherwise
#######################################
function ask_question {
        prompt="$1" # this is preprocessed question
        make_request_json_array "$prompt"

        echo -e "${GRAY}Sending request...${NC}"
        
        response=$(curl https://api.openai.com/v1/chat/completions \
                -s -S \
                -H 'Content-Type: application/json' \
                -H "Authorization: Bearer $OPENAI_API_KEY" \
                -d '{
                "model": "'"$MODEL"'",
                "messages": [{"role": "system", "content": "'"$SYSTEM_INIT_PROMPT"'"}, '"$chat_request"'],
                "temperature": '"$TEMPERATURE"',
                "max_tokens": '"$MAX_TOKENS"'
                }')

        extracted_response=$(echo "$response" | jq -r '.choices[0].message.content | @text')

        # if response is null, throw error
        if [ -z "$extracted_response" ]; then
                exit 1
        fi

        # preprocess response
        preprocess "$extracted_response"
        processed_response="$preprocessed_text"
                
        # remove new lines from response. replace with space
        processed_response=$(echo "$processed_response" | sed -e 's/\\n/ /g')

        update_chat_request_with_response "$processed_response"

}


# check if OpenAI API key is set as environment variable
if [[ -z "$OPENAI_API_KEY" ]]; then
        echo -e "${RED}Error: Please set your OpenAI API key as the environment variable ${BOLD}OPENAI_API_KEY${NC} ${RED}by running:\n ${BOLD}export OPENAI_API_KEY=YOUR_API_KEY${NC}"
        echo -e "${RED}You can create an API key at https://beta.openai.com/account/api-keys${NC}"
        exit 1
fi


# parse flags/parameters for the script
while [[ $# -gt 0 ]]; do
        case $1 in
                -i | --init-chat-prompt ) # check if i is followed by empty. if yes, then print the pre-defined init prompts and exit
                        if [ "$2" = "write-code" ]; then
                                USER_INIT_PROMPT="$WRITE_CODE_INIT_PROMPT"
                        elif [ "$2" = "explain-code" ]; then
                                USER_INIT_PROMPT="$EXPLAIN_CODE_INIT_PROMPT"
                        elif [ "$2" = "command-line-helper" ]; then # also have a way to execute the command
                                USER_INIT_PROMPT="you are a command line helper"
                        else
                                echo "Invalid init prompt: $2"
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
                        shift
                        shift
                        ;;
                -h | --history ) # takes in chatname parameter, prints chat history
                        if [ -z "$2" ]; then # check if input is empty
                                num_chats=$(ls -1 ".GPTerminal/History" | wc -l)
                                echo "Listing all ${num_chats#"${num_chats%%[![:space:]]*}"} chat(s):"
                                ls ".GPTerminal/History"
                                exit 1
                        elif [ -n ".GPTerminal/History/$2" ]; then
                                less ".GPTerminal/History/$2"
                                exit 1
                        else
                                echo "No such chat $2 exists"
                        fi
                        shift
                        shift
                        ;;
                -q | --question ) # ask question and exit. context/history will not be saved
                        ask_question "$2"
                        echo -e "\n${BLUE}response:${NC} $extracted_response\n"
                        exit 1
                        ;;
                * )
                        echo "Invalid option: $1"
                        exit 1
                        ;;
        esac
done

# make context file if it does not exist
init_context_file

CURRENT_QUESTION_INDEX=$((CURRENT_QUESTION_INDEX+1))

# print initialization params
echo "---------------INITIALIZATION PARAMS---------------"
echo "Initialization: $USER_INIT_PROMPT (default: general questions)"
echo "Model: $MODEL"
echo "Temperature: $TEMPERATURE"
echo "Chat Name: $CONTEXT_FILE_PATH"
echo -e "---------------------------------------------------\n"

# loop to ask questions until user exits
while true; do
        read -p "${GREEN}User:${NC} " -e input
        if [ "$input" == "exit" ] || [ "$input" == "q" ]; then
                echo "${GRAY}Shutting down...${NC}"
                exit 0
        else
                # preprocess the user's question
                preprocess "$input"
                preprocessed_question="$preprocessed_text"
                
                # ask the question, raw json is stored in $response, processed in $extracted_response
                ask_question "$preprocessed_question"
                err_code=$?

                if [ "$err_code" = 1 ]; then
                        echo -e "${RED}Error: No response from OpenAI API. Please try again. You may want to try using a smaller input. You may also want to try resetting the chat context (by creating a new chat or typing --force-context-reset)${NC}"
                else
                        # write response to the history file
                        write_to_context_file "$preprocessed_question" "$extracted_response" "$CURRENT_QUESTION_INDEX"

                        CURRENT_QUESTION_INDEX=$((CURRENT_QUESTION_INDEX + 1))

                        echo -e "${BLUE}Chat:${NC} $extracted_response\n"
                fi
        fi
done
