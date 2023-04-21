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
MAX_CONTEXT_TOKENS=$((MAX_TOKENS - 100))

# set default model parameters
SYSTEM_INIT_PROMPT="You are ChatGPT, a large language model trained by OpenAI. Answer as concisely as possible. Current date: $(date +%d/%m/%Y). Knowledge cutoff: 9/1/2021."
DEFAULT_INIT_PROMPT="You are ChatGPT, a Large Language Model trained by OpenAI. You will be answering questions from users. You answer as concisely as possible for each response (e.g. don’t be verbose). If you are generating a list, do not have too many items. Keep the number of items short. Before each user prompt you will be given the chat history in Q&A form. Output your answer directly, with no labels in front. Do not start your answers with A or Anwser. You were trained on data up until 2021. Today's date is $(date +%d/%m/%Y)"

WRITE_CODE_INIT_PROMPT="You are translating written prompts into code. Answer as concisely as possible."
EXPLAIN_CODE_INIT_PROMPT="You are summarizing a code snippet in natural language."

# set default init prompt"
USER_INIT_PROMPT="$DEFAULT_INIT_PROMPT"

### CONTEXT FUNCTIONS ###

# get approximate token count of current context
function get_token_count {
        char_count=$(echo "$context" | wc -c)
        approx_token_count=$(echo "scale=0; $char_count * 0.75" | bc)
        echo "approx token count: $approx_token_count"
}

# get the number of questions in the context file
function get_questions_count {
        CURRENT_QUESTION_INDEX=$(sed -nE 's/^-------------------QUESTION ([0-9]+)---------------------$/\1/p' $CONTEXT_FILE_PATH | tail -n 1)
        return $CURRENT_QUESTION_INDEX
}

# preprocesses the input $1 to escape quotation marks and replace newlines with spaces
function preprocess {
        preprocessed_text=$(echo "$1" | sed -e 's/"/\\"/g' | sed -e 's/\n/ /g')
}

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

# need to check that this function works correctly
# TODO: streamline the format of the context file (in both init_chat_context and write_to_context_file) - done
function init_chat_context {
        # check if context file is empty
        if [ -s "$CONTEXT_FILE_PATH" ]; then
                echo "Context is empty"
                # ask_question "$USER_INIT_PROMPT"
                echo -e "Initialization Prompt: $USER_INIT_PROMPT" >> "$CONTEXT_FILE_PATH"
                context="$USER_INIT_PROMPT"
        else 
                # we are continuing from a previous context
                # first get the initialization prompt and preprocess it
                USER_INIT_PROMPT=$(cat "$CONTEXT_FILE_PATH" | head -n 1 | sed 's/Initialization Prompt: (.*)/\1/')
                preprocess "$USER_INIT_PROMPT"
                preprocessed_USER_INIT_PROMPT="$preprocessed_text"

                # starting from last question, add to context until we exceed MAX_CONTEXT_TOKENS
                context="$preprocessed_USER_INIT_PROMPT\n$context"
                get_token_count
                init_prompt_token_count=$approx_token_count
                
                # total num questions in CURRENT_QUESTION_INDEX
                curr_question=$(get_questions_count)
                context=""

                while [ $(echo "$approx_token_count < $MAX_CONTEXT_TOKENS - $init_prompt_token_count)" | bc) -eq 1 ] && [ $curr_question -gt 0]; do
                        echo "---loop---"

                        # get the curr_question-th question and answer
                        curr_text=$(sed -n "/-------------------QUESTION $curr_question---------------------/,/-------------------END OF QUESTION $((curr_question+1))---------------------/p" $CONTEXT_FILE_PATH | tail -n +2 | head -n -1)
                        context="$curr_text\n$context"

                        echo "$context"
                        get_token_count
                done

                # add back the initialization prompt
                context="$preprocessed_USER_INIT_PROMPT\n$context"
                
        fi
        # get context from context file, and replace newlines with \n
        context=$(cat "$CONTEXT_FILE_PATH" | tail -n +5)
        context=$(echo "$context" | sed -e 's/"/\\"/g')
}

# chat history filenames are be of the form .GPTerminal/History/<timestamp> or <user-defined>
# stores Q: <user prompt> and A: <chat response> in the chat history file
# $1 is the user prompt/question, $2 is the chat response, $3 current question number
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
# $1 is processed question, $2 is processed response
function update_chat_context {

        # add new QnA to context
        context="$context\nQ: $1\nA: $2"
        echo "context: $context"

        # check context length 
        # approximately 1 token = 4 characters or ~.75 words (100 tokens = 75 words)
        get_token_count

        exceeds_max=$(echo "$approx_token_count > $MAX_CONTEXT_TOKENS" | bc)
        # echo "exceeds_max: $exceeds_max"

        #  TODO: DEBUG THIS FUNCTION SO THAT IT REMOVES ONLY THE FIRST QUESTION.
        #  CURRENTLY REMOVES EVERYTHING EXCEPT THE LAST QUESTION
        while [ $exceeds_max = 1 ]; do
                echo "-----LOOOP-----"
                # remove first/oldest QnA from prompt
                echo "TESTTT"
                echo "$context" | sed -n '/Q:/,$p' | tail -n +2

                # REMOVES EVERYTHING EXCEPT FOR THE LAST QUESTION
                cc=$(echo "$context" | sed 's/^.*Q:/Q:/')
                echo "processed: $cc"
                context=$(echo "$context" | sed '1,/\\nA: /d')
                # add back initialization prompt
                context="$USER_INIT_PROMPT\n$context"
                echo "$context"
                get_token_count
                exceeds_max=$(echo "$approx_token_count > $MAX_CONTEXT_TOKENS" | bc)
                echo "exceeds_max = $exceeds_max"
        done
}

