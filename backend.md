# TrackIt Backend

A comprehensive REST API for user management, authentication, and metric tracking with admin dashboard.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start Guide](#quick-start-guide)
- [Installation](#installation)
- [Configuration](#configuration)
- [Project Structure](#project-structure)
- [Database](#database)
- [Running the Server](#running-the-server)
- [API Documentation](#api-documentation)
- [Admin Dashboard](#admin-dashboard)
- [Authentication System](#authentication-system)
- [API Endpoints](#api-endpoints)
- [Error Handling](#error-handling)
- [Hardware Monitoring](#hardware-monitoring)
- [Security Features](#security-features)
- [Email Service](#email-service)
- [Development](#development)
- [Deployment Considerations](#deployment-considerations)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## Prerequisites

- Node.js (v18 or later)
- npm (v8 or later)
- PostgreSQL (v12 or later)
- lm-sensors (for hardware monitoring on Linux)

## Installation

1. Clone the repository:
```bash
git clone https://github.com/apptrackit/trackit-backend
cd trackit-backend
```

2. Install dependencies:
```bash
npm install
```

## Quick Start Guide

1. **Clone and Install**:
   ```bash
   git clone https://github.com/apptrackit/trackit-backend
   cd trackit-backend
   npm install
   ```

2. **Set up Environment**:
   ```bash
   touch .env
   ```

3. **Set up Database**:
   ```bash
   # Create PostgreSQL database
   createdb trackitdb
   
   # Tables will be auto-created on first run
   ```

4. **Start the Server**:
   ```bash
   npm run dev  # For development
   # OR
   npm start    # For production
   ```

5. **Access Services**:
   - API Server: `http://localhost:3000`
   - Admin Dashboard: `http://localhost:3000/`
   - API Documentation: `http://localhost:3000/api-docs` (dev mode only)

## Configuration

Create a `.env` file in the root directory:

```env
# Database Configuration
DATABASE_URL=postgres://username:password@localhost:5432/database_name

# JWT Security
JWT_SECRET=your_secure_jwt_secret_here

# Server Configuration
PORT=3000
HOST=0.0.0.0

# Security Settings
SALT=10  # Number of salt rounds for password hashing

# Admin Account
ADMIN_USERNAME=admin
ADMIN_PASSWORD=admin

# Environment
NODE_ENV=development

# Email Configuration
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_SECURE=false
EMAIL_USER=your_email@gmail.com
EMAIL_PASS=your_app_password_here
EMAIL_FROM=TrackIt <your_email@gmail.com>
EMAIL_TLS_REJECT_UNAUTHORIZED=true
```

## Project Structure

```
trackit-backend/
│
├── app.js                    # Main application entry point
├── auth.js                   # Authentication middleware
├── database.js               # Database connection and setup
├── package.json              # Project dependencies and scripts
├── package-lock.json         # Dependency lock file
├── .env                      # Environment variables (create from template)
├── .gitignore               # Git ignore rules
│
├── controllers/              # Business logic controllers
│   ├── adminController.js    # Admin operations
│   ├── authController.js     # Authentication logic
│   ├── metricController.js   # Metric tracking logic
│   └── userController.js     # User management logic
│
├── routes/                   # API route definitions
│   ├── admin.js             # Admin routes
│   ├── auth.js              # Authentication routes
│   ├── metrics.js           # Metric tracking routes
│   └── users.js             # User management routes
│
├── services/                 # Business logic services
│   ├── authService.js       # Authentication service
│   ├── emailService.js      # Email sending service
│   ├── hardwareService.js   # Hardware monitoring service
│   ├── metricService.js     # Metric data service
│   ├── sessionService.js    # Session management service
│   └── userService.js       # User data service
│
├── utils/                    # Utility modules
│   ├── logger.js            # Winston logging configuration
│   └── swagger.js           # Swagger API documentation setup
│
├── public/                   # Static files and admin dashboard
│   ├── index.html           # Admin login page
│   ├── admin-dashboard.html # Admin dashboard
│   ├── css/
│   │   ├── index.css        # Login page styles
│   │   └── admin-dashboard.css # Dashboard styles
│   └── scripts/
│       ├── admin-dashboard.js   # Dashboard logic
│       ├── clipboard-helper.js  # Clipboard utility functions
│       └── index.js            # Login page logic
│
└── logs/                     # Application logs (auto-created)
    ├── combined.log         # All log levels
    └── error.log           # Error logs only
```

## Logging

The application uses Winston for comprehensive logging:

- **Console Output**: Colorized, timestamped logs for development
- **File Logging**: 
  - `logs/error.log` - Error level logs only
  - `logs/combined.log` - All log levels
- **Log Format**: Structured JSON with timestamps and service tags
- **Log Levels**: error, warn, info, debug

Log files are automatically created in the `logs/` directory.

## Database

The application uses PostgreSQL with the following tables:

### Users Table
- `id`: Serial primary key
- `username`: Unique username (TEXT)
- `email`: User's email (TEXT)
- `password`: Hashed password (TEXT)
- `created_at`: Account creation timestamp (TIMESTAMP)

### Sessions Table
- `id`: Serial primary key
- `user_id`: Reference to users table (INTEGER)
- `device_id`: Unique device identifier (TEXT)
- `access_token`: JWT access token (TEXT)
- `refresh_token`: Refresh token (TEXT)
- `access_token_expires_at`: Access token expiration (TIMESTAMP)
- `refresh_token_expires_at`: Refresh token expiration (TIMESTAMP)
- `created_at`: Session creation timestamp (TIMESTAMP)
- `last_refresh_at`: Last token refresh timestamp (TIMESTAMP)
- `last_check_at`: Last session check timestamp (TIMESTAMP)
- `refresh_count`: Number of token refreshes (INTEGER)

### Admin Sessions Table
- `id`: Serial primary key
- `token`: Bearer token for admin authentication (TEXT)
- `username`: Admin username (TEXT)
- `created_at`: Session creation timestamp (TIMESTAMP)
- `expires_at`: Token expiration timestamp (TIMESTAMP)

### Metric Types Table
- `id`: Serial primary key
- `name`: Name of the metric type (VARCHAR, UNIQUE)
- `unit`: Unit for this type (VARCHAR)
- `icon_name`: Icon name for this type (VARCHAR)
- `is_default`: Indicates if it's a system-defined default type (BOOLEAN)
- `user_id`: Reference to user who created custom type (INTEGER, nullable)
- `category`: Category of the metric type (VARCHAR)

### Metric Entries Table
- `id`: Serial primary key
- `user_id`: Reference to users table (INTEGER)
- `metric_type_id`: Reference to metric_types table (INTEGER)
- `value`: Metric value (BIGINT)
- `date`: Date of the metric entry (DATE)
- `is_apple_health`: Is from Apple Health (BOOLEAN)

**Default Metric Types**: The system automatically seeds 12 default body measurement metric types (Weight, Height, Body Fat, Waist, Bicep, Chest, Thigh, Shoulder, Glutes, Calf, Neck, Forearm).

## Database Setup

1. Install PostgreSQL on your system
2. Create a database:
```sql
CREATE DATABASE trackitdb;
```

3. Create a user (optional):
```sql
CREATE USER dev WITH PASSWORD 'dev';
GRANT ALL PRIVILEGES ON DATABASE trackitdb TO dev;
```

4. Update your `.env` file with the correct DATABASE_URL

The database tables and default data are automatically created when the application starts.

## Running the Server

Start the server:
```bash
npm start
```

For development with auto-restart:
```bash
npm run dev
```

The server will run on `http://localhost:3000` by default.

## API Documentation

Interactive API documentation is available via Swagger UI when running in development mode:
- **Swagger UI**: `http://localhost:3000/api-docs`

The Swagger documentation provides:
- Complete API endpoint reference
- Request/response schemas
- Authentication examples
- Interactive testing interface

*Note: Swagger UI is only available in development mode for security reasons.*

## Admin Dashboard

Access the admin dashboard at `http://localhost:3000/` with your admin credentials.

**Features:**
- User management (create, edit, delete users)
- Real-time hardware monitoring (CPU temperature, fan speed, uptime)
- User activity statistics with customizable timeframes
- Active session management
- Search and sort functionality
- Responsive design for mobile and desktop

## Authentication System

The system uses multiple authentication mechanisms:

### User Authentication
- **JWT Tokens**: Short-lived access tokens (7 days) for API access
- **Refresh Tokens**: Long-lived tokens (365 days) for token renewal
- **Device-based Sessions**: Each device gets a unique session
- **Session Limits**: Maximum 5 concurrent sessions per user

### Admin Authentication
- **Bearer Tokens**: Secure admin session tokens (1 hour expiration)
- **JWT Authentication**: User authentication with access/refresh tokens
- **Auto-cleanup**: Expired tokens are automatically removed
- **Session Validation**: Token validation endpoint for dashboard

## API Endpoints

> 💡 **Tip**: For interactive API testing, visit the Swagger UI at `http://localhost:3000/api-docs` when running in development mode.

### Authentication Routes (`/auth`)

#### User Login
- **POST** `/auth/login`
- **Body**: `{ "username": "user", "password": "pass" }`
- **Returns**: Access token, refresh token, user info

#### Token Refresh
- **POST** `/auth/refresh`
- **Body**: `{ "refreshToken": "token", "deviceId": "id" }`
- **Returns**: New access and refresh tokens

#### Session Check
- **GET** `/auth/check`
- **Headers**: `Authorization: Bearer token`
- **Returns**: Session validity and user info

#### Logout
- **POST** `/auth/logout`
- **Headers**: `Authorization: Bearer token`
- **Body**: `{ "deviceId": "id" }`

#### Logout All Devices
- **POST** `/auth/logout-all`
- **Headers**: `Authorization: Bearer token`
- **Body**: `{}` (empty - user identified from token)

#### List Active Sessions
- **POST** `/auth/sessions`
- **Headers**: `Authorization: Bearer token`
- **Body**: `{}` (empty - user identified from token)
- **Returns**: Array of active sessions with device info

### User Management Routes (`/user`)

#### Register New User
- **POST** `/user/register`
- **Body**: `{ "username": "user", "email": "email", "password": "pass" }`
- **Returns**: User info and authentication tokens

#### Change Password
- **POST** `/user/change/password`
- **Headers**: `Authorization: Bearer token`
- **Body**: `{ "username": "user", "oldPassword": "old", "newPassword": "new" }`

#### Change Username
- **POST** `/user/change/username`
- **Headers**: `Authorization: Bearer token`
- **Body**: `{ "oldUsername": "old", "newUsername": "new", "password": "pass" }`

#### Change Email
- **POST** `/user/change/email`
- **Headers**: `Authorization: Bearer token`
- **Body**: `{ "username": "user", "newEmail": "email", "password": "pass" }`

#### Delete Account
- **POST** `/user/delete`
- **Headers**: `Authorization: Bearer token`
- **Body**: `{ "username": "user", "password": "pass" }`

### Metric Management Routes (`/api/metrics`)

All metric endpoints require: `Authorization: Bearer token` header

#### Create Metric Entry
- **POST** `/api/metrics`
- **Body**: `{ "metric_type_id": 1, "value": 75, "date": "2024-03-25", "is_apple_health": false }`
- **Returns**: Entry ID and success message

#### Update Metric Entry
- **PUT** `/api/metrics/:entryId`
- **Body**: `{ "value": 76, "date": "2024-03-26" }` (partial updates allowed)

#### Delete Metric Entry
- **DELETE** `/api/metrics/:entryId`

### Admin Routes (`/admin`)

#### Admin Login
- **POST** `/admin/login`
- **Body**: `{ "username": "admin", "password": "admin" }`
- **Returns**: Bearer token and expiration time

#### Token Validation
- **POST** `/admin/validate-token`
- **Headers**: `Authorization: Bearer admin_token`

#### Admin Logout
- **POST** `/admin/logout`
- **Headers**: `Authorization: Bearer admin_token`

All other admin endpoints require: `Authorization: Bearer admin_token`

#### User Management
- **GET** `/admin/getAllUserData` - Get all users
- **POST** `/admin/user` - Get specific user info
- **POST** `/admin/updateUser` - Update user data
- **POST** `/admin/deleteUser` - Delete user
- **POST** `/admin/createUser` - Create new user
- **GET** `/admin/emails` - Get all user emails

#### Statistics
- **GET** `/admin/registrations?range=24h|week|month|year` - Registration stats
- **GET** `/admin/active-users?range=24h|week|month|year` - Active user stats

#### Hardware Monitoring
- **GET** `/admin/hardwareinfo` - Get server hardware stats
- **Returns**: CPU temperature, fan speed, uptime with color coding

#### Legacy Endpoint (Deprecated)
- **POST** `/admin/check` - Legacy admin credentials check (use login instead)

## Error Handling

The API returns consistent error responses:

```json
{
  "success": false,
  "error": "Error message description"
}
```

**Common HTTP Status Codes:**
- `200`: Success
- `201`: Created
- `400`: Bad Request (missing/invalid data)
- `401`: Unauthorized (invalid/missing token)
- `403`: Forbidden (insufficient permissions)
- `404`: Not Found
- `409`: Conflict (duplicate data)
- `500`: Internal Server Error

## Hardware Monitoring

The admin dashboard includes real-time hardware monitoring requiring `lm-sensors`:

```bash
# Install on Ubuntu/Debian
sudo apt-get install lm-sensors

# Configure sensors
sudo sensors-detect
```

**Monitored Metrics:**
- **CPU Temperature**: Color-coded (Red: >70°C, Green: 40-70°C, Blue: <40°C)
- **Fan Speed**: Color-coded (Red: >3000 RPM, Green: 1500-3000 RPM, Blue: <1500 RPM)
- **System Uptime**: Formatted display (days, hours, minutes)

## Security Features

1. **Password Hashing**: bcrypt with configurable salt rounds
2. **JWT Security**: Signed tokens with expiration
3. **Bearer Token Authentication**: Required for protected endpoints
4. **Session Management**: Device-based tracking with limits
5. **Admin Token Expiration**: 1-hour admin sessions with auto-cleanup
6. **Input Validation**: Email format, required fields
7. **SQL Injection Protection**: Parameterized queries
8. **CORS Protection**: Configurable origin restrictions

## Development

### Available Scripts

- `npm start` - Start production server
- `npm run dev` - Start development server with nodemon (auto-restart on changes)

### Dependencies

**Core Dependencies**:
- `express` - Web framework
- `pg` - PostgreSQL client
- `jsonwebtoken` - JWT token handling
- `bcrypt` - Password hashing
- `winston` - Logging framework
- `nodemailer` - Email service

**Development Dependencies**:
- `nodemon` - Auto-restart during development
- `swagger-jsdoc` - API documentation generation
- `swagger-ui-express` - Interactive API documentation UI

### Environment Variables
The application requires all environment variables to be set in `.env`. Missing variables will prevent startup.

### Database Migrations
Database schema updates are handled automatically on application startup. New tables and default data are created as needed.

### Logging Configuration
Customize logging in `utils/logger.js`:
- Adjust log levels
- Modify output formats
- Change file destinations
- Configure rotation policies

## Deployment Considerations

1. **Environment Variables**: Secure storage of secrets in production
2. **Database**: PostgreSQL with proper connection pooling and backup strategy
3. **Logging**: Persistent log storage and rotation (consider ELK stack for production)
4. **Hardware Monitoring**: Ensure lm-sensors is installed and configured on Linux servers
5. **HTTPS**: Use reverse proxy (nginx/Apache) for SSL termination
6. **Process Management**: Use PM2, Docker, or Kubernetes for process management
7. **API Documentation**: Swagger UI is disabled in production for security
8. **Load Balancing**: Consider multiple instances behind a load balancer for high availability

## Client Implementation Guide

### Token Management
1. Store tokens securely (keychain/secure storage)
2. Include bearer tokens in authorization headers
3. Handle token refresh automatically on 401 errors
4. Implement proper logout flow

### Session Management
1. Track current device ID
2. Implement session list UI
3. Allow users to manage active sessions
4. Handle session limits gracefully

### Error Handling
1. Parse error responses consistently
2. Show user-friendly error messages
3. Handle network connectivity issues
4. Implement retry logic for failed requests

## Email Service

The application includes a comprehensive email service for sending HTML emails. The service supports:

- **HTML Email Sending**: Send rich HTML emails with styling
- **Environment Configuration**: All email settings configured via environment variables
- **Built-in Templates**: Welcome emails and password reset emails
- **Multiple Recipients**: Support for CC, BCC, and multiple recipients
- **Attachments**: Support for email attachments
- **Connection Verification**: Test email configuration before sending

### Email Configuration

Configure the following environment variables in your `.env` file:

```env
EMAIL_HOST=smtp.gmail.com          # SMTP server host
EMAIL_PORT=587                     # SMTP server port
EMAIL_SECURE=false                 # Use SSL/TLS (true for port 465)
EMAIL_USER=your_email@gmail.com    # Email account username
EMAIL_PASS=your_app_password       # Email account password (use app password for Gmail)
EMAIL_FROM=TrackIt <your_email@gmail.com>  # Default sender address
EMAIL_TLS_REJECT_UNAUTHORIZED=true # TLS certificate validation
```

### Popular Email Provider Settings

**Gmail:**
- Host: `smtp.gmail.com`
- Port: `587`
- Secure: `false`
- Note: Use app passwords instead of your regular password

**Outlook/Hotmail:**
- Host: `smtp-mail.outlook.com`
- Port: `587`
- Secure: `false`

**Yahoo:**
- Host: `smtp.mail.yahoo.com`
- Port: `587`
- Secure: `false`

### Usage Examples

```javascript
const emailService = require('./services/emailService');

// Send simple HTML email
await emailService.sendSimpleHtmlEmail(
  'user@example.com',
  'Subject',
  '<h1>Hello!</h1><p>HTML content here</p>'
);

// Send detailed email with all options
await emailService.sendHtmlEmail({
  to: 'user@example.com',
  subject: 'Subject',
  html: '<h1>HTML content</h1>',
  cc: ['cc@example.com'],
  bcc: ['bcc@example.com'],
  attachments: [/* attachment objects */]
});

// Send welcome email (built-in template)
await emailService.sendWelcomeEmail('user@example.com', 'Username');

// Send password reset email (built-in template)
await emailService.sendPasswordResetEmail('user@example.com', 'Username', 'reset-link');

// Verify email configuration
const isValid = await emailService.verifyConnection();
```

See `examples/emailExamples.js` for complete usage examples.

## Troubleshooting

### Common Issues

**Database Connection Issues**:
```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Test connection
psql -h localhost -U username -d database_name
```

**Environment Variables**:
- Ensure all required variables are set in `.env`
- Check for typos in variable names
- Verify database URL format: `postgres://username:password@host:port/database`

**Hardware Monitoring**:
```bash
# Install and configure sensors
sudo apt-get install lm-sensors
sudo sensors-detect

# Test sensors
sensors
```

**Email Service**:
- Use app-specific passwords for Gmail
- Check firewall settings for SMTP ports
- Verify email credentials and server settings

**Port Already in Use**:
```bash
# Find process using port 3000
lsof -i :3000

# Kill process if needed
kill -9 <PID>
```

## Contributing

1. Follow existing code style and structure
2. Add logging for new features using the Winston logger
3. Update API documentation for new endpoints (add Swagger annotations)
4. Test database operations thoroughly
5. Ensure proper error handling and validation
6. Update this README for any new features or configuration changes

## License

ISC License - see package.json for details.

---

## Additional Resources

- **GitHub Repository**: [https://github.com/apptrackit/trackit-backend](https://github.com/apptrackit/trackit-backend)
- **API Documentation**: Available at `/api-docs` when running in development mode
- **Issue Tracking**: Use GitHub Issues for bug reports and feature requests

For questions or support, please refer to the project's GitHub repository.