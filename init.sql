-- init.sql
-- Create test database
CREATE DATABASE myapp_test;

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE myapp_development TO postgres;
GRANT ALL PRIVILEGES ON DATABASE myapp_test TO postgres;