# TESTING LINES FOR update_chat_context
# context="$USER_INIT_PROMPT\nQ: Give me a name\nA: Bob\nQ: another name?\nA: Robob\nQ: Give me a third name\nA: coBob"
# update_chat_context "What is your name?" "My name is GPTerminal"

# $1 is the processed prompt
# result is stored in chat_request
function make_chat_request_json {

        if [ -z "$chat_request" ]; then # initialize chat message if empty
                chat_request="{\"role\": \"user\", \"content\": \"$1\"}"
        else # append new question to chat message
                echo "appending new question to chat request: $1"
                chat_request="$chat_request, {\"role\": \"user\", \"content\": \"$1\"}"
        fi
}

# $1 is the processed response
# update the chat request with previous response
function update_chat_request_with_response {
        
        # add response to chat message
        chat_request="$chat_request, {\"role\": \"assistant\", \"content\": \"$1\"}"
        echo "CHAT REQUEST IN UPDATE: $chat_request"

        # transform to json array to parse with jq
	chat_request_json="[ $chat_request ]"
	# check prompt length, 1 word =~ 1.3 tokens
	# reserving 100 tokens for next user prompt
	while (($(echo "$chat_message" | wc -c) * 1, 3 > (MAX_TOKENS - 100))); do
		# remove first/oldest QnA from prompt
		chat_request=$(echo "$chat_request_json" | jq -c '.[2:] | .[] | {role, content}')
	done

}

# use curl to send question data to OpenAI server and get the response
# use json import in python to parse the response and get the answer (because it keeps new line characters)
function ask_question {
        prompt="$1" # this is preprocessed question
        echo "PROMPT RECEIVED IN ASK_QUESTION: $prompt"
        make_chat_request_json "$prompt"
        echo "chat_request: $chat_request"
        
        response=$(curl https://api.openai.com/v1/chat/completions \
                -H 'Content-Type: application/json' \
                -H "Authorization: Bearer $OPENAI_API_KEY" \
                -s -S \
                -d '{
                "model": "'"$MODEL"'",
                "messages": [{"role": "system", "content": "'"$SYSTEM_INIT_PROMPT"'"}, '"$chat_request"'],
                "temperature": '"$TEMPERATURE"',
                "max_tokens": '"$MAX_TOKENS"'
                }')

        extracted_response=$(echo "$response" | jq -r '.choices[0].message.content | @text')
        echo "extracted_response: $extracted_response"

        # preprocess response
        preprocess "$extracted_response"
        processed_response="$preprocessed_text"
                
        # remove new lines from response. replace with space
        processed_response=$(echo "$processed_response" | sed -e 's/\\n/ /g')
        # echo "processed_response: $processed_response"

        update_chat_request_with_response "$processed_response"
        echo "updated_chat_request: $chat_request"
}

# function ask_question {
#         echo "PROMPT PARAMETER: $1"
        
#         response=$(curl https://api.openai.com/v1/chat/completions \
#                 -H 'Content-Type: application/json' \
#                 -H "Authorization: Bearer $OPENAI_API_KEY" \
#                 -s -S \
#                 -d '{
#                 "model": "'"$MODEL"'",
#                 "messages": [{"role": "user", "content": "'"$1"'"}],
#                 "temperature": '"$TEMPERATURE"'
#                 }')

#         extracted_response=$(echo "$response" | jq -r '.choices[0].message.content | @text')
#         # extracted_response=$(echo "$response" | python -c "import sys, json; print(json.load(sys.stdin)['choices'][0]['message']['content'])")
#         # echo "response: $extracted_response"
#         write_to_context_file "$1" "$extracted_response" "$CURRENT_QUESTION_INDEX"
# }




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

echo "---------------INIT PARAMS---------------------"
echo "Initialization Prompt: $USER_INIT_PROMPT (default)"
echo "Model: $MODEL"
echo "Temperature: $TEMPERATURE"
echo "-----------------------------------------------"

# make context file if it does not exist
init_context_file
context=$(cat "$CONTEXT_FILE_PATH")

# if no context, then just loop and prompt for questions

# check if chat context is empty (i.e. it does not contain an init prompt)
# if yes, then add the init prompt to the context as question 0
echo "context: $context"

if [ -z "$context" ]; then
        echo "Context is empty"
        echo -e "----INITIALIZATION PROMPT----\n" >> "$CONTEXT_FILE_PATH"
        ask_question "$USER_INIT_PROMPT"
        write_to_context_file "$preprocessed_text"
        echo -e "----END INITIALIZATION PROMPT----\n" >> "$CONTEXT_FILE_PATH"
fi

# get the current question number in the file
echo $CURRENT_QUESTION_INDEX
CURRENT_QUESTION_INDEX=$(sed -nE 's/^-------------------QUESTION ([0-9]+).*---------------------$/\1/p' $CONTEXT_FILE_PATH | tail -n 1)

if [ -z "$CURRENT_QUESTION_INDEX" ]; then
        CURRENT_QUESTION_INDEX=1
else
        CURRENT_QUESTION_INDEX=$((CURRENT_QUESTION_INDEX+1))
fi

echo "$CONTEXT_FILE_PATH"
cat "$CONTEXT_FILE_PATH"
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

                # preprocess the response
                # preprocess "$extracted_response"
                # preprocessed_response="$preprocessed_text"

                # update the current context
                # update_chat_context "$preprocessed_question" "$preprocessed_response"
                CURRENT_QUESTION_INDEX=$((CURRENT_QUESTION_INDEX + 1))
        fi
done
