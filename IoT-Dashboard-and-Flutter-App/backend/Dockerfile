# -----------------------------
# Base image: Node.js LTS
# -----------------------------
FROM node:18-alpine

# -----------------------------
# Set working directory
# -----------------------------
WORKDIR /app

# -----------------------------
# Copy package files
# -----------------------------
COPY package*.json ./

# -----------------------------
# Install dependencies
# -----------------------------
RUN npm install --production

# -----------------------------
# Copy source code
# -----------------------------
COPY . .

# -----------------------------
# Expose port
# -----------------------------
EXPOSE 8080

# -----------------------------
# Start backend server
# -----------------------------
CMD ["node", "server.js"]
