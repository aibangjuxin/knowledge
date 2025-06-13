#!/bin/bash

# Replace the following variables with your own values
MIG_NAME="your-mig-name"
REGION="europe-west2"
NEW_SIZE=4   # Number of instances after increase
OLD_MIN=2
OLD_MAX=4
TARGET_CPU_UTIL=0.9

# Step 1: Disable autoscaling (if it exists)
echo "Disabling autoscaler..."
gcloud compute instance-groups managed set-autoscaling "$MIG_NAME" \
  --region="$REGION" \
  --min-num-replicas="$OLD_MIN" \
  --max-num-replicas="$OLD_MAX" \
  --target-cpu-utilization="$TARGET_CPU_UTIL" \
  --cool-down-period="180s" \
  --mode=off

# Step 2: Execute Resize operation
echo "Resizing MIG to $NEW_SIZE instances..."
gcloud compute instance-groups managed resize "$MIG_NAME" \
  --region="$REGION" \
  --size="$NEW_SIZE"

# Step 3: Wait a few seconds, observe instance distribution
echo "Sleeping 60s to wait for instance creation..."
sleep 80

# Step 4: Display instance distribution (zone distribution)
echo "Listing instance zone distribution:"
gcloud compute instance-groups managed list-instances "$MIG_NAME" \
  --region="$REGION" \
  --format="table(instance, zone, status)"

# Step 5: Restore autoscaling (optional)
read -p "Do you want to re-enable autoscaler with previous policy (min=$OLD_MIN, max=$OLD_MAX)? (y/n): " confirm
if [[ "$confirm" == "y" ]]; then
  echo "Restoring autoscaler..."
  gcloud compute instance-groups managed set-autoscaling "$MIG_NAME" \
    --region="$REGION" \
    --min-num-replicas="$OLD_MIN" \
    --max-num-replicas="$OLD_MAX" \
    --target-cpu-utilization="$TARGET_CPU_UTIL" \
    --cool-down-period="180s"
else
  echo "Autoscaler not restored. Done."
fi