#!/usr/bin/env zsh
# AI-powered shell functions
# These are sourced from the zsh module because they contain complex shell syntax
# that's difficult to express directly in Nix strings

# Git AI commit - generates semantic commit messages for staged changes
function git_ai_commit() {
    if ! git diff --cached --quiet; then
        # Check if llm is available
        if ! command -v llm &> /dev/null; then
            echo "Error: llm is not installed. Please install it first."
            return 1
        fi
        
        # Generate commit message using AI and commit immediately
        local commit_msg
        commit_msg=$(llm -m 4o  << EOF 2>/dev/null
Generate a semantic commit message following the format: type(scope): description  
Common types: feat, fix, docs, style, refactor, test, chore
Here are the staged files:
$(git diff --cached --name-only)
And here are the changes:
$(git diff --cached)
Respond ONLY with the commit message, nothing else. Make it concise and descriptive.
EOF
)

        git commit -m "$commit_msg"
    else
        echo "No staged changes to commit"
    fi
}

# Git PR AI - generates PR title and description for current branch
function gprai() {
    local current_branch base_ref branch_diff changed_files pr_prompt pr_content
    
    # Check if llm is available
    if ! command -v llm &> /dev/null; then
        echo "Error: llm is not installed. Please install it first."
        return 1
    fi
    
    # 1) Figure out current branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    # 2) Pick the main ref (prefer origin branches to avoid outdated local refs)
    if git show-ref --verify --quiet refs/remotes/origin/main; then
        base_ref=origin/main
    elif git show-ref --verify --quiet refs/remotes/origin/master; then
        base_ref=origin/master
    else
        echo "Error: 'origin/main' or 'origin/master' branch not found. Make sure you've fetched from origin."
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
    
    # 4) Generate PR content using AI
    pr_content=$(llm -m 4o << EOF 2>/dev/null
Generate a PR title and description based on these changes.
Use semantic format: type(scope): description
Common types: feat, fix, docs, style, refactor, test, chore

Files changed:
$changed_files

Diff:
$branch_diff

Respond *exactly* in this format:

TITLE: <type(scope): concise summary>
DESCRIPTION:
## Overview
<one or two sentence high-level summary>

## Changes Made
- <bullet points of specific changes>

## Testing
- <how this was tested or should be tested>
EOF
)
    
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

# Aliases for AI functions
alias gcai="git_ai_commit"
alias gprai="gprai"

# Export functions so they're available in subshells
export -f git_ai_commit
export -f gprai
export -f explain_command
export -f fix_error