#!/bin/bash
# Usage: ./scripts/irc-say.sh "your message here"
#    or ./scripts/irc-say.sh /quit
echo "$*" > /tmp/irc-bot.fifo
