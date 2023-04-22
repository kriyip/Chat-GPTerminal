#!/bin/bash

# 1 for context, 0 for no context
HAS_CONTEXT=1

CONTEXT_FILE_PATH=""
MODEL="gpt-3.5-turbo"

# 1 for verbose, 0 for not verbose
VERBOSE=0
TEMPERATURE="0.7"

CONTEXT_HEAD_QUESTION_INDEX=1
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

### CONTEXT FUNCTIONS ###

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

# returns the number of questions in the context file. Stores the result in CURRENT_QUESTION_INDEX.
function get_questions_count {
        CURRENT_QUESTION_INDEX=$(sed -nE 's/^-------------------QUESTION ([0-9]+):.*---------------------$/\1/p' $CONTEXT_FILE_PATH | tail -n 1)
        if [ -z "$CURRENT_QUESTION_INDEX" ]; then
                CURRENT_QUESTION_INDEX=0
        fi
}

# preprocesses a string by replacing newlines with spaces and escaping double quotes
# also escapes all control characters from U+0000 through U+001F (unprintable characters)
# Arguments: $1 is the string to be preprocessed
function preprocess {
        # escaped_string=$(printf '%q' "$1")
        # preprocessed_text=$(echo "$1" | sed -e 's/"/\\"/g' | sed -e 's/\n/ /g')
        preprocessed_text=$(echo "$1" | tr '\n' ' ' | tr -d '\r' | sed -e 's/"/\\"/g')
}

# initializes the context file if it doesn't exist
function init_context_file {
        # check if context file exists
        if [ ! -d ".GPTerminal" ]; then
                mkdir ".GPTerminal"
                mkdir ".GPTerminal/History"
        fi
        if [ -z "$CONTEXT_FILE_PATH" ]; then
                timestamp=$(date +"%Y-%m-%d_%H:%M:%S")
                CONTEXT_FILE_PATH=".GPTerminal/History/$timestamp"
        fi
        touch "$CONTEXT_FILE_PATH"
        chmod 700 "$CONTEXT_FILE_PATH"
}

# this is a mess
# need to check that this function works correctly
# TODO: streamline the format of the context file (in both init_chat_context and write_to_context_file) - done
# function init_chat_context {
#         # check if context file is empty
#         if [ -s "$CONTEXT_FILE_PATH" ]; then
#                 echo "Context is empty"
#                 # ask_question "$USER_INIT_PROMPT"
#                 echo -e "Initialization Prompt: $USER_INIT_PROMPT" >> "$CONTEXT_FILE_PATH"
#                 context="$USER_INIT_PROMPT"
#         else 
#                 # we are continuing from a previous context
#                 # first get the initialization prompt and preprocess it
#                 USER_INIT_PROMPT=$(cat "$CONTEXT_FILE_PATH" | head -n 1 | sed 's/Initialization Prompt: (.*)/\1/')
#                 preprocess "$USER_INIT_PROMPT"
#                 preprocessed_USER_INIT_PROMPT="$preprocessed_text"

#                 # starting from last question, add to context until we exceed MAX_CONTEXT_TOKENS
#                 context="$preprocessed_USER_INIT_PROMPT\n$context"
#                 get_token_count
#                 init_prompt_token_count=$approx_token_count
                
#                 # total num questions in CURRENT_QUESTION_INDEX
#                 curr_question=$(get_questions_count)
#                 context=""

#                 while [ $(echo "$approx_token_count < $MAX_CONTEXT_TOKENS - $init_prompt_token_count)" | bc) -eq 1 ] && [ $curr_question -gt 0]; do
#                         echo "---loop---"

#                         # get the curr_question-th question and answer
#                         curr_text=$(sed -n "/-------------------QUESTION $curr_question---------------------/,/-------------------END OF QUESTION $((curr_question+1))---------------------/p" $CONTEXT_FILE_PATH | tail -n +2 | head -n -1)
#                         context="$curr_text\n$context"

#                         echo "$context"
#                         get_token_count
#                 done

#                 # add back the initialization prompt
#                 context="$preprocessed_USER_INIT_PROMPT\n$context"
                
