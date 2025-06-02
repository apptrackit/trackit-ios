# TrackIt Backend

A REST API for user management with authentication.

## Prerequisites

- Node.js (v14 or later)
- npm
- SQLite3

## Installation

1. Clone the repository:
```bash
git clone https://github.com/apptrackit/trackit-backend
cd trackit_backend
```

2. Install dependencies:
```bash
npm install
```

## Configuration

Create a `.env` file in the root directory:

```env
# Database Configuration
DB_PATH=/path/to/your/database.db

# API Security
API_KEY=your_secure_api_key_here
JWT_SECRET=your_secure_jwt_secret_here

# Server Configuration
PORT=3000
HOST=localhost

# Security Settings
SALT=10  # Number of salt rounds for password hashing

# Admin Account
ADMIN_USERNAME=admin
ADMIN_PASSWORD=admin
ADMIN_API_KEY=admin
```

## Project Structure

```
trackit-backend/
│
├── app.js                 # Main application entry point
├── auth.js                # Authentication middleware
├── database.js            # Database connection and setup
│
├── controllers/           # Business logic
│   ├── authController.js  # Authentication logic
│   ├── userController.js  # User management logic
│   └── adminController.js # Admin operations
│
├── routes/                # API route definitions
│   ├── auth.js           # Authentication routes
│   ├── users.js          # User management routes
│   └── admin.js          # Admin routes
│
└── public/               # Static files
    ├── admin-dashboard.html
    ├── styles/
    └── scripts/
```

## Database

The application uses SQLite with two main tables:

### Users Table
- `id`: Unique identifier
- `username`: Unique username
- `email`: User's email
- `password`: Hashed password

### Sessions Table
- `id`: Unique identifier
- `user_id`: Reference to users table
- `device_id`: Unique device identifier
- `access_token`: JWT access token
- `refresh_token`: Refresh token
- `access_token_expires_at`: Access token expiration
- `refresh_token_expires_at`: Refresh token expiration
- `created_at`: Session creation timestamp
- `last_refresh_at`: Last token refresh timestamp
- `refresh_count`: Number of token refreshes

The database is automatically created and initialized when the application starts.

## Running the Server

Start the server:
```bash
npm start
```

The server will run on `http://localhost:3000` by default.

## API Authentication

All endpoints require an API key provided either as:
- Header: `x-api-key: your_api_key`
- Query: `?apiKey=your_api_key`

For authenticated user endpoints, include a JWT token:
`Authorization: Bearer your_jwt_token`

The JWT token contains:
- `userId`: User ID
- `username`: Username
- `deviceId`: Device identifier
- `iat`: Issued at timestamp
- `exp`: Expiration timestamp

## API Endpoints

### Authentication

#### User Login

- **URL**: `/auth/login`
- **Method**: POST
- **Body**:
  ```json
  {
    "username": "johndoe",
    "password": "securepassword"
  }
  ```
- **Success Response**: 
  ```json
  {
    "success": true,
    "authenticated": true,
    "message": "Authentication successful",
    "accessToken": "eyJhbGciOiJIUzI1NiIs...",
    "refreshToken": "a1b2c3d4e5f6...",
    "apiKey": "your_api_key_here",
    "deviceId": "unique_device_id",
    "user": {
      "id": 1,
      "username": "johndoe",
      "email": "john@example.com"
    }
  }
  ```
- **Error Responses**:
  - 400: Missing username or password
  - 403: Maximum sessions (5) reached
  - 500: Database error

#### Check Session Status

- **URL**: `/auth/check`
- **Method**: GET
- **Headers**: 
  - `Authorization: Bearer your_jwt_token`
  - `x-api-key: your_api_key`
- **Success Response**: 
  ```json
  {
    "success": true,
    "isAuthenticated": true,
    "message": "Session is valid",
    "deviceId": "your_device_id",
    "user": {
      "id": 1,
      "username": "johndoe",
      "email": "john@example.com"
    }
  }
  ```
- **Error Responses**:
  - 401: No token provided
  - 500: Database error

#### Logout

- **URL**: `/auth/logout`
- **Method**: POST
- **Headers**: 
  - `x-api-key: your_api_key`
- **Body**:
  ```json
  {
    "deviceId": "your_device_id",
    "userId": "user_id"
  }
  ```
- **Success Response**: 
  ```json
  {
    "success": true,
    "message": "Logged out successfully"
  }
  ```
- **Error Responses**:
  - 400: Missing deviceId or userId
  - 500: Database error

#### Logout All Devices

- **URL**: `/auth/logout-all`
- **Method**: POST
- **Headers**: 
  - `x-api-key: your_api_key`
- **Body**:
  ```json
  {
    "userId": "user_id"
  }
  ```
- **Success Response**: 
  ```json
  {
    "success": true,
    "message": "Logged out from all devices successfully"
  }
  ```
- **Error Responses**:
  - 400: Missing userId
  - 500: Database error

#### List Active Sessions

- **URL**: `/auth/sessions`
- **Method**: POST
- **Headers**: 
  - `x-api-key: your_api_key`
- **Body**:
  ```json
  {
    "userId": "user_id"
  }
  ```
- **Success Response**: 
  ```json
  {
    "success": true,
    "sessions": [
      {
        "id": 1,
        "device_id": "unique_device_id",
        "created_at": "2024-03-20T10:00:00Z",
        "last_refresh_at": "2024-03-20T15:00:00Z",
        "refresh_count": 2
      }
    ]
  }
  ```
