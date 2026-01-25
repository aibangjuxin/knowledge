# Use a lightweight Python base image
FROM python:3.9-slim

# Install dnsutils (bind9-host) for 'dig' command
RUN apt-get update && \
    apt-get install -y dnsutils && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy necessary files
COPY verify-pub-priv-ip-glm-ipv6.sh .
COPY dns_server.py .
COPY Intra-verify-domain.html .

# Make script executable
RUN chmod +x verify-pub-priv-ip-glm-ipv6.sh

# Expose the port
EXPOSE 8000

# Run the server
CMD ["python3", "dns_server.py"]
