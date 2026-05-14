# Sidecar Profiling Strategy

Since your environment uses Init Containers and likely minimal base images (like Distroless or Alpine) for the Java app, you probably don't have `jcmd`, `jmap`, or `bash` inside the main container.

**The Sidecar Pattern** allows you to attach a full-featured JDK container to your running Pod to execute these tools.

## Method 1: Ephemeral Debug Container (Recommended for K8s 1.23+)
This is the modern, easiest way.

```bash
kubectl debug -it <your-pod-name> \
  --image=openjdk:17-jdk-slim \
  --target=<your-java-container-name> \
  --profile=general
```

*   `--target`: This is crucial. It makes the sidecar share the **Process Namespace** with your Java container.
*   `--image`: Uses a Docker Hub image containing `jcmd` (see [Docker Hub Tools](./docker-hub-tools.md)).

### Troubleshooting Connection
Once inside the sidecar, you might run `jcmd` and see:
> `com.sun.tools.attach.AttachNotSupportedException: Unable to open socket file /proc/1/root/tmp/.java_pid1`

**Why?**
1.  **PID Mismatch**: In the sidecar, your Java process might not be PID 1. Run `ps -ef` to find the real PID (e.g., PID 50).
2.  **User Mismatch**: Your Java app runs as `appuser` (UID 1000), but sidecar runs as `root` (UID 0). The JVM requires the *same user* to connect.
3.  **File System Isolation**: The JVM socket is in the *target container's* `/tmp`, not the sidecar's `/tmp`.

**The Fix Script**:
Run this inside the sidecar:

```bash
# 1. Find the Java PID
JAVA_PID=$(ps -ef | grep java | grep -v grep | awk '{print $2}')

# 2. Create a symlink to the target container's /tmp socket
# Note: /proc/$JAVA_PID/root is a magic link to the target's filesystem
ln -s /proc/$JAVA_PID/root/tmp/.java_pid$JAVA_PID /tmp/.java_pid$JAVA_PID

# 3. Switch to the target user (assuming UID 1000) and run jcmd
# If you don't know the UID, check /proc/$JAVA_PID/status
su -s /bin/bash 1000 -c "jcmd $JAVA_PID VM.native_memory summary"
```

## Method 2: Permanent Sidecar (Deployment Modification)
If you want to monitor continuously, add a sidecar to your Deployment YAML.

```yaml
spec:
  shareProcessNamespace: true  # <--- CRITICAL: Allows containers to see each other's processes
  containers:
    - name: java-app
      image: my-app:latest
      # ...
    
    - name: profiler-sidecar
      image: openjdk:17-jdk-slim
      command: ["/bin/sh", "-c", "sleep infinity"]
      securityContext:
        runAsUser: 0 # Root is needed to create the symlink initially
```

## Summary of Sidecar Workflow
1.  **Inject**: Use `kubectl debug` or edit Deployment.
2.  **Locate**: Find the Java PID (`ps -ef`).
3.  **Bridge**: Link the socket (`ln -s ...`).
4.  **Execute**: Run `jcmd` as the correct user (`su -s ...`).
