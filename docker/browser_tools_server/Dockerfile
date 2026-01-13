FROM node:18-alpine

# Install necessary dependencies for browser tools
RUN apk add --no-cache \
    chromium \
    nss \
    freetype \
    freetype-dev \
    harfbuzz \
    ca-certificates \
    ttf-freefont

# Set environment variables for Puppeteer to use installed Chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

# Create app directory
WORKDIR /app

# Install the browser-tools-server package globally
RUN npm install -g @agentdeskai/browser-tools-server@1.2.0

# Expose port 3025
EXPOSE 3025

# Start the browser-tools-server
CMD ["npx", "@agentdeskai/browser-tools-server@1.2.0"]