#         fi
#         # get context from context file, and replace newlines with \n
#         context=$(cat "$CONTEXT_FILE_PATH" | tail -n +5)
#         context=$(echo "$context" | sed -e 's/"/\\"/g')
# }

# chat history filenames are be of the form .GPTerminal/History/<timestamp> or <user-defined>

# Add the new question and answer to the context file
# Arguments: $1 is the user's question, $2 is the chat's answer, $3 current question number
function write_to_context_file {
        timestamp=$(date +"%Y-%m-%d_%H:%M:%S")
        echo -e "-------------------QUESTION $3: $timestamp---------------------" >> "$CONTEXT_FILE_PATH"
        echo -e "Q: $1" >> "$CONTEXT_FILE_PATH"
        echo -e "A: $2" >> "$CONTEXT_FILE_PATH"
        echo -e "-------------------END OF QUESTION $3---------------------" >> "$CONTEXT_FILE_PATH"
}

# usage: this function is called AFTER a call to ask_question. It adds the new question and response to the current context
# adds a new question and response to the chat context
# keeps the size of the context to a maximum of MAX_TOKENS-100 tokens (100 left over for current prompt)
#######################################
# USAGE: this function is called AFTER a call to ask_question. It adds the new question and response to the current context
# adds a new question and response to the chat context
# keeps the size of the context to a maximum of MAX_TOKENS-100 tokens (100 left over for current prompt)
# approximately 1 token = 4 characters or ~.75 words (100 tokens = 75 words)
# ARGUMENTS:
#   $1: the processed question string
#   $2: the processed response string
# OUTPUTS:
#   The approximate token count in approx_token_count
#######################################
# function update_chat_context {

#         # add new QnA to context
#         context="$context\nQ: $1\nA: $2"
#         echo "context: $context"

#         # check context length 
#         # approximately 1 token = 4 characters or ~.75 words (100 tokens = 75 words)
#         get_token_count

#         exceeds_max=$(echo "$approx_token_count > $MAX_CONTEXT_TOKENS" | bc)
#         # echo "exceeds_max: $exceeds_max"

#         #  TODO: DEBUG THIS FUNCTION SO THAT IT REMOVES ONLY THE FIRST QUESTION.
#         #  CURRENTLY REMOVES EVERYTHING EXCEPT THE LAST QUESTION
#         while [ $exceeds_max = 1 ]; do
#                 echo "-----LOOOP-----"
#                 # remove first/oldest QnA from prompt
#                 echo "TESTTT"
#                 echo "$context" | sed -n '/Q:/,$p' | tail -n +2

#                 # REMOVES EVERYTHING EXCEPT FOR THE LAST QUESTION
#                 cc=$(echo "$context" | sed 's/^.*Q:/Q:/')
#                 echo "processed: $cc"
#                 context=$(echo "$context" | sed '1,/\\nA: /d')
#                 # add back initialization prompt
#                 context="$USER_INIT_PROMPT\n$context"
#                 echo "$context"
#                 get_token_count
#                 exceeds_max=$(echo "$approx_token_count > $MAX_CONTEXT_TOKENS" | bc)
#                 echo "exceeds_max = $exceeds_max"
#         done
# }

# TESTING LINES FOR update_chat_context
# context="$USER_INIT_PROMPT\nQ: Give me a name\nA: Bob\nQ: another name?\nA: Robob\nQ: Give me a third name\nA: coBob"
# update_chat_context "What is your name?" "My name is GPTerminal"

# $1 is the processed prompt
# result is stored in chat_request

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
                # echo "appending new question to chat request: $1"
                chat_request="$chat_request, {\"role\": \"user\", \"content\": \"$1\"}"
        fi
}

