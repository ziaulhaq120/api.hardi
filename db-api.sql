-- Enable UUID extension jika belum
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Tabel users untuk autentikasi
CREATE TABLE IF NOT EXISTS users (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    username VARCHAR(255) NOT NULL UNIQUE,
    role VARCHAR(50) DEFAULT 'user',
    api_key UUID DEFAULT uuid_generate_v4(),
    request_limit INTEGER DEFAULT 200,
    daily_limit INTEGER DEFAULT 200,
    requests_made INTEGER DEFAULT 0,
    daily_requests INTEGER DEFAULT 0,
    is_verified BOOLEAN DEFAULT false,
    verified_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP WITH TIME ZONE
);

-- Tabel admin_sessions untuk tracking sesi login
CREATE TABLE IF NOT EXISTS admin_sessions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    ip_address VARCHAR(45) NOT NULL,
    device_info TEXT,
    user_agent TEXT,
    last_activity TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(ip_address)
);

-- Tabel system_logs untuk semua aktivitas sistem
CREATE TABLE IF NOT EXISTS system_logs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    username VARCHAR(50) REFERENCES users(username),
    event_type VARCHAR(50) NOT NULL, -- 'LOGIN', 'LOGOUT', 'SIGNIN', 'API_REQUEST', 'ACCESS', 'ERROR'
    event_status VARCHAR(20) NOT NULL, -- 'SUCCESS', 'FAILED', 'BLOCKED'
    endpoint VARCHAR(255),
    method VARCHAR(10),
    status_code INTEGER,
    response_time INTEGER,
    ip_address VARCHAR(45) NOT NULL,
    device_info TEXT,
    user_agent TEXT,
    request_body TEXT,
    response_body TEXT,
    error_message TEXT,
    additional_info JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Tabel api_logs khusus untuk API requests
