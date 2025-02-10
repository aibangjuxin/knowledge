date -d "2 days 7 hours ago" +"%Y-%m-%d %H:%M:%S"

# Get the current time
current_time=$(date +"%Y-%m-%d %H:%M:%S")
echo "Current time: $current_time"

# Subtract 2 days
new_time=$(date -d "2 days ago" +"%Y-%m-%d %H:%M:%S")
echo "Time 2 days ago: $new_time"