# $1 is the processed response
# update the chat request with previous response
#######################################
# This function adds the previous response to the chat request and keeps the size of
# context size within MAX_CONTEXT_TOKENS
# Approximately 1 token = 4 characters or ~.75 words (100 tokens = 75 words)
# ARGUMENTS:
#   $1: the processed response string
# OUTPUTS:
#   The chat request json in chat_request
#######################################
function update_chat_request_with_response {
        
        # add response to chat message
        chat_request="$chat_request, {\"role\": \"assistant\", \"content\": \"$1\"}"
        # echo "CHAT REQUEST IN UPDATE: $chat_request"

        # transform to json array to parse with jq
	request_json_array="[ $chat_request ]"

        # maintain the size of the context to a maximum of MAX_CONTEXT_TOKENS
	# check prompt length, 1 word =~ 1.3 tokens
	# reserving 100 tokens for next user prompt
        echo "INIT CHAT REQUEST: $chat_request"

        num_tokens=$(echo "$chat_request" | wc -c)
        num_tokens=$(echo "$num_tokens * 1.3" | bc)
        echo "INIT NUM OF TOKENS IN CHAT REQUEST: $num_tokens"
        exceeds_max=$(echo "$num_tokens > $MAX_CONTEXT_TOKENS" | bc)

        # get_token_count "$chat_request"
        # exceeds_max=$(echo "$approx_token_count > $MAX_CONTEXT_TOKENS" | bc)
        echo "exceeds_max: $exceeds_max"
        
        while [ $exceeds_max = 1 ]; do
                # remove first/oldest QnA from prompt
                echo "---LOOP---"
                echo "ORIGINAL JSON ARRAY: $request_json_array--------------"

                # chat_message=$(echo "$request_json_array" | jq -c '.[2:] | .[] | {role, content}')
                # echo "CHAT MESSAGE: $chat_message------------------"

                # remove the first question/answer pair
                new_json_array=$(echo "$request_json_array" | jq -c '.[2:]')
                new_json_array=$(echo "$new_json_array" | jq -s .)

                new_json_array=$(echo "$new_json_array" | jq -c '.[0]')

                # assign the new_json_array to request_json_array
                request_json_array="$new_json_array"

                
                # convert array string to json string. Assign this to chat_request
                chat_request=$(echo "$new_json_array" | awk '{print substr($0, 2, length($0) - 2)}')
                echo "NEW CHAT REQUEST: $chat_request================="
                
                # get updated token count
                num_tokens=$(echo "$chat_request" | wc -c)
                num_tokens=$(echo "$num_tokens * 1.3" | bc)
                echo "NUMBER OF TOKENS IN CHAT REQUEST: $num_tokens"

                exceeds_max=$(echo "$num_tokens > $MAX_CONTEXT_TOKENS" | bc)
                echo "exceeds_max: $exceeds_max"

        done

        # echo "FINAL NUMBER OF TOKENS IN CHAT REQUEST: $num_tokens"
        # echo "FINAL REQUEST: $chat_request"
}


# use curl to send question data to OpenAI server and get the response
# use json import in python to parse the response and get the answer (because it keeps new line characters)
#######################################
# Sends the chat request to the OpenAI API and gets the response
# This function updates the chat request to contain the new question, response pair
# ARGUMENTS:
#   $1: the preprocessed question string
# OUTPUTS:
#   the chatbot response in extracted_response
#   the processed response in processed_response
#######################################
function ask_question {
        prompt="$1" # this is preprocessed question
        make_request_json_array "$prompt"
        # echo "chat_request: $chat_request"
        
        response=$(curl https://api.openai.com/v1/chat/completions \
                -H 'Content-Type: application/json' \
                -H "Authorization: Bearer $OPENAI_API_KEY" \
                -d '{
                "model": "'"$MODEL"'",
                "messages": [{"role": "system", "content": "'"$SYSTEM_INIT_PROMPT"'"}, '"$chat_request"'],
                "temperature": '"$TEMPERATURE"',
                "max_tokens": '"$MAX_TOKENS"'
                }')

        extracted_response=$(echo "$response" | jq -r '.choices[0].message.content | @text')

        # preprocess response
        preprocess "$extracted_response"
        processed_response="$preprocessed_text"
                
        # remove new lines from response. replace with space
        processed_response=$(echo "$processed_response" | sed -e 's/\\n/ /g')
        # echo "processed_response: $processed_response"

        update_chat_request_with_response "$processed_response"
        echo "updated_chat_request: $chat_request"
}



