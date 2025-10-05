#!/bin/bash
# GitHub Repository Uploader - Enhanced Version with GUI Features
# Features: Create new repos, modify existing repos, clone repos, view repo info, check issues, and account management
# License: MIT

set -eo pipefail
exec > >(tee -a /tmp/github_uploader.log) 2>&1

# Configuration
CONFIG_DIR="$HOME/.config/github_uploader"
CONFIG_FILE="$CONFIG_DIR/config"
LOG_FILE="/tmp/github_uploader_$(date +%Y%m%d_%H%M%S).log"

# Initialize logging
mkdir -p "$(dirname "$LOG_FILE")"
echo "=== GitHub Uploader Started $(date) ===" > "$LOG_FILE"

# Load configuration
load_config() {
    mkdir -p "$CONFIG_DIR"
    touch "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        GITHUB_USER=""
        GITHUB_TOKEN=""
    fi
}

# Verify dependencies
verify_dependencies() {
    local missing=()
    for cmd in git curl jq zenity; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        zenity --error --text="Missing required tools: ${missing[*]}\nInstall with: sudo apt install ${missing[*]}"
        exit 1
    fi
}

# Get GitHub credentials with validation
get_credentials() {
    while true; do
        if [[ -z "$GITHUB_USER" || -z "$GITHUB_TOKEN" ]]; then
            creds=$(zenity --forms --title="GitHub Credentials" \
                --text="Enter GitHub Details" \
                --add-entry="Username" \
                --add-password="Personal Access Token" \
                --separator="|")
            
            if [[ -z "$creds" ]]; then
                exit 0
            fi
            
            GITHUB_USER=$(echo "$creds" | cut -d'|' -f1)
            GITHUB_TOKEN=$(echo "$creds" | cut -d'|' -f2)
            
            # Save config
            echo "GITHUB_USER=\"$GITHUB_USER\"" > "$CONFIG_FILE"
            echo "GITHUB_TOKEN=\"$GITHUB_TOKEN\"" >> "$CONFIG_FILE"
        fi
        
        # Validate credentials
        if validate_credentials; then
            break
        else
            zenity --error --text="Invalid GitHub credentials. Please check your username and token.\n\nMake sure your token has the 'repo' scope enabled."
            # Clear invalid credentials
            GITHUB_USER=""
            GITHUB_TOKEN=""
            rm -f "$CONFIG_FILE"
        fi
    done
}

# Validate GitHub credentials
validate_credentials() {
    local response=$(curl -s -w "%{http_code}" -u "$GITHUB_USER:$GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/user")
    
    local http_code=${response: -3}
    [[ "$http_code" == "200" ]]
}

