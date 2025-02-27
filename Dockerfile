FROM ubuntu:22.04

# Install dependencies
RUN apt update && apt install -y curl 

# Install Ollama
RUN curl -fsSL https://ollama.com/install.sh | sh

# Expose the Ollama port
EXPOSE 11434

# Run Ollama on startup
CMD ["ollama", "serve"]