# check if OpenAI API key is set as environment variable
if [[ -z "$OPENAI_API_KEY" ]]; then
        echo "Please set your OpenAI API key as the environment variable OPENAI_API_KEY by running:"
        echo "export OPENAI_API_KEY=YOUR_API_KEY"
        echo "You can create an API key at https://beta.openai.com/account/api-keys"
        exit 1
fi

# parse flags/parameters for the script
while [[ $# -gt 0 ]]; do
        case $1 in
                -i | --init-chat-prompt ) 
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
                -m | --model ) # check for other models to include
                        if [ "$2" = "gpt-3.5-turbo" ] || [ "$2" = "gpt-3.5" ] || [ "$2" = "gpt-3" ]; then
                                MODEL="$2"
                        # elif [ "$2" = "gpt-3.5" ]; then
                        #         MODEL="$2"
                        # elif [ "$2" = "gpt-3" ]; then
                        #         MODEL="$2"
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
                # --context )
                #         if [ "$2" = "drop" ]; then
                #                 HAS_CONTEXT=1
                #         elif [ "$2" = "summarize"]; then
                #                 HAS_CONTEXT=2
                #         elif [ "$2" = "off" ]; then
                #                 HAS_CONTEXT=0
                #         else
                #                 echo "Invalid context: $2"
                #                 exit 1
                #         fi
                #         shift
                #         shift
                #         ;;
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
                -h | --history ) # takes in chatname parameter, prints chat history
                        if [ -z "$2" ]; then # list all 
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

# make context file if it does not exist
init_context_file
context=$(cat "$CONTEXT_FILE_PATH")

# if no context, then just loop and prompt for questions

# check if chat context is empty (i.e. it does not contain an init prompt)
# if yes, then add the init prompt to the context as question 0
echo "context: $context"
get_questions_count
echo "CURRENT QUESTION: $CURRENT_QUESTION_INDEX"

if [ -z "$context" ]; then
        echo -e "----INITIALIZATION PROMPT----" >> "$CONTEXT_FILE_PATH"
        ask_question "$USER_INIT_PROMPT"
        write_to_context_file "$USER_INIT_PROMPT" "$processed_response" "$CURRENT_QUESTION_INDEX"
        echo -e "----END INITIALIZATION PROMPT----" >> "$CONTEXT_FILE_PATH"
fi

CURRENT_QUESTION_INDEX=$((CURRENT_QUESTION_INDEX+1))

echo "---------------INITIALIZATION PARAMS---------------"
echo "Initialization Prompt: $USER_INIT_PROMPT (default)"
echo "Model: $MODEL"
echo "Temperature: $TEMPERATURE"
echo "Chat Name: $CONTEXT_FILE_PATH"
echo "---------------------------------------------------"

# # get the current question number in the file
# echo $CURRENT_QUESTION_INDEX
# CURRENT_QUESTION_INDEX=$(sed -nE 's/^-------------------QUESTION ([0-9]+).*---------------------$/\1/p' $CONTEXT_FILE_PATH | tail -n 1)

# if [ -z "$CURRENT_QUESTION_INDEX" ]; then
#         CURRENT_QUESTION_INDEX=1
# else
#         CURRENT_QUESTION_INDEX=$((CURRENT_QUESTION_INDEX+1))
# fi

echo "init $CONTEXT_FILE_PATH"
# cat "$CONTEXT_FILE_PATH"
echo "curr question: $CURRENT_QUESTION_INDEX"

# type exit to exit
while true; do
        read -p "Ask a question: " -e input
        if [ "$input" == "exit" ] || [ "$input" == "q" ]; then
                echo "Shutting down..."
                exit 0
        else
                # preprocess the user's question
                preprocess "$input"
                preprocessed_question="$preprocessed_text"
                
                # ask the question, raw json is stored in $response, processed in $extracted_response
                ask_question "$preprocessed_question"
                # print the response and write it to the history file
                echo "response: $extracted_response"
                write_to_context_file "$question" "$extracted_response" "$CURRENT_QUESTION_INDEX"

                # update the current context
                # update_chat_context "$preprocessed_question" "$preprocessed_response"
                CURRENT_QUESTION_INDEX=$((CURRENT_QUESTION_INDEX + 1))
                echo "CURRENT QUESTION: $CURRENT_QUESTION_INDEX"
        fi
done
