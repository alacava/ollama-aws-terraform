FROM ubuntu:latest

# Install dependencies
RUN apt update && apt install -y curl

# Install Ollama
RUN curl -fsSL https://ollama.com/install.sh | sh

# Expose Ollama’s default port
EXPOSE 11434

# Start Ollama when the container runs
CMD ["ollama", "serve"]
