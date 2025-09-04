#!/usr/bin/env zsh
# AI-powered shell functions
# These are sourced from the zsh module because they contain complex shell syntax
# that's difficult to express directly in Nix strings

# Git AI commit - generates semantic commit messages for staged changes
function git_ai_commit() {
    if ! git diff --cached --quiet; then
        # Check if cgpt is available
        if ! command -v cgpt &> /dev/null; then
            echo "Error: cgpt is not installed. Please install it first."
            return 1
        fi
        
        # Generate commit message using AI
        local commit_msg
        commit_msg=$(cgpt --no-history << 'EOF' 2>/dev/null
Generate a semantic commit message following the format: type(scope): description
Common types: feat, fix, docs, style, refactor, test, chore
Here are the staged files:
$(git diff --cached --name-only)
And here are the changes:
$(git diff --cached)
Respond ONLY with the commit message, nothing else. Make it concise and descriptive.
EOF
)
        
        # Show the proposed message
        echo "Proposed commit message:"
        echo "$commit_msg"
        echo ""
        
        # Ask for confirmation
        read -q "response?Do you want to use this commit message? (y/N) "
        echo ""
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            git commit -m "$commit_msg"
        else
            echo "Commit cancelled."
        fi
    else
        echo "No staged changes to commit"
    fi
}

# Git PR AI - generates PR title and description for current branch
function gprai() {
    local current_branch base_ref branch_diff changed_files pr_prompt pr_content
    
    # Check if cgpt is available
    if ! command -v cgpt &> /dev/null; then
        echo "Error: cgpt is not installed. Please install it first."
        return 1
    fi
    
    # 1) Figure out current branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    # 2) Pick the main ref (prefer origin/main, fall back to local main)
    if git show-ref --verify --quiet refs/remotes/origin/main; then
        base_ref=origin/main
    elif git show-ref --verify --quiet refs/heads/main; then
        base_ref=main
    elif git show-ref --verify --quiet refs/remotes/origin/master; then
        base_ref=origin/master
    elif git show-ref --verify --quiet refs/heads/master; then
        base_ref=master
    else
        echo "Error: 'main' or 'master' branch not found locally or on origin."
        return 1
    fi
    
    # 3) Get diff + file list
    branch_diff=$(git diff "$base_ref...$current_branch")
    changed_files=$(git diff --name-only "$base_ref...$current_branch")
    
    # Check if there are changes
    if [[ -z "$changed_files" ]]; then
        echo "No changes detected between $current_branch and $base_ref"
        return 1
    fi
    
    # 4) Build the prompt
    pr_prompt=$(cat <<'PROMPT_EOF'
Generate a PR title and description based on these changes.
Use semantic format: type(scope): description
Common types: feat, fix, docs, style, refactor, test, chore

Files changed:
${changed_files}

Diff:
${branch_diff}

Respond *exactly* in this format:

TITLE: <type(scope): concise summary>
DESCRIPTION:
## Overview
<one or two sentence high-level summary>

## Changes Made
- <bullet points of specific changes>

## Testing
- <how this was tested or should be tested>
PROMPT_EOF
)
    
    # 5) Call cgpt with the actual values substituted
    pr_content=$(echo "$pr_prompt" | sed "s/\${changed_files}/$changed_files/g" | sed "s/\${branch_diff}/$(echo "$branch_diff" | sed 's/[\&/]/\\&/g')/g" | cgpt --no-history 2>/dev/null)
    
    # 6) Output the AI response
    printf "%s\n" "$pr_content"
    
    # Optional: offer to create the PR directly with gh CLI
    if command -v gh &> /dev/null; then
        echo ""
        read -q "response?Do you want to create this PR with gh CLI? (y/N) "
        echo ""
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            # Parse title and description
            local title=$(echo "$pr_content" | grep "^TITLE:" | sed 's/^TITLE: //')
            local description=$(echo "$pr_content" | sed '1,/^DESCRIPTION:/d')
            
            if [[ -n "$title" ]]; then
                gh pr create --title "$title" --body "$description"
            else
                echo "Error: Could not parse PR title from AI response"
            fi
        fi
    fi
}

# AI-powered command explanation
function explain_command() {
    local cmd="$*"
    
    if [[ -z "$cmd" ]]; then
        echo "Usage: explain_command <command>"
        return 1
    fi
    
    if ! command -v cgpt &> /dev/null; then
        echo "Error: cgpt is not installed."
        return 1
    fi
    
    cgpt --no-history << EOF
Explain this command in simple terms:
$cmd

Include:
1. What the command does
2. Break down each part/flag
3. Example use cases
4. Any warnings or things to be careful about
EOF
}

# AI-powered error diagnosis
function fix_error() {
    local error_msg="$*"
    
    if [[ -z "$error_msg" ]]; then
        echo "Usage: fix_error <error message>"
        echo "Or pipe an error: command_that_fails 2>&1 | fix_error"
        
        # Check if input is coming from pipe
        if [[ ! -t 0 ]]; then
            error_msg=$(cat)
        else
            return 1
        fi
    fi
    
    if ! command -v cgpt &> /dev/null; then
        echo "Error: cgpt is not installed."
        return 1
    fi
    
    cgpt --no-history << EOF
I got this error:
$error_msg

Please:
1. Explain what the error means
2. Suggest how to fix it
3. Provide the exact commands to run if applicable
EOF
}

# Aliases for AI functions
alias gcai="git_ai_commit"
alias gprai="gprai"
alias explain="explain_command"
alias fixerr="fix_error"

# Export functions so they're available in subshells
export -f git_ai_commit
export -f gprai
export -f explain_command
export -f fix_error