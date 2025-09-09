#!/bin/bash

# Check if homedir argument was provided
if [ -z "$1" ]; then
    echo "Usage: $0 <homedir>"
    echo "Example: $0 /home/myuser"
    exit 1
fi

HOMEDIR="$1"
BASHRC="~/.bashrc"

# Append the content into .bashrc
cat << EOF >> "$BASHRC"

# === Custom Aliases and Functions ===

# Alias to show Slurm accounts for current user
alias myacct='sacctmgr -nP show assoc where user=\$(whoami) format=account'

# Alias 'me' to home directory provided as argument
alias me="cd $HOMEDIR"

# Enroot container creation
enc() {
    if [ -z "\$1" ] || [ -z "\$2" ]; then
        echo "Usage: enc <name> <path>"
        echo "Example: enc my-ubuntu /path/to/ubuntu.sqsh"
        return 1
    fi

    echo "Creating enroot container named '\$1' from '\$2'"
    enroot create -n "\$1" "\$2"
}

# Enroot start alias
alias ens="enroot start --rw --root --mount"

# Squeue filter for your jobs
alias sqme="squeue --start | grep idhanani"

# Run interactive shell on node for job
sr() {
    if [ \$# -ne 2 ]; then
        echo "Usage: sr <jobid> <node_name>"
        return 1
    fi

    local jobid="\$1"
    local node_name="\$2"

    srun --jobid "\$jobid" --overlap -w eos"\$node_name" --pty /bin/bash
}
EOF

echo "Custom aliases and functions appended to $BASHRC"
echo "Run 'source $BASHRC' or restart your shell to apply changes."