- **Error Responses**:
  - 400: Missing userId
  - 500: Database error

#### Refresh Token

- **URL**: `/auth/refresh`
- **Method**: POST
- **Headers**: 
  - `x-api-key: your_api_key`
- **Body**:
  ```json
  {
    "refreshToken": "your_refresh_token",
    "deviceId": "your_device_id"
  }
  ```
- **Success Response**: 
  ```json
  {
    "success": true,
    "accessToken": "eyJhbGciOiJIUzI1NiIs...",
    "refreshToken": "new_refresh_token...",
    "deviceId": "your_device_id"
  }
  ```
- **Error Responses**:
  - 400: Missing refreshToken or deviceId
  - 401: Invalid or expired refresh token
  - 500: Database error

### User Management

#### Register a New User

- **URL**: `/user/register`
- **Method**: POST
- **Body**:
  ```json
  {
    "username": "johndoe",
    "email": "john@example.com",
    "password": "securepassword"
  }
  ```
- **Success Response**: 
  ```json
  {
    "success": true,
    "authenticated": true,
    "message": "Registration successful",
    "accessToken": "eyJhbGciOiJIUzI1NiIs...",
    "refreshToken": "a1b2c3d4e5f6...",
    "apiKey": "your_api_key_here",
    "deviceId": "unique_device_id",
    "user": {
      "id": 1,
      "username": "johndoe",
      "email": "john@example.com"
    }
  }
  ```
- **Error Responses**:
  - 400: Invalid email format
  - 409: Username already exists
  - 500: Database error

#### Change Password

- **URL**: `/user/change/password`
- **Method**: POST
- **Body**:
  ```json
  {
    "username": "johndoe",
    "oldPassword": "oldpassword",
    "newPassword": "newpassword"
  }
  ```
- **Success Response**: 
  ```json
  {
    "success": true,
    "message": "Password updated successfully"
  }
  ```

#### Change Username

- **URL**: `/user/change/username`
- **Method**: POST
- **Body**:
  ```json
  {
    "oldUsername": "johndoe",
    "newUsername": "johndoe2",
    "password": "securepassword"
  }
  ```
- **Success Response**: 
  ```json
  {
    "success": true,
    "message": "Username updated successfully"
  }
  ```

#### Change Email

- **URL**: `/user/change/email`
- **Method**: POST
- **Body**:
  ```json
  {
    "username": "johndoe",
    "newEmail": "newemail@example.com",
    "password": "securepassword"
  }
  ```
- **Success Response**: 
  ```json
  {
    "success": true,
    "message": "Email updated successfully"
  }
  ```

#### Delete Account

- **URL**: `/user/delete`
- **Method**: POST
- **Body**:
  ```json
  {
    "username": "johndoe",
    "password": "securepassword"
  }
  ```
- **Success Response**: 
  ```json
  {
    "success": true,
    "message": "Account deleted successfully"
  }
  ```

### Admin Operations

#### Admin Login

- **URL**: `/admin/login`
- **Method**: POST
- **Body**:
  ```json
  {
    "username": "admin",
    "password": "admin"
  }
  ```
- **Success Response**: 
  ```json
  {
    "success": true,
    "adminApiKey": "your_admin_api_key",
    "apiKey": "your_api_key",
    "username": "admin",
    "message": "Admin login successful"
  }
  ```

#### Admin User Lookup

- **URL**: `/admin/user`
- **Method**: POST
- **Headers**:
  - `x-admin-api-key: your_admin_api_key`
- **Body**:
  ```json
  {
    "username": "johndoe"
  }
  ```
- **Success Response**: 
  ```json
  {
    "id": 1,
    "username": "johndoe",
    "email": "john@example.com",
    "password": "[hashed password]"
  }
  ```

#### Get All Emails

- **URL**: `/admin/emails`
- **Method**: GET
- **Headers**:
  - `x-admin-api-key: your_admin_api_key`
- **Success Response**: 
  ```json
  {
    "success": true,
    "emails": ["user1@example.com", "user2@example.com"]
  }
  ```

## Session Management

The system uses a combination of access tokens and refresh tokens for session management:

1. **Access Token**:
   - Short-lived (7 days)
   - Used for API authentication
   - Contains user and device information
   - Stored in the database with expiration time

2. **Refresh Token**:
   - Long-lived (365 days)
   - Used to obtain new access tokens
   - Stored in the database with expiration time

3. **Device Management**:
   - Each login creates a unique device ID based on user agent and IP
   - Maximum of 5 concurrent sessions per user
   - Sessions are tracked per device
   - Users can view and manage their active sessions

4. **Session Storage**:
   - Sessions are stored in the database with:
     - User ID
     - Device ID
     - Access token
     - Refresh token
     - Access token expiration
     - Refresh token expiration
     - Creation timestamp
     - Last refresh timestamp
     - Refresh count

### Client Implementation

For the best user experience, implement the following in your client application:

1. Store securely:
   - Access token
   - Refresh token
   - Device ID
   - API key

2. Use the access token for all API requests

3. When you get a 401 error (expired token):
   - Use the refresh token and device ID to get new tokens
   - Retry the original request with the new access token

4. If the refresh token request fails:
   - Redirect to login screen

5. On logout:
   - Call the logout endpoint with the device ID
   - Clear stored tokens
   - Redirect to login screen

6. Session Management:
   - Track the current device ID
   - Use it to identify the current session in the sessions list
   - Implement session management UI to view and control active sessions

## Replit
- pull updates `git pull origin main`