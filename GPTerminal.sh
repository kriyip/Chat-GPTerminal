#!/bin/bash

# 1 for context, 0 for no context
HAS_CONTEXT=1

CONTEXT_FILE_PATH=""
MODEL="gpt-3.5-turbo"

# 1 for verbose, 0 for not verbose
# VERBOSE=0
TEMPERATURE="0.7"

CURRENT_QUESTION_INDEX=0

MAX_TOKENS=1024
MAX_CONTEXT_TOKENS=$((MAX_TOKENS - 244)) # leave 244 tokens for prompt (780 for context). will change this to be user adjustable. note that higher token allowances for the current question will decrease the capacity of the context.

# set default model parameters
SYSTEM_PROMPT_MODE="default (general purpose)"
SYSTEM_INIT_PROMPT="You are ChatGPT, a large language model by OpenAI. Be as concise as possible. The shorter the better. If you are generating a list, keep the number of items small. Output your answer directly, with no labels in front. Do not start your answers with A or Answer."

WRITE_CODE_INIT_PROMPT="You are a helpful Linux terminal expert. You are given command descriptions and returning functioning shell commands. Return only the output of the command directly, with no other content and not in a code block. Be as concise as possible. The shorter the better."
EXPLAIN_CODE_INIT_PROMPT="You are a helpful Linux terminal expert. You are given shell commands and explaining the command. Be as concise as possible. The shorter the better."


# color and style codes
GREEN=`tput setaf 10`
BLUE=`tput setaf 12`
RED=`tput setaf 9`
GRAY=`tput setaf 8`
BOLD=$(tput bold)
UL=$(tput smul)
NC=`tput sgr0`


# returns the number of questions in the context file. Stores the result in CURRENT_QUESTION_INDEX.
# Arguments: $1 is the context file path
function get_questions_count {
        CURRENT_QUESTION_INDEX=$(sed -nE 's/^-------------------QUESTION ([0-9]+):.*---------------------$/\1/p' $1 | tail -n 1)
        if [ -z "$1" ]; then
                CURRENT_QUESTION_INDEX=0
        fi
}


# preprocesses a string by replacing newlines with spaces and escaping double quotes
# also escapes all control characters from U+0000 through U+001F (unprintable characters)
# Arguments: $1 is the string to be preprocessed
function preprocess {
        preprocessed_text=$(echo "$1" | tr '\n' ' ' | tr -d '\r' | sed -e 's/"/\\"/g')
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
        if [ -z "$chat_request" ]; then
                chat_request="{\"role\": \"user\", \"content\": \"$1\"}"
        else
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
# ERROR CODES:
#   1: the chat request is not valid json (usually api key is invalid)
#   2: the chat request is too long
#   3: the chat request has a parse error (edge cases with escape characters)
#######################################
function update_chat_request_with_response {
        
        # add response to chat message
        chat_request="$chat_request, {\"role\": \"assistant\", \"content\": \"$1\"}"

        # transform to json array to parse with jq
	request_json_array="[ $chat_request ]"


        num_tokens=$(echo "$chat_request" | wc -c)
        num_tokens=$(echo "$num_tokens * 1.3" | bc)
        exceeds_max=$(echo "$num_tokens > $MAX_CONTEXT_TOKENS" | bc)

        # check for parse error
        echo "$request_json_array" | jq -c '.[2:]' | jq -s . | jq -c '.[0]' >/dev/null
        if [ $? -ne 0 ]; then
                echo "$?"
                exit 3
        fi

        # if the number of tokens exceeds the max, remove the first question/answer pair until it doesn't
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
                }' 2>&1)
        
        # check if response is an error. if yes, print to stderr and exit
        if echo "$response" | jq -e '.error?' >/dev/null; then
                error_type=$(echo "$response" | jq -r '.error.code')
                echo -e "${RED}${BOLD}Your request to the OpenAI API failed. Reason: ${NC}" >&2
                case $error_type in
                        "invalid_api_key" )
                                echo -e "${RED} Invalid API key. Please check your API key and try again.${NC}" >&2
                        ;;
                        * )
                                error_reason=$(echo "$response" | jq -r '.error.message')
                                echo -e "${RED}$error_reason${NC}" >&2
                        ;;
                esac
		exit 2
	fi

        # extract response text from json
        extracted_response=$(echo "$response" | jq -r '.choices[0].message.content | @text')

        # if response is null, there is likely some sort of token length error
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
        echo -e "${RED}Error: Please set your OpenAI API key as the environment variable ${BOLD}OPENAI_API_KEY${NC} ${RED}by running:\n ${BOLD}export OPENAI_API_KEY=YOUR_API_KEY${NC}" >&2
        echo -e "${RED}You can create an API key at https://beta.openai.com/account/api-keys${NC}" >&2
        exit 1
fi


