#!/usr/bin/env python3
"""IRC relay bot - receives messages, writes to inbox, sends replies from FIFO."""

import socket
import time
import os
import select
import json
import re

SERVER = "127.0.0.1"
PORT = 6667
NICK = "pi-agent"
CHANNEL = "#general"
FIFO = "/tmp/irc-bot.fifo"
INBOX = "/tmp/irc-inbox.jsonl"
LAST_SEEN = "/tmp/irc-ext-last-id"

def setup():
    if os.path.exists(FIFO):
        os.unlink(FIFO)
    os.mkfifo(FIFO)
    # Clear inbox
    with open(INBOX, "w") as f:
        f.write("")
    # Reset extension last-seen counters so both observer and driver pick up new messages
    for f in [LAST_SEEN, "/tmp/irc-ext-last-id-worker"]:
        if os.path.exists(f):
            os.unlink(f)

MAX_LINE = 400  # stay under 512 IRC limit

def send(sock, msg):
    sock.sendall(f"{msg}\r\n".encode())

def _send_chunked(sock, text):
    """Split long messages into IRC-safe chunks."""
    prefix = f"PRIVMSG {CHANNEL} :"
    max_content = MAX_LINE - len(prefix) - 2
    while len(text) > max_content:
        split_at = text.rfind(" ", 0, max_content)
        if split_at == -1:
            split_at = max_content
        chunk = text[:split_at]
        text = text[split_at:].strip()
        send(sock, f"{prefix}{chunk}")
        time.sleep(0.15)
    if text:
        send(sock, f"{prefix}{text}")

def main():
    setup()
    
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect((SERVER, PORT))
    
    send(sock, f"NICK {NICK}")
    send(sock, f"USER {NICK} 0 * :{NICK}")
    time.sleep(0.3)
    send(sock, f"JOIN {CHANNEL}")
    time.sleep(0.3)
    
    with open("/tmp/irc-bot-ready", "w") as f:
        f.write("ready")
    
    fifo_fd = os.open(FIFO, os.O_RDONLY | os.O_NONBLOCK)
    sock_fd = sock.fileno()
    buf = b""
    last_seen_id = 0
    msg_counter = 0
    current_nick = NICK  # track nick changes for inbox entries
    
    while True:
        readable, _, _ = select.select([sock_fd, fifo_fd], [], [], 0.3)
        
        for fd in readable:
            if fd == sock_fd:
                try:
                    data = sock.recv(4096)
                except:
                    return
                if not data:
                    return
                buf += data
                while b"\r\n" in buf:
                    line_bytes, buf = buf.split(b"\r\n", 1)
                    line = line_bytes.decode("utf-8", errors="replace")
                    
                    if line.startswith("PING"):
                        send(sock, f"PONG {line[5:]}")
                        continue
                    
                    # Match any PRIVMSG to #general from any sender
                    m = re.match(r":([^!]+)![^ ]+ PRIVMSG " + re.escape(CHANNEL) + r" :(.+)", line)
                    if m:
                        sender = m.group(1)
                        content = m.group(2)
                        # Skip echo of our own messages (ngircd reflects them back).
                        # Our own sent messages are already written to inbox from the FIFO handler.
                        if sender.lower() == current_nick.lower():
                            continue
                        msg_counter += 1
                        entry = json.dumps({
                            "id": msg_counter,
                            "from": sender,
                            "msg": content,
                            "time": time.strftime("%H:%M:%S")
                        })
                        with open(INBOX, "a") as f:
                            f.write(entry + "\n")
                        # Signal new message is available
                        with open("/tmp/irc-new-msg", "w") as f:
                            f.write(str(msg_counter))
                    
            elif fd == fifo_fd:
                try:
                    msg = os.read(fifo_fd, 4096).decode().strip()
                    if msg:
                        if msg.startswith("/quit"):
                            send(sock, "QUIT :Goodbye!")
                            time.sleep(0.3)
                            sock.close()
                            os.close(fifo_fd)
                            os.unlink(FIFO)
                            return
                        elif msg.startswith("/nick "):
                            new_nick = msg[6:].strip()
                            current_nick = new_nick
                            send(sock, f"NICK {new_nick}")
                        elif msg.startswith("/msg "):
                            _send_chunked(sock, msg[5:])
                            # Also write to inbox so the worker sees it
                            if not msg.startswith("WORKER:"):
                                msg_counter += 1
                                entry = json.dumps({
                                    "id": msg_counter,
                                    "from": current_nick,
                                    "msg": msg[5:],
                                    "time": time.strftime("%H:%M:%S")
                                })
                                with open(INBOX, "a") as f:
                                    f.write(entry + "\n")
                        elif msg.startswith("/raw "):
                            send(sock, msg[5:])
                        else:
                            _send_chunked(sock, msg)
                            # Also write to inbox so the worker sees it
                            # Skip worker's own messages to prevent loops
                            if not msg.startswith("WORKER:"):
                                msg_counter += 1
                                entry = json.dumps({
                                    "id": msg_counter,
                                    "from": current_nick,
                                    "msg": msg,
                                    "time": time.strftime("%H:%M:%S")
                                })
                                with open(INBOX, "a") as f:
                                    f.write(entry + "\n")
                except BlockingIOError:
                    pass

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    finally:
        if os.path.exists(FIFO):
            os.unlink(FIFO)
