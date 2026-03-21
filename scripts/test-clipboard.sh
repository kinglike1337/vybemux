#!/bin/bash

set -e

echo "================================"
echo "vybemux Clipboard Integration Test"
echo "================================"
echo ""

all_passed=true

# Test 1: tmux Version
echo -n "[*] Checking tmux version... "
if command -v tmux >/dev/null 2>&1; then
    tmux_version=$(tmux -V | cut -d ' ' -f 2)
    tmux_major=$(echo "$tmux_version" | cut -d '.' -f 1)
    tmux_minor=$(echo "$tmux_version" | cut -d '.' -f 2 | cut -d 'a' -f 1)
    
    if [ "$tmux_major" -gt 3 ] || { [ "$tmux_major" -eq 3 ] && [ "$tmux_minor" -ge 2 ]; }; then
        echo -e "\033[32mSUCCESS\033[0m (version $tmux_version)"
    else
        echo -e "\033[33mWARNING\033[0m (version $tmux_version, < 3.3 - allow-passthrough may not work)"
    fi
else
    echo -e "\033[31mFAILED\033[0m (tmux not found)"
    all_passed=false
fi

# Test 2: set-clipboard setting
echo -n "[*] Checking set-clipboard... "
set_clipboard=$(tmux show-options -g set-clipboard 2>/dev/null | awk '{print $2}' || echo "not set")
if [ "$set_clipboard" = "on" ]; then
    echo -e "\033[32mSUCCESS\033[0m (on)"
elif [ "$set_clipboard" = "external" ]; then
    echo -e "\033[33mWARNING\033[0m (external - OSC 52 may not work)"
else
    echo -e "\033[31mFAILED\033[0m ($set_clipboard - expected 'on')"
    all_passed=false
fi

# Test 3: allow-passthrough setting
echo -n "[*] Checking allow-passthrough... "
allow_passthrough=$(tmux show-options -g allow-passthrough 2>/dev/null | awk '{print $2}' || echo "not set")
if [ "$allow_passthrough" = "on" ]; then
    echo -e "\033[32mSUCCESS\033[0m (on)"
else
    echo -e "\033[33mWARNING\033[0m ($allow_passthrough - nested OSC 52 may not work)"
fi

# Test 4: tmux-yank @custom_copy_command
echo -n "[*] Checking tmux-yank fallback... "
custom_command=$(tmux show-options -g @custom_copy_command 2>/dev/null || echo "")
if [ -n "$custom_command" ]; then
    if echo "$custom_command" | grep -q "033]52;c"; then
        echo -e "\033[32mSUCCESS\033[0m (OSC 52 configured as fallback)"
    else
        echo -e "\033[33mWARNING\033[0m (configured but may not use OSC 52)"
    fi
else
    echo -e "\033[33mWARNING\033[0m (not configured - will use xsel/xclip if available)"
fi

# Test 5: tmux-yank loaded
echo -n "[*] Checking tmux-yank plugin... "
if tmux list-keys -T copy-mode-vi 2>/dev/null | grep -q "yank"; then
    echo -e "\033[32mSUCCESS\033[0m (loaded)"
else
    echo -e "\033[33mWARNING\033[0m (may not be loaded)"
fi

# Test 6: OSC 52 sequence test
echo -n "[*] Testing OSC 52 sequence... "
test_text="vybemux clipboard test"
osc52_test=$(printf "\033]52;c;%s\033\\" "$(echo -n "$test_text" | base64 -w0)")
if tmux send-keys -l "$osc52_test" 2>/dev/null; then
    echo -e "\033[32mSUCCESS\033[0m (sequence sent)"
else
    echo -e "\033[33mWARNING\033[0m (could not send - may be normal if not in a session)"
fi

echo ""
echo "================================"
if [ "$all_passed" = true ]; then
    echo -e "\033[32mAll critical tests passed!\033[0m"
else
    echo -e "\033[31mSome tests failed - please check configuration\033[0m"
fi
echo "================================"
echo ""
echo "Manual verification:"
echo "1. In tmux: Press Prefix + [ (enter copy mode)"
echo "2. Select some text with vi keys (v) or mouse drag"
echo "3. Press y to yank to clipboard"
echo "4. Try pasting in VS Code (Ctrl+V)"
echo ""
echo "Note: OSC 52 works with Code-Server/xterm.js in browsers."
echo "For SSH access, install xsel or xclip for native X11 clipboard."