# parse flags/parameters for the script
while [[ $# -gt 0 ]]; do
        case $1 in
                -i | --init-chat-prompt ) # check if i is followed by empty. if yes, then print the pre-defined init prompts and exit
                        if [ "$2" = "linux-write" ]; then
                                SYSTEM_INIT_PROMPT="$WRITE_CODE_INIT_PROMPT"
                                SYSTEM_PROMPT_MODE="write (create linux terminal commands)"
                        elif [ "$2" = "linux-explain" ]; then
                                SYSTEM_INIT_PROMPT="$EXPLAIN_CODE_INIT_PROMPT"
                                SYSTEM_PROMPT_MODE="explain (explain linux terminal commands)"
                        # check if $2 is empty
                        elif [ -z "$2" ]; then
                                echo -e "${BLUE}Available pre-defined init prompts:\n linux-write\n linux-explain${NC}"
                                exit 0
                        else
                                SYSTEM_INIT_PROMPT="$2"
                                SYSTEM_PROMPT_MODE="custom ($2)"
                                SYSTEM_INIT_PROMPT="$SYSTEM_INIT_PROMPT Be concise."
                        fi
                        shift
                        shift
                        ;;
                -t | --temperature )
                        if (( $(echo "$2 > 0" | bc -l) )) && (( $(echo "$2 < 1" | bc -l) )); then
                                TEMPERATURE="$2"
                        else
                                echo -e "${RED}Invalid temperature: $2\nTemperature must be between 0 and 1${NC}"
                                exit 1
                        fi
                        shift
                        shift
                        ;;
                -n | --name-new-chat )
                        if [ -n "$2" ]; then
                                if [[ "$2" =~ " " ]]; then
                                        echo "${RED}Chat names cannot contain spaces.${NC}"
                                        exit 1
                                elif [ -e ".GPTerminal/History/$2" ]; then
                                        echo "${RED}Chat \"$2\" already exists. Please enter another name.${NC}"
                                        exit 1
                                fi
                                CONTEXT_FILE_PATH=".GPTerminal/History/$2"
                        else
                                echo "${RED}Chat name cannot be the empty string${NC}"
                                exit 1
                        fi
                        shift
                        shift
                        ;;
                -h | --history ) # takes in chatname parameter, prints chat history
                        if [ -z "$2" ]; then # check if input is empty
                                num_chats=$(ls -1 ".GPTerminal/History" | wc -l)
                                echo "${BLUE}Listing all ${num_chats#"${num_chats%%[![:space:]]*}"} chat(s):${NC}"
                                ls ".GPTerminal/History"
                                exit 1
                        elif [ -e ".GPTerminal/History/$2" ]; then
                                get_questions_count ".GPTerminal/History/$2"
                                echo "${BLUE}Opening chat \"$2\" containing $CURRENT_QUESTION_INDEX questions...${NC}"
                                less ".GPTerminal/History/$2"
                                exit 1
                        else
                                echo "${RED}No such chat \"$2\" exists${NC}"
                                exit 1
                        fi
                        shift
                        shift
                        ;;
                -q | --question ) # ask question and exit. context/history will not be saved
                        echo -e "${GREEN}User:${NC} $2"
                        ask_question "$2"
                        echo -e "${BLUE}Chat:${NC} $extracted_response\n"
                        exit 1
                        ;;
                * )
                        echo "${RED}Invalid option: $1${NC}"
                        exit 1
                        ;;
        esac
done


init_context_file


context_file_name=$(basename "$CONTEXT_FILE_PATH")

# print initialization params
echo "---------------INITIALIZATION PARAMS---------------"
echo "Initialization: $SYSTEM_PROMPT_MODE"
echo "Model: $MODEL"
echo "Temperature: $TEMPERATURE"
echo "Chat Name: $context_file_name"
echo -e "---------------------------------------------------\n"


while true; do
        read -p "${GREEN}User:${NC} " -e input
        if [ "$input" == "exit" ] || [ "$input" == "q" ]; then
                echo "${GRAY}Shutting down...${NC}"
                exit 0
        elif [ "$input" == "--force-context-reset" ]; then
                echo "${GRAY}Resetting chat context...${NC}"
                chat_request=""
        elif [ "$input" == "--history" ]; then
                get_questions_count "$CONTEXT_FILE_PATH"
                echo "${BLUE}Opening chat \"$CONTEXT_FILE_PATH\" containing $CURRENT_QUESTION_INDEX questions...${NC}"
                less "$CONTEXT_FILE_PATH"
        elif [ "$input" == "--help" ]; then
                echo -e "${BLUE}Available commands:\n exit\n q\n --force-context-reset\n --history\n --help${NC}"
        else
                # preprocess the user's question
                preprocess "$input"
                preprocessed_question="$preprocessed_text"
                
                # ask the question, raw json is stored in $response, processed in $extracted_response
                ask_question "$preprocessed_question"
                err_code=$?

                if [ "$err_code" = 1 ]; then
                        echo -e "${RED}Error: Null response from OpenAI API. Please try again. You may want to try using a smaller input. You may also want to try resetting the chat context (by creating a new chat or typing --force-context-reset)${NC}">&2
                elif [ "$err_code" = 2 ]; then
                        exit 1
                elif [ "$err_code" = 3 ]; then
                        echo -e "${GRAY}Error: A parse error has occurred within the script. Please report this issue. This will hopefully be fixed in the near future.${NC}">&2
                        exit 1
                else
                        # write response to the history file
                        write_to_context_file "$preprocessed_question" "$extracted_response" "$CURRENT_QUESTION_INDEX"

                        CURRENT_QUESTION_INDEX=$((CURRENT_QUESTION_INDEX + 1))

                        echo -e "${BLUE}Chat:${NC} $extracted_response\n"
                fi
        fi
done