# Delete account credentials
delete_credentials() {
    if [[ -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"
        zenity --info --text="Account credentials deleted successfully."
    else
        zenity --info --text="No account credentials found."
    fi
    exit 0
}

# Check if repository exists
repo_exists() {
    local repo_name="$1"
    local response=$(curl -s -o /dev/null -w "%{http_code}" -u "$GITHUB_USER:$GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USER/$repo_name")
    
    [[ "$response" == "200" ]]
}

# Create GitHub repository
create_repo() {
    local repo_name="$1"
    local description="$2"
    local license="$3"
    local private="$4"
    
    local license_template=""
    if [[ -n "$license" && "$license" != "none" ]]; then
        license_template=",\"license_template\":\"$license\""
    fi
    
    # Log the request details for debugging
    echo "Creating repository: $repo_name" >> "$LOG_FILE"
    echo "Description: $description" >> "$LOG_FILE"
    echo "License: $license" >> "$LOG_FILE"
    echo "Private: $private" >> "$LOG_FILE"
    
    local response=$(curl -w "%{http_code}" -s -u "$GITHUB_USER:$GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{
            \"name\": \"$repo_name\",
            \"description\": \"$description\",
            \"private\": $private,
            \"auto_init\": false
            $license_template
        }" \
        https://api.github.com/user/repos)
    
    # Extract HTTP status code and response body
    local http_code=${response: -3}
    local response_body=${response:0:${#response}-3}
    
    echo "HTTP Response Code: $http_code" >> "$LOG_FILE"
    echo "API Response: $response_body" >> "$LOG_FILE"
    
    if [[ "$http_code" != "201" ]]; then
        if echo "$response_body" | jq -e '.errors' &>/dev/null; then
            error_msg=$(echo "$response_body" | jq -r '.errors[0].message')
            zenity --error --text="GitHub API Error: $error_msg"
            return 1
        elif [[ "$http_code" == "401" ]]; then
            zenity --error --text="Authentication failed. Please check your credentials.\n\nMake sure your token has the 'repo' scope enabled."
            # Clear invalid credentials
            GITHUB_USER=""
            GITHUB_TOKEN=""
            rm -f "$CONFIG_FILE"
            return 1
        else
            zenity --error --text="Repository creation failed: HTTP $http_code. Check log: $LOG_FILE"
            return 1
        fi
    fi
    
    if ! echo "$response_body" | jq -e '.html_url' &>/dev/null; then
        zenity --error --text="Repository creation failed: Unexpected API response. Check log: $LOG_FILE"
        return 1
    fi
    
    echo "$response_body" | jq -r '.html_url'
}

# Show folder content preview
show_folder_content() {
    local folder_path="$1"
    local file_count=$(find "$folder_path" -type f | wc -l)
    local folder_count=$(find "$folder_path" -type d | wc -l)
    local total_size=$(du -sh "$folder_path" 2>/dev/null | cut -f1 || echo "Unknown")
    
    # Get list of files (limit to 20 for preview)
    local file_list=$(find "$folder_path" -type f -not -path '*/\.git/*' -printf "%f\n" | head -20)
    
    zenity --info \
        --title="Folder Content Preview" \
        --text="Folder: $(basename "$folder_path")\n\nTotal files: $file_count\nTotal folders: $folder_count\nTotal size: $total_size\n\nFirst 20 files:\n$file_list" \
        --width=500 \
        --height=400
}

# Initialize Git repository with content
initialize_repo() {
    local project_dir="$1"
    
    cd "$project_dir" || {
        zenity --error --text="Failed to access project directory: $project_dir"
        return 1
    }
    
    # Initialize repository only if not already a Git repo
    if [[ ! -d ".git" ]]; then
        git init --quiet || {
            zenity --error --text="Failed to initialize Git repository"
            return 1
        }
    fi
    
    # Add ALL files (including hidden ones except .git)
    find . -type f -not -path './.git/*' -exec git add {} + 2>/dev/null || {
        zenity --error --text="Failed to add files to Git"
        return 1
    }
    
    # Check if there are files to commit
    if [[ -n "$(git status --porcelain)" ]]; then
        git commit --quiet -m "Initial commit" || {
            zenity --error --text="Failed to create initial commit"
            return 1
        }
    else
        # Create minimal README if directory is empty
        echo "# $(basename "$project_dir")" > README.md
        echo "Project description" >> README.md
        git add README.md || {
            zenity --error --text="Failed to add README"
            return 1
        }
        git commit --quiet -m "Initial commit with README" || {
            zenity --error --text="Failed to create initial commit"
            return 1
        }
    fi
}

# Update existing repository
update_repo() {
    local project_dir="$1"
    local repo_name="$2"
    
    cd "$project_dir" || {
        zenity --error --text="Failed to access project directory: $project_dir"
        return 1
    }
    
    # Check if it's a git repository
    if [[ ! -d ".git" ]]; then
        zenity --error --text="Not a Git repository. Please initialize first."
        return 1
    fi
    
    # Check if remote already exists and remove it if it does
    if git remote get-url origin &>/dev/null; then
        git remote remove origin || {
            zenity --error --text="Failed to remove existing remote origin"
            return 1
        }
    fi
    
    # Add the remote with credentials
    git remote add origin "https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/$repo_name.git" || {
        zenity --error --text="Failed to add remote origin. Please check your credentials and repository name."
        return 1
    }
    
    # Add all changes
    find . -type f -not -path './.git/*' -exec git add {} + 2>/dev/null || {
        zenity --error --text="Failed to add files to Git"
        return 1
    }
    
    # Check if there are changes to commit
    if [[ -n "$(git status --porcelain)" ]]; then
        git commit --quiet -m "Auto-update $(date '+%Y-%m-%d %H:%M:%S')" || {
            zenity --error --text="Failed to create commit"
            return 1
        }
    fi
    
    # Push changes with better error handling
    if ! git push --set-upstream origin main --force 2>> "$LOG_FILE"; then
        zenity --error --text="Failed to push to repository. Please check the log file: $LOG_FILE"
        return 1
    fi
    
    zenity --info \
        --title="Success" \
        --text="Repository updated successfully!\n\nhttps://github.com/$GITHUB_USER/$repo_name"
}

# Clone a GitHub repository
clone_repo() {
    get_credentials
    
    local repo_url=$(zenity --entry \
        --title="Clone Repository" \
        --text="Enter GitHub repository URL to clone:" \
        --width=500)
    
    if [[ -z "$repo_url" ]]; then
        return 1
    fi
    
    # Extract repo name from URL for default directory name
    local repo_name=$(basename "$repo_url" .git)
    
    local clone_dir=$(zenity --file-selection \
        --title="Select Directory to Clone Into" \
        --directory \
        --filename="$HOME/")
    
    if [[ -z "$clone_dir" ]]; then
        return 1
    fi
    
    local full_clone_path="$clone_dir/$repo_name"
    
    # Check if directory already exists
    if [[ -d "$full_clone_path" ]]; then
        zenity --question \
            --title="Directory Exists" \
            --text="Directory '$full_clone_path' already exists. Do you want to overwrite it?" \
            --ok-label="Overwrite" \
            --cancel-label="Cancel"
        
        if [[ $? -ne 0 ]]; then
            return 1
        fi
        
        # Remove existing directory
        rm -rf "$full_clone_path"
    fi
    
    # Clone with progress
    (git clone "$repo_url" "$full_clone_path" 2>&1 | \
        while read line; do
            if [[ $line =~ ^Cloning ]]; then
                echo "# $line"
            elif [[ $line =~ ^[0-9]+% ]]; then
                echo $line | grep -o '[0-9]*%' | tr -d '%'
            fi
        done | \
        zenity --progress \
        --title="Cloning Repository" \
        --text="Cloning $repo_url..." \
        --auto-close \
        --auto-kill \
        --percentage=0) 
    
    if [[ $? -eq 0 ]]; then
        zenity --info \
            --title="Success" \
            --text="Repository cloned successfully!\n\nLocation: $full_clone_path"
    else
        zenity --error \
            --title="Error" \
            --text="Failed to clone repository. Please check the URL and your credentials."
    fi
}

# View repository information
view_repo_info() {
    get_credentials
    
    local repo_name=$(zenity --entry \
        --title="View Repository Info" \
        --text="Enter repository name:" \
        --entry-text="")
    
    if [[ -z "$repo_name" ]]; then
        return 1
    fi
    
    # Get repository info from GitHub API
    local response=$(curl -s -u "$GITHUB_USER:$GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USER/$repo_name")
    
    if echo "$response" | jq -e '.message' &>/dev/null; then
        zenity --error --text="Repository not found: $repo_name"
        return 1
    fi
    
    local description=$(echo "$response" | jq -r '.description // "No description"')
    local stars=$(echo "$response" | jq -r '.stargazers_count')
    local forks=$(echo "$response" | jq -r '.forks_count')
    local issues=$(echo "$response" | jq -r '.open_issues_count')
    local url=$(echo "$response" | jq -r '.html_url')
    local created=$(echo "$response" | jq -r '.created_at' | cut -d'T' -f1)
    local updated=$(echo "$response" | jq -r '.updated_at' | cut -d'T' -f1)
    
    zenity --info \
        --title="Repository Information: $repo_name" \
        --text="Description: $description\nStars: ⭐ $stars\nForks: 🍴 $forks\nOpen Issues: 🐛 $issues\nURL: $url\nCreated: $created\nLast Updated: $updated" \
        --width=500 \
        --height=300
}

# Check repository issues
check_issues() {
    get_credentials
    
    local repo_name=$(zenity --entry \
        --title="Check Repository Issues" \
        --text="Enter repository name:" \
        --entry-text="")
    
    if [[ -z "$repo_name" ]]; then
        return 1
    fi
    
    # Get issues from GitHub API
    local response=$(curl -s -u "$GITHUB_USER:$GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_USER/$repo_name/issues?state=all")
    
    if echo "$response" | jq -e '.message' &>/dev/null; then
        zenity --error --text="Repository not found: $repo_name"
        return 1
    fi
    
    local issues_count=$(echo "$response" | jq 'length')
    local open_issues=0
    local closed_issues=0
    
    # Count open and closed issues
    for i in $(seq 0 $(($issues_count-1))); do
        local state=$(echo "$response" | jq -r ".[$i].state")
        if [[ "$state" == "open" ]]; then
            ((open_issues++))
        else
            ((closed_issues++))
        fi
    done
    
    zenity --info \
        --title="Issues Summary: $repo_name" \
        --text="Total Issues: $issues_count\nOpen Issues: $open_issues\nClosed Issues: $closed_issues\n\nView details in log: $LOG_FILE" \
        --width=400 \
        --height=200
    
    # Log detailed issues information
    echo "=== Issues for $repo_name ===" >> "$LOG_FILE"
    echo "$response" | jq '.' >> "$LOG_FILE"
}

# Show token help
show_token_help() {
    zenity --info --title="GitHub Token Help" \
        --text="To create a GitHub Personal Access Token:\n\n1. Go to GitHub.com → Settings → Developer settings → Personal access tokens\n2. Click 'Generate new token'\n3. Give it a name and select the 'repo' scope\n4. Click 'Generate token'\n5. Copy the token and use it in this application\n\nNote: The token will only be shown once, so copy it immediately." \
        --width=500
}

# Main workflow
main() {
    verify_dependencies
    load_config
    
    local project_dir="${1:-$PWD}"
    if [[ ! -d "$project_dir" ]]; then
        zenity --error --text="Directory does not exist: $project_dir"
        exit 1
    fi
    
    # Show folder content preview
    show_folder_content "$project_dir"
    
    # Show action selection with new features
    local action=$(zenity --list \
        --title="GitHub Repository Manager" \
        --text="Select action for folder: $(basename "$project_dir")" \
        --column="Action" \
        "Create New Repository" \
        "Update Existing Repository" \
        "Clone Repository" \
        "View Repository Info" \
        "Check Repository Issues" \
        "Delete Account Credentials" \
        "Token Help" \
        --height=350 \
        --width=400)
    
    if [[ -z "$action" ]]; then
        exit 0
    fi
    
    case "$action" in
        "Delete Account Credentials")
            delete_credentials
            ;;
        "Token Help")
            show_token_help
            exit 0
            ;;
        "Create New Repository")
            get_credentials
            
            # Get user input
            local folder_name=$(basename "$project_dir")
            local inputs=$(zenity --forms --title="GitHub Repository Setup" \
                --text="Enter repository details" \
                --add-entry="Repository name:" \
                --add-entry="Description:" \
                --add-combo="License:" \
                --combo-values="none|MIT|Apache-2.0|GPL-3.0" \
                --add-combo="Visibility:" \
                --combo-values="public|private")
            
            if [[ -z "$inputs" ]]; then
                exit 0
            fi
            
            IFS='|' read -r repo_name description license visibility <<< "$inputs"
            repo_name=${repo_name:-$folder_name}
            license=${license:-none}
            private=false
            [[ "$visibility" == "private" ]] && private=true
            
            # Confirm
            zenity --question \
                --title="Confirmation" \
                --text="Create repository?\n\nName: $repo_name\nDescription: $description\nLicense: $license\nPrivate: $private" \
                --ok-label="Create" \
                --cancel-label="Cancel" || exit 0
            
            # Check if repo already exists
            if repo_exists "$repo_name"; then
                zenity --error --text="Repository '$repo_name' already exists. Please choose a different name."
                exit 1
            fi
            
            # Create GitHub repository
            repo_url=$(create_repo "$repo_name" "$description" "$license" "$private") || exit 1
            
            # Initialize and push
            initialize_repo "$project_dir" || exit 1
            
            # Ensure we're on main branch
            git checkout -B main || {
                zenity --error --text="Failed to switch to main branch"
                exit 1
            }
            
            # Remove existing remote if it exists
            if git remote get-url origin &>/dev/null; then
                git remote remove origin
            fi
            
            git remote add origin "https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/$repo_name.git" || {
                zenity --error --text="Failed to add remote origin. Please check your credentials."
                exit 1
            }
            
            # Force push to ensure files are uploaded
            git push --set-upstream origin main --force || {
                zenity --error --text="Failed to push to repository. Error: $?"
                exit 1
            }
            
            # Show success
            zenity --info \
                --title="Success" \
                --text="Repository created successfully!\n\n$repo_url\n\nAll files have been uploaded." \
                --no-wrap
            ;;
        "Update Existing Repository")
            get_credentials
            
            # Get repository name
            local folder_name=$(basename "$project_dir")
            local repo_name=$(zenity --entry \
                --title="Update Repository" \
                --text="Enter repository name to update:" \
                --entry-text="$folder_name")
            
            if [[ -z "$repo_name" ]]; then
                exit 0
            fi
            
            # Check if repo exists
            if ! repo_exists "$repo_name"; then
                zenity --error --text="Repository '$repo_name' does not exist."
                exit 1
            fi
            
            # Update repository
            update_repo "$project_dir" "$repo_name"
            ;;
        "Clone Repository")
            clone_repo
            ;;
        "View Repository Info")
            view_repo_info
            ;;
        "Check Repository Issues")
            check_issues
            ;;
    esac
}

main "$@"
