#!/bin/bash
# setup-docker.sh

echo "🐳 Setting up Docker environment for Rails application..."

# Check if we're setting up for production or development
ENVIRONMENT=${1:-development}

if [ "$ENVIRONMENT" = "production" ]; then
    echo "🚀 Setting up PRODUCTION environment..."
    COMPOSE_FILE="docker-compose.prod.yml"
    ENV_FILE=".env.production"
else
    echo "🛠️  Setting up DEVELOPMENT environment..."
    COMPOSE_FILE="docker-compose.yml"
    ENV_FILE=".env"
fi

# Create .env file if it doesn't exist
if [ ! -f $ENV_FILE ]; then
    echo "📝 Creating $ENV_FILE file from .env.example..."
    cp .env.example $ENV_FILE
    echo "⚠️  Please update $ENV_FILE file with your actual values before running docker-compose up"
fi

# Create docker entrypoint script if it doesn't exist
if [ ! -f bin/docker-entrypoint ]; then
    echo "📝 Creating docker entrypoint script..."
    mkdir -p bin
    cat > bin/docker-entrypoint << 'EOF'
#!/bin/bash -e

# If running the rails server then create or migrate existing database
if [ "${1}" == "./bin/rails" ] && [ "${2}" == "server" ]; then
  ./bin/rails db:prepare
fi

exec "${@}"
EOF
    chmod +x bin/docker-entrypoint
fi

# Create init.sql for PostgreSQL setup
echo "📊 Creating PostgreSQL initialization script..."
cat > init.sql << 'EOF'
-- init.sql
-- Create test database
CREATE DATABASE myapp_test;

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE myapp_development TO postgres;
GRANT ALL PRIVILEGES ON DATABASE myapp_test TO postgres;
EOF

if [ "$ENVIRONMENT" = "production" ]; then
    echo "🔨 Building production Docker images..."
    docker-compose -f $COMPOSE_FILE build

    echo "🚀 Starting production services..."
    docker-compose -f $COMPOSE_FILE up -d db redis

    echo "⏳ Waiting for database to be ready..."
    sleep 15

    echo "📦 Setting up production database..."
    docker-compose -f $COMPOSE_FILE run --rm web ./bin/rails db:prepare

    echo "🎉 Production Docker setup complete!"
    echo ""
    echo "To start the production application:"
    echo "  docker-compose -f docker-compose.prod.yml up -d"
    echo ""
    echo "To view logs:"
    echo "  docker-compose -f docker-compose.prod.yml logs -f web"
    echo ""
    echo "To stop services:"
    echo "  docker-compose -f docker-compose.prod.yml down"

else
    # Development setup
    echo "🔨 Building development Docker images..."
    docker-compose build

    echo "🚀 Starting development services..."
    docker-compose up -d db redis

    echo "⏳ Waiting for database to be ready..."
    sleep 10

    echo "📦 Installing dependencies and setting up database..."
    docker-compose run --rm web bundle install
    
    # Only install npm/yarn if package.json exists
    if [ -f package.json ]; then
        if [ -f yarn.lock ]; then
            docker-compose run --rm web yarn install
        else
            docker-compose run --rm web npm install
        fi
    fi
    
    docker-compose run --rm web rails db:create db:migrate

    echo "🎉 Development Docker setup complete!"
    echo ""
    echo "To start the application:"
    echo "  docker-compose up"
    echo ""
    echo "To run commands:"
    echo "  docker-compose exec web rails console"
    echo "  docker-compose exec web rails db:migrate"
    echo "  docker-compose exec web bundle install"
    echo ""
    echo "To view logs:"
    echo "  docker-compose logs -f web"
    echo "  docker-compose logs -f sidekiq"
    echo ""
    echo "To stop services:"
    echo "  docker-compose down"
fi