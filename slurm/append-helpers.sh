#!/bin/bash

# Check if both arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <me_directory> <HOME>"
    echo "Example: $0 /scratch/myuser /home/myuser"
    exit 1
fi

ME_DIR="$1"
USER_HOME="$2"
BASHRC="$USER_HOME/.bashrc"

# Append the content into ~/.bashrc inside USER_HOME
cat << EOF >> "$BASHRC"

# === Custom Aliases and Functions ===

# Alias to show Slurm accounts for current user
alias myacct='sacctmgr -nP show assoc where user=\$(whoami) format=account'

# Alias 'me' to the directory passed as first argument
alias me="cd $ME_DIR"

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

