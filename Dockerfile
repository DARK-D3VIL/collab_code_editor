# Alternative: Use full Ruby image which has better compatibility
FROM ruby:3.2.0

# Install additional dependencies including CMake for rugged
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    cmake \
    pkg-config \
    libssl-dev \
    libpq-dev \
    libvips42 \
    postgresql-client \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 18
ARG NODE_VERSION=18.20.8
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs

# Install Yarn
ARG YARN_VERSION=1.22.22
RUN npm install -g yarn@$YARN_VERSION

# Set working directory
WORKDIR /app

# Set development environment
ENV RAILS_ENV=development \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_SILENCE_ROOT_WARNING=1

# Copy dependency files
COPY Gemfile Gemfile.lock ./

# Install gems without forcing system libraries (let it compile its own libgit2)
RUN bundle config set --local path '/usr/local/bundle' && \
    bundle config set --local deployment 'false' && \
    bundle install --jobs 4 --retry 3 && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

# Copy package files if they exist
COPY package*.json yarn.lock* ./
RUN if [ -f package.json ]; then \
        if [ -f yarn.lock ]; then \
            yarn install --frozen-lockfile; \
        else \
            npm install; \
        fi \
    fi

# Copy the rest of the application
COPY . .

# Create necessary directories and set permissions
RUN mkdir -p tmp/pids tmp/cache tmp/sockets log storage && \
    if [ -f bin/rails ]; then chmod +x bin/rails; fi && \
    if [ -f bin/docker-entrypoint ]; then chmod +x bin/docker-entrypoint; fi

# Expose port
EXPOSE 3000

# Default command for development
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]