# Base stage for installing dependencies
FROM node:20-buster as installer

# Copy source code
COPY . /juice-shop

# Set the working directory
WORKDIR /juice-shop

# Install global tools and dependencies
RUN npm i -g typescript ts-node && \
    npm install --omit=dev --unsafe-perm && \
    npm dedupe --omit=dev

# Clean up unnecessary directories
RUN rm -rf frontend/node_modules frontend/.angular frontend/src/assets

# Prepare application directories
RUN mkdir logs && \
    chown -R 65532 logs && \
    chgrp -R 0 ftp/ frontend/dist/ logs/ data/ i18n/ && \
    chmod -R g=u ftp/ frontend/dist/ logs/ data/ i18n/

# Remove sensitive or unnecessary files
RUN rm data/chatbot/botDefaultTrainingData.json || true && \
    rm ftp/legal.md || true && \
    rm i18n/*.json || true

# Add CycloneDX tool for generating SBOM (Software Bill of Materials)
ARG CYCLONEDX_NPM_VERSION=latest
RUN npm install -g @cyclonedx/cyclonedx-npm@$CYCLONEDX_NPM_VERSION && \
    npm run sbom

# Separate stage to handle libxmljs build errors
FROM node:20-buster as libxmljs-builder
WORKDIR /juice-shop

# Install build tools
RUN apt-get update && apt-get install -y build-essential python3

# Copy dependencies from the installer stage
COPY --from=installer /juice-shop/node_modules ./node_modules

# Rebuild libxmljs to fix startup issues
RUN rm -rf node_modules/libxmljs/build && \
    cd node_modules/libxmljs && \
    npm run build

# Final stage for production
FROM gcr.io/distroless/nodejs20-debian11

# Build-time metadata
ARG BUILD_DATE
ARG VCS_REF
LABEL maintainer="Bjoern Kimminich <bjoern.kimminich@owasp.org>" \
    org.opencontainers.image.title="OWASP Juice Shop" \
    org.opencontainers.image.description="Probably the most modern and sophisticated insecure web application" \
    org.opencontainers.image.authors="Bjoern Kimminich <bjoern.kimminich@owasp.org>" \
    org.opencontainers.image.vendor="Open Worldwide Application Security Project" \
    org.opencontainers.image.documentation="https://help.owasp-juice.shop" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.version="17.1.1" \
    org.opencontainers.image.url="https://owasp-juice.shop" \
    org.opencontainers.image.source="https://github.com/juice-shop/juice-shop" \
    org.opencontainers.image.revision=$VCS_REF \
    org.opencontainers.image.created=$BUILD_DATE

# Set working directory
WORKDIR /juice-shop

# Copy application files and rebuilt libxmljs
COPY --from=installer --chown=65532:0 /juice-shop .
COPY --chown=65532:0 --from=libxmljs-builder /juice-shop/node_modules/libxmljs ./node_modules/libxmljs

# Use a non-root user
USER 65532

# Expose the application port
EXPOSE 3000

# Set the default command
CMD ["/juice-shop/build/app.js"]
