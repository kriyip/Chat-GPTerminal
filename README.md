# Chat-GPTerminal
--- 
<!-- Description -->
A simple lightweight shell program for using OpenAI's `gpt-3.5-turbo` model from your terminal.

<!-- Usage -->
## Features
Users can use the `GPTerminal.sh` file with several different parameter flags. Note that you can use multiple flags at the same time.
- Run the script (default mode): `./GPTerminal.sh` (or `GPTerminal` if added to your path). Ask questions to OpenAI's gpt chatbot and receive context-aware responses (note that the current implementation uses a short-term memory situation, where older messages get deleted from context in order to meet the token length limitations of the OpenAI API).
<!-- example 1 -->
![Demo1](https://drive.google.com/file/d/1-nl-8OpDtFjSCx9hOhVwnNGz4MTvkz2i/view?usp=share_link)

- Initialize the chatbot with predefined or custom parameters:
    - Choose from two predefined initializations:
        - `linux-write` (writes linux terminal commands from an input description): `./GPTerminal.sh -i "linux-write"`
        - `linux-explain` (explains a linux terminal command): `./GPTerminal.sh -i "linux-explain"`
    - Write your own custom initialization prompt: `./GPTerminal.sh -i "your initialization prompt here"` or `./GPTerminal.sh --init-chat-prompt "You are "`

- Define the temperature parameter of the chatbot (higher temperatures give more creative entropic responses, lower temperatures give more conservative predictive output): `./GPTerminal.sh -t [value between 0 and 1.0]` or `./GPTerminal.sh --temperature 0.7`

- Define a name for a new chat history. If this parameter is not specified, the chat history will be saved under the current timestamp: `./GPTerminal.sh -n "chat name"` or `./GPTerminal.sh --new-name-chat "chat name"`

<!-- example 2: init, temp, chat name -->
![Demo2](https://drive.google.com/file/d/14Q1aBfQ36TBYgQpqnwgFKgipGLUPHOE6/view?usp=share_link)


- List all previous chats: `./GPTerminal.sh -h` or `./GPterminal.sh --history`

- View a previous chat history: `./GPTerminal.sh -h "chat name"` or `./GPTerminal.sh --history "chat name"`

- Ask a quick question (the context will not be saved and a history file will not be created): `./GPTerminal.sh -q "Your question here"`

- Type `exit` or  `q` to quit the program

<!-- example 3: history and quick question -->
![Demo3](https://drive.google.com/file/d/1mZBF9B9WPGoHdTn9ePR_E78zKagHcZdv/view?usp=share_link)

<!-- How to Use It -->
# Installation
---
## Prerequisites
1. `curl` is used to make requests and receive data from the API
2. `jq` is used to parse, format, and create JSON requests and responses with the API
3. An OpenAI API Key. This can be created [here](https://platform.openai.com/account/api-keys).

## Setup
1. Add the OpenAI API Key to your shell profile: `export OPENAI_API_KEY=YOUR_API_KEY`
2. Download the `GPTerminal.sh` file or clone this repository.
3. If desired, add `GPTerminal.sh` to your `PATH`: `export PATH=$PATH:/path/to/GPTerminal.sh`. You can also run the script like any other bash script: run `chmod u+x GPTerminal.sh`, then `./GPTerminal.sh -[desired flags]`