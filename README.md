# 🚀 Collaborative Code Editor

[![Ruby on Rails](https://img.shields.io/badge/Rails-7.2+-red.svg)](https://rubyonrails.org/)
[![Python](https://img.shields.io/badge/Python-3.8+-blue.svg)](https://www.python.org/)
[![Docker](https://img.shields.io/badge/Docker-Supported-blue.svg)](https://www.docker.com/)

A real-time collaborative code editor with AI-powered completion features, designed for seamless team development experiences.

## ✨ Features

### 🔥 Real-time Collaboration
- **Live Multi-User Editing**: Multiple developers can edit the same file simultaneously
- **Live Cursor Tracking**: See where your teammates are working in real-time
- **Instant Synchronization**: Changes appear instantly across all connected clients
- **Conflict Resolution**: Smart handling of simultaneous edits

### 🤖 AI-Powered Code Completion
- **Intelligent Suggestions**: Context-aware code completions powered by transformer models
- **Personalized Models**: AI learns from your coding patterns for better suggestions
- **Multiple Completion Types**: Variable names, function calls, code blocks, and documentation
- **Confidence Scoring**: AI suggestions come with confidence ratings

### 💬 Integrated Communication
- **Real-time Chat**: Built-in team chat for seamless communication
- **Typing Indicators**: See when teammates are actively coding
- **User Presence**: Know who's online and working on what
- **Notification System**: Stay updated on important changes

### 🔐 Secure & Scalable
- **GitHub OAuth**: Seamless authentication with your GitHub account
- **Project Permissions**: Role-based access control for teams
- **Git Integration**: Built-in version control with commit management
- **WebSocket Architecture**: Scalable real-time communication

## 🏗️ Architecture

This project consists of two main components:

1. **Main Application** (Ruby on Rails): Handles user management, real-time collaboration, and UI
2. **[AI Microservice](https://github.com/DARK-D3VIL/code_completion_microservice)** (Python/FastAPI): Provides intelligent code completion

```mermaid
graph TB
    A[Web Client] -->|WebSocket| B[Rails App]
    A -->|HTTP| B
    B -->|Redis PubSub| C[ActionCable]
    B -->|HTTP API| D[AI Microservice]
    B -->|SQL| E[(PostgreSQL)]
    B -->|Cache| F[(Redis)]
    D -->|ML Models| G[PyTorch/Transformers]
```

## 🛠️ Tech Stack

### Frontend
- **Monaco Editor** - Professional code editing experience
- **Bootstrap 5** - Modern, responsive UI framework
- **Action Cable** - Real-time WebSocket connections
- **Stimulus** - Lightweight JavaScript framework

### Backend
- **Ruby on Rails 7.2+** - Main application framework
- **PostgreSQL** - Primary database
- **Redis** - Caching and real-time messaging
- **Sidekiq** - Background job processing

### AI Service
- **FastAPI** - High-performance Python API framework
- **PyTorch** - Machine learning framework
- **Transformers** - Pre-trained language models
- **PEFT** - Parameter-efficient fine-tuning

### DevOps
- **Docker & Docker Compose** - Containerized deployment
- **GitHub Actions** - CI/CD pipeline
- **Heroku Ready** - One-click deployment

## 🚀 Quick Start

### Prerequisites
- Ruby 3.0+
- Node.js 18+
- PostgreSQL 12+
- Redis 6+
- Python 3.8+ (for AI service)
- Docker (optional)

### 1. Clone the Repository
```bash
git clone https://github.com/yourusername/collab-editor.git
cd collab-editor
```

### 2. Environment Setup
```bash
# Copy environment template
cp .env.example .env

# Edit .env with your configuration
nano .env
```

Required environment variables:
```env
DATABASE_URL=postgresql://username:password@localhost/collab_editor_development
REDIS_URL=redis://localhost:6379/1
GITHUB_CLIENT_ID=your_github_oauth_app_id
GITHUB_CLIENT_SECRET=your_github_oauth_app_secret
SECRET_KEY_BASE=your_secret_key
AI_SERVICE_URL=http://localhost:8000
```

### 3. Installation
```bash
# Install Ruby dependencies
bundle install

# Install JavaScript dependencies
yarn install

# Setup database
rails db:create db:migrate db:seed

# Build assets
yarn build:css
yarn build
```

### 4. Start Services

#### Option A: Manual Setup
```bash
# Terminal 1: Start Redis
redis-server

# Terminal 2: Start Rails server
rails server

# Terminal 3: Start background jobs
bundle exec sidekiq

# Terminal 4: Start AI service (see AI service setup below)
cd ../code_completion_microservice
python -m uvicorn main:app --reload --port 8000
```

#### Option B: Docker Setup (Recommended)
```bash
# Development environment
docker-compose up --build

# Setup database
docker-compose exec web rails db:create db:migrate
```

### 5. AI Service Setup

Clone and setup the AI microservice:

```bash
# Clone the AI service repository
git clone https://github.com/DARK-D3VIL/code_completion_microservice.git
cd code_completion_microservice

# Install Python dependencies
pip install -r requirements.txt

# Start the AI service
uvicorn main:app --reload --port 8000
```

Visit `http://localhost:3000` to start coding collaboratively!

## 📚 Usage

### Creating Your First Project
1. **Sign Up/Login** with GitHub OAuth
2. **Create New Project** - Set name and visibility
3. **Invite Collaborators** - Add team members by email/username
4. **Start Coding** - Create files and start collaborative editing

### Keyboard Shortcuts
| Shortcut | Action |
|----------|--------|
| `Ctrl+S` | Save current file |
| `Ctrl+Enter` | Trigger AI completion |
| `Ctrl+Alt+A` | Toggle AI completion on/off |
| `Ctrl+Shift+C` | Toggle chat sidebar |
| `Tab` | Accept AI suggestion |
| `Esc` | Dismiss AI popup |
| `↑↓` | Navigate AI suggestions |

### AI Completion Features
- **Auto-trigger**: AI suggestions appear as you type
- **Manual trigger**: Use `Ctrl+Enter` for on-demand completions
- **Smart filtering**: Suggestions adapt to your coding style
- **Confidence levels**: See how confident the AI is about each suggestion

## 🔧 Configuration

### GitHub OAuth Setup
1. Go to [GitHub Developer Settings](https://github.com/settings/applications/new)
2. Create a new OAuth App with these settings:
   - **Application name**: Your app name
   - **Homepage URL**: `http://localhost:3000`
   - **Callback URL**: `http://localhost:3000/users/auth/github/callback`
3. Copy the Client ID and Secret to your `.env` file

### Production Deployment

#### Heroku
```bash
# Install Heroku CLI and login
heroku create your-app-name

# Add required addons
heroku addons:create heroku-postgresql:mini
heroku addons:create heroku-redis:mini

# Set environment variables
heroku config:set GITHUB_CLIENT_ID=your_client_id
heroku config:set GITHUB_CLIENT_SECRET=your_client_secret
heroku config:set RAILS_MASTER_KEY=your_master_key

# Deploy
git push heroku main
heroku run rails db:migrate
```

#### Docker Production
```bash
# Build and deploy
docker-compose -f docker-compose.prod.yml up -d

# Initialize database
docker-compose -f docker-compose.prod.yml exec web rails db:migrate
```

## 📁 Project Structure

```
├── app/
│   ├── channels/          # WebSocket channels for real-time features
│   ├── controllers/       # API and web controllers
│   ├── models/           # Data models and business logic
│   ├── views/            # ERB templates and layouts
│   └── javascript/       # Frontend JavaScript and Stimulus controllers
├── config/               # Rails configuration
├── db/                   # Database migrations and schema
├── docker-compose.yml    # Development Docker setup
├── docker-compose.prod.yml # Production Docker setup
├── Gemfile              # Ruby dependencies
├── package.json         # JavaScript dependencies
└── README.md           # This file
```

## 🧪 Development

### Running Tests
```bash
# Ruby tests
rails test

# System tests with browser
rails test:system

# JavaScript tests
yarn test
```

### Code Quality
```bash
# Ruby linting
rubocop

# Auto-fix Ruby issues
rubocop -a

# JavaScript linting
eslint app/javascript/
```

### Development Commands
```bash
# Generate new migration
rails generate migration AddFeatureToModel feature:string

# Create new controller
rails generate controller FeatureName

# Rails console
rails console

# Check routes
rails routes
```

## 🐳 Docker Commands

```bash
# Development
docker-compose up                    # Start all services
docker-compose down                  # Stop all services
docker-compose logs web              # View app logs
docker-compose exec web rails console # Rails console

# Production
docker-compose -f docker-compose.prod.yml up -d
docker-compose -f docker-compose.prod.yml logs -f web
```

## 🔍 API Documentation

### WebSocket Events
| Event | Description | Payload |
|-------|-------------|---------|
| `content_change` | Real-time code edits | `{content, position, userId}` |
| `cursor_change` | User cursor position | `{line, column, userId}` |
| `user_joined` | User joined session | `{userId, username}` |
| `user_left` | User left session | `{userId}` |
| `chat_message` | Team chat message | `{message, userId, timestamp}` |

### REST API Endpoints
| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/projects` | List user projects |
| `POST` | `/api/projects` | Create new project |
| `GET` | `/api/projects/:id/files` | List project files |
| `PUT` | `/api/projects/:id/files/*path` | Save file content |
| `POST` | `/api/ai/completions` | Get AI code suggestions |

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feature/amazing-feature`
3. **Commit** your changes: `git commit -m 'Add amazing feature'`
4. **Push** to the branch: `git push origin feature/amazing-feature`
5. **Open** a Pull Request

### Development Guidelines
- Follow Ruby Style Guide and use RuboCop
- Write tests for new features
- Update documentation for API changes
- Use meaningful commit messages

## 🐛 Troubleshooting

<details>
<summary><strong>WebSocket connection issues</strong></summary>

- Ensure Redis is running: `redis-cli ping`
- Check Action Cable configuration in `config/cable.yml`
- Verify firewall settings allow WebSocket connections
- Check browser console for connection errors
</details>

<details>
<summary><strong>AI completion not working</strong></summary>

- Verify AI service is running: `curl http://localhost:8000/health`
- Check AI service URL in environment variables
- Ensure Python dependencies are installed
- Check AI service logs for errors
</details>

<details>
<summary><strong>GitHub OAuth issues</strong></summary>

- Verify OAuth app configuration on GitHub
- Check callback URL matches your setup
- Ensure Client ID and Secret are set correctly
- Clear browser cookies and try again
</details>

<details>
<summary><strong>Database connection errors</strong></summary>

- Check PostgreSQL is running: `pg_isready`
- Verify database credentials in `DATABASE_URL`
- Run migrations: `rails db:migrate`
- Check database permissions
</details>

## 📊 Performance

- **Real-time Latency**: < 50ms for collaborative edits
- **AI Response Time**: < 2s for code completions
- **Concurrent Users**: Supports 100+ users per project
- **WebSocket Scaling**: Redis-backed horizontal scaling

## 🔒 Security

- **Authentication**: GitHub OAuth 2.0
- **Authorization**: Role-based project access
- **Data Encryption**: HTTPS/WSS in production
- **Input Validation**: Comprehensive sanitization
- **Rate Limiting**: API and WebSocket protection

## 📈 Monitoring

- **Health Checks**: `/up` endpoint for monitoring
- **Application Metrics**: Built-in Rails instrumentation
- **Error Tracking**: Exception notifications
- **Performance Monitoring**: Database query optimization

## 🙏 Acknowledgments

- [Monaco Editor](https://microsoft.github.io/monaco-editor/) - Amazing code editing experience
- [Action Cable](https://guides.rubyonrails.org/action_cable_overview.html) - Real-time WebSocket functionality
- [Hugging Face Transformers](https://huggingface.co/transformers/) - Pre-trained language models
- [Bootstrap](https://getbootstrap.com/) - Beautiful UI components

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Related Projects

- **[AI Code Completion Service](https://github.com/DARK-D3VIL/code_completion_microservice)** - The intelligent code completion microservice
- **[Monaco Editor](https://github.com/microsoft/monaco-editor)** - VS Code's editor for the web
- **[Action Cable](https://github.com/rails/actioncable)** - Real-time WebSocket framework

---

<div align="center">

**[🌟 Star this repo](https://github.com/yourusername/collab-editor) • [🐛 Report Bug](https://github.com/yourusername/collab-editor/issues) • [💡 Request Feature](https://github.com/yourusername/collab-editor/issues)**

Made with ❤️ by developers, for developers

</div>