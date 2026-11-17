#!/bin/bash
os_type=""
# edit it according to your own path
# 尝试获取操作系统类型
os_name=$(uname -s)

echo "=================================="
echo "Git iOS Auto-Commit Script Starting..."
echo "=================================="
echo "Detected system: $os_name"

case $os_name in
Linux)
  os_type="iPad Pro"
  ;;
Darwin)
  os_type="macOS"
  ;;
*)
  # 其他未知系统类型默认为iPhone
  os_type="iPhone"
  ;;
esac

# 输出操作系统类型
echo "OS Type: $os_type"
echo "Script execution time: $(date)"
echo "----------------------------------"

# Define the directory
dir=$(pwd)
echo "Current working directory: $dir"

# Check if the directory exists
if [ -d "$dir" ]; then
  echo "✓ Directory exists, proceeding..."
  cd "$dir"
else
  echo "✗ Error: Directory $dir does not exist."
  exit 1
fi

# Check if this is a git repository
if [ ! -d ".git" ]; then
  echo "✗ Error: This is not a git repository!"
  exit 1
fi
echo "✓ Git repository detected"

# Get the current date
riqi=$(date)
echo "Current timestamp: $riqi"

# Check git status
echo "----------------------------------"
echo "Checking git status..."
git_status=$(git status --porcelain)
echo "Git status output:"
git status --short

# Check if there are any changes
if [ -n "$git_status" ]; then
  echo "✓ Changes detected, proceeding with commit process..."
  echo "Number of changed files: $(echo "$git_status" | wc -l)"
  echo "Changed files:"
  echo "$git_status" | sed 's/^/   /'
  echo "----------------------------------"
  echo "Adding changes to git staging area..."
  git add .
  if [ $? -eq 0 ]; then
    echo "✓ All changes added successfully to staging area"
    echo "Staged files:"
    git diff --cached --name-only | sed 's/^/   - /'
  else
    echo "✗ Failed to add changes to staging area"
    exit 1
  fi

  echo "----------------------------------"
  echo "Preparing commit..."
  
  # Get the latest changed filename
  filename=$(git diff --cached --name-only | tail -n 1)
  if [ -z "$filename" ]; then
    filename="multiple files"
  fi
  
  # Define a commit message
  commit_message="This is for my ${os_type} git push or pull at $riqi. Last changed file: $filename"
  echo "Commit message: $commit_message"

  # Commit the changes
  echo "Committing changes..."
  git commit -m "$commit_message"
  if [ $? -eq 0 ]; then
    echo "✓ Changes committed successfully"
    echo "Commit hash: $(git rev-parse --short HEAD)"
  else
    echo "✗ Failed to commit changes"
    exit 1
  fi

  echo "----------------------------------"
  echo "Pushing changes to remote repository..."
  
  # Get current branch name
  current_branch=$(git branch --show-current)
  echo "Current branch: $current_branch"
  
  # Get remote info
  remote_url=$(git remote get-url origin 2>/dev/null || echo "No remote configured")
  echo "Remote URL: $remote_url"
  
  # Push the changes
  git push
  if [ $? -eq 0 ]; then
    echo "✓ Changes pushed successfully to $current_branch"
    echo "Remote commit: $(git rev-parse --short HEAD)"
    echo "📱 iOS/iPad git operation completed successfully!"
  else
    echo "✗ Failed to push changes"
    echo "This might be due to:"
    echo "  - Network connectivity issues (check WiFi/cellular)"
    echo "  - Authentication problems (check SSH keys/tokens)"
    echo "  - Remote repository conflicts"
    echo "  - iOS app permissions"
    exit 1
  fi
else
  echo "ℹ No changes detected in the repository"
  echo "Repository is up to date"
fi

echo "=================================="
echo "iOS Git script execution completed!"
echo "Device: $os_type"
echo "Final status:"
git status --short
echo "=================================="

# lex add file and for iPad ios