CREATE TABLE IF NOT EXISTS api_logs (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    username VARCHAR(50) REFERENCES users(username),
    endpoint VARCHAR(255) NOT NULL,
    method VARCHAR(10) NOT NULL,
    status_code INTEGER NOT NULL,
    response_time INTEGER NOT NULL,
    ip_address VARCHAR(45) NOT NULL,
    device_info TEXT,
    user_agent TEXT,
    request_body TEXT,
    response_body TEXT,
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert user admin default dengan API key
INSERT INTO users (
    username, 
    password, 
    role,
    allowed_ips,
    allowed_devices,
    api_key,
    request_limit,
    daily_limit
) 
VALUES (
    'hardi', 
    '1427', 
    'admin',
    ARRAY['*'],
    ARRAY['*'],
    'sk_test_' || encode(sha256(random()::text::bytea), 'hex'),
    1000000,  -- 1 juta request total
    10000     -- 10 ribu request per hari
)
ON CONFLICT (username) 
DO UPDATE SET 
    password = EXCLUDED.password,
    role = EXCLUDED.role,
    allowed_ips = EXCLUDED.allowed_ips,
    allowed_devices = EXCLUDED.allowed_devices,
    request_limit = EXCLUDED.request_limit,
    daily_limit = EXCLUDED.daily_limit;

-- Indexes untuk optimasi query
CREATE INDEX IF NOT EXISTS idx_system_logs_username ON system_logs(username);
CREATE INDEX IF NOT EXISTS idx_system_logs_event_type ON system_logs(event_type);
CREATE INDEX IF NOT EXISTS idx_system_logs_created_at ON system_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_system_logs_ip ON system_logs(ip_address);
CREATE INDEX IF NOT EXISTS idx_api_logs_created_at ON api_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_api_logs_username ON api_logs(username);
CREATE INDEX IF NOT EXISTS idx_admin_sessions_ip ON admin_sessions(ip_address);

-- Function untuk logging system events
CREATE OR REPLACE FUNCTION log_system_event(
    p_username VARCHAR(50),
    p_event_type VARCHAR(50),
    p_event_status VARCHAR(20),
    p_endpoint VARCHAR(255),
    p_method VARCHAR(10),
    p_status_code INTEGER,
    p_ip_address VARCHAR(45),
    p_device_info TEXT,
    p_user_agent TEXT,
    p_error_message TEXT DEFAULT NULL,
    p_additional_info JSONB DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_log_id UUID;
BEGIN
    INSERT INTO system_logs (
        username,
        event_type,
        event_status,
        endpoint,
        method,
        status_code,
        ip_address,
        device_info,
        user_agent,
        error_message,
        additional_info
    ) VALUES (
        p_username,
        p_event_type,
        p_event_status,
        p_endpoint,
        p_method,
        p_status_code,
        p_ip_address,
        p_device_info,
        p_user_agent,
        p_error_message,
        p_additional_info
    ) RETURNING id INTO v_log_id;

    RETURN v_log_id;
END;
$$ LANGUAGE plpgsql;

-- Function untuk reset daily requests
CREATE OR REPLACE FUNCTION reset_daily_requests()
RETURNS void AS $$
BEGIN
    UPDATE users 
    SET daily_requests = 0,
        last_reset_at = CURRENT_TIMESTAMP
    WHERE daily_requests > 0;
    
    -- Log reset event
    PERFORM log_system_event(
        'system',
        'DAILY_RESET',
        'SUCCESS',
        NULL,
        NULL,
        200,
        '127.0.0.1',
        'System',
        'System Scheduler',
        NULL,
        jsonb_build_object('reset_count', (SELECT COUNT(*) FROM users WHERE daily_requests > 0))
    );
END;
$$ LANGUAGE plpgsql;

-- Function untuk update request count
CREATE OR REPLACE FUNCTION update_request_count()
RETURNS TRIGGER AS $$
BEGIN
    -- Reset daily requests jika sudah lewat 24 jam
    IF (
        EXISTS (
            SELECT 1 FROM users 
            WHERE username = NEW.username 
            AND last_reset_at < CURRENT_TIMESTAMP - INTERVAL '24 hours'
        )
    ) THEN
        UPDATE users 
        SET daily_requests = 1,
            requests_made = requests_made + 1,
            last_reset_at = CURRENT_TIMESTAMP
        WHERE username = NEW.username;
    ELSE
        -- Update counters
        UPDATE users 
        SET daily_requests = daily_requests + 1,
            requests_made = requests_made + 1
        WHERE username = NEW.username;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger untuk update request count
CREATE TRIGGER trg_update_request_count
AFTER INSERT ON api_logs
FOR EACH ROW
EXECUTE FUNCTION update_request_count();

-- Create endpoints table
CREATE TABLE endpoints (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    base_url VARCHAR(255) NOT NULL,
    endpoint_path VARCHAR(255) NOT NULL,
    method VARCHAR(10) NOT NULL,
    version VARCHAR(10) DEFAULT 'v1',
    category VARCHAR(50),
    parameters JSONB DEFAULT '[]',
    options JSONB DEFAULT '[]',
    response_example JSONB,
    usage_cost INTEGER DEFAULT 1,
    rate_limit INTEGER DEFAULT 60, -- requests per minute
    is_active BOOLEAN DEFAULT true,
    requires_auth BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES users(id),
    updated_by UUID REFERENCES users(id)
);

-- Example of parameters JSONB structure:
-- [
--   {
--     "name": "query",
--     "type": "string",
--     "required": true,
--     "description": "Search query parameter",
--     "example": "john doe"
--   },
--   {
--     "name": "limit",
--     "type": "integer",
--     "required": false,
--     "default": 10,
--     "min": 1,
--     "max": 100,
--     "description": "Number of results to return"
--   }
-- ]

-- Example of options JSONB structure:
-- [
--   {
--     "name": "include_metadata",
--     "type": "boolean",
--     "default": false,
--     "description": "Include additional metadata in response"
--   },
--   {
--     "name": "format",
--     "type": "string",
--     "enum": ["json", "xml", "csv"],
--     "default": "json",
--     "description": "Response format"
--   }
-- ]

-- Create indexes for better query performance
CREATE INDEX idx_endpoints_name ON endpoints(name);
CREATE INDEX idx_endpoints_category ON endpoints(category);
CREATE INDEX idx_endpoints_created_at ON endpoints(created_at);
CREATE INDEX idx_endpoints_is_active ON endpoints(is_active);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger for auto-updating updated_at
CREATE TRIGGER update_endpoints_timestamp
    BEFORE UPDATE ON endpoints
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Insert example endpoint
INSERT INTO endpoints (
    name,
    description,
    base_url,
    endpoint_path,
    method,
    category,
    parameters,
    options,
    response_example,
    usage_cost
) VALUES (
    'Search API',
    'Search for items in the database with advanced filtering',
    'https://api.example.com',
    '/search',
    'GET',
    'search',
    '[
        {
            "name": "query",
            "type": "string",
            "required": true,
            "description": "Search query parameter",
            "example": "john doe"
        },
        {
            "name": "limit",
            "type": "integer",
            "required": false,
            "default": 10,
            "min": 1,
            "max": 100,
            "description": "Number of results to return"
        }
    ]',
    '[
        {
            "name": "include_metadata",
            "type": "boolean",
            "default": false,
            "description": "Include additional metadata in response"
        },
        {
            "name": "format",
            "type": "string",
            "enum": ["json", "xml", "csv"],
            "default": "json",
            "description": "Response format"
        }
    ]',
    '{
        "status": "success",
        "data": [
            {
                "id": "123",
                "name": "Example Item",
                "description": "This is an example item"
            }
        ],
        "metadata": {
            "total": 1,
            "page": 1
        }
    }',
    2
);