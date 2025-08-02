# 📱 LifeTrackerX

> A comprehensive iOS fitness and body tracking app with Apple Health integration

<div align="center">
  <img src="https://img.shields.io/badge/iOS-17.0+-blue.svg" alt="iOS Version">
  <img src="https://img.shields.io/badge/Swift-5.0-orange.svg" alt="Swift Version">
  <img src="https://img.shields.io/badge/Xcode-15.0+-blue.svg" alt="Xcode Version">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License">
</div>

## ✨ Features

### 🏃‍♂️ **Health & Fitness Tracking**
- **Body Measurements**: Weight, height, body fat percentage, BMI, and body circumferences (waist, bicep, chest, thigh, etc.)
- **Apple Health Integration**: Seamless sync with iOS Health app for automatic data import/export
- **Progress Analytics**: Interactive charts and trends with multiple time frames (weekly, monthly, 6-month, yearly, all-time)
- **Calculated Metrics**: Automatic computation of BMI, lean body mass, fat mass, FFMI, BMR, and body surface area

### 📊 **Smart Dashboard**
- **Real-time Overview**: Quick glance at latest measurements with beautiful summary cards
- **Progress Charts**: Visual trends with customizable time frames and smooth animations
- **Recent Activity**: Latest measurements and changes at a glance
- **Quick Actions**: One-tap access to add new measurements or photos

### 📸 **Progress Photos**
- **Visual Progress Tracking**: Capture and organize progress photos by date
- **Before/After Comparisons**: Side-by-side photo comparisons to visualize changes
- **Secure Storage**: Photos stored securely with privacy protection

### 🔐 **User Management**
- **Secure Authentication**: JWT-based authentication with refresh tokens
- **Cloud Sync**: Automatic backup and sync across devices via backend API
- **Data Export**: Export your data anytime for backup or migration
- **Privacy First**: All data encrypted and stored securely

### 🔄 **Apple Health Integration**
- **Bidirectional Sync**: Import from and export to Apple Health
- **Automatic Updates**: Background sync every 5 minutes when authorized
- **Data Integrity**: Smart conflict resolution and duplicate prevention
- **Health Categories**: Weight, height, body fat percentage, waist circumference

## 🏗️ Architecture

### **SwiftUI + MVVM**
- Modern SwiftUI interface with reactive data binding
- Clean architecture with separated concerns
- Combine framework for reactive programming

### **Core Components**
```
├── 📱 App Layer
│   ├── FitnessApp.swift (App entry point)
│   └── MainTabView.swift (Navigation structure)
├── 🎨 Views
│   ├── Dashboard/ (Main overview and charts)
│   ├── Photos/ (Progress photo management)
│   ├── History/ (Data history and trends)
│   └── Settings/ (User preferences and export)
├── 🧠 Managers
│   ├── HealthManager (Apple Health integration)
│   ├── AuthService (Authentication & backend)
│   ├── NetworkManager (API communications)
│   └── StatsHistoryManager (Data persistence)
└── 📊 Models
    ├── StatEntry (Measurement data)
    ├── StatType (Measurement categories)
    └── ProgressPhoto (Photo metadata)
```

## 🚀 Getting Started

### **Prerequisites**
- iOS 17.0+
- Xcode 15.0+
- Apple Developer Account (for HealthKit entitlements)

### **Installation**
1. **Clone the repository**
   ```bash
   git clone https://github.com/apptrackit/trackit-ios.git
   cd trackit-ios
   ```

2. **Open in Xcode**
   ```bash
   open TrackIt.xcodeproj
   ```

3. **Configure Backend** (Optional)
   - Update `AuthService.swift` with your backend URL
   - See [backend documentation](backend.md) for server setup

4. **Build and Run**
   - Select your target device/simulator
   - Press `Cmd + R` or click the Run button

## 🔧 Configuration

### **HealthKit Setup**
The app requires HealthKit permissions for full functionality:
- Weight (body mass)
- Height
- Body fat percentage  
- Waist circumference

Permissions are requested on first launch and can be managed in iOS Settings.

### **Backend Integration**
The app works offline but offers enhanced features with backend sync:
- User authentication and multi-device sync
- Data backup and recovery
- Advanced analytics and insights

Configure the backend URL in `AuthService.swift`:
```swift
private let baseURL = "https://your-backend-url.com"
```

## 📊 Supported Measurements

| Measurement | Unit | Apple Health | Auto-Calculated |
|------------|------|-------------|----------------|
| Weight | kg | ✅ | ➖ |
| Height | cm | ✅ | ➖ |
| Body Fat | % | ✅ | ➖ |
| BMI | - | ➖ | ✅ |
| Waist | cm | ✅ | ➖ |
| Bicep | cm | ➖ | ➖ |
| Chest | cm | ➖ | ➖ |
| Thigh | cm | ➖ | ➖ |
| Lean Body Mass | kg | ➖ | ✅ |
| Fat Mass | kg | ➖ | ✅ |
| FFMI | - | ➖ | ✅ |
| BMR | kcal | ➖ | ✅ |
| BSA | m² | ➖ | ✅ |

## 🎯 Key Features Deep Dive

### **Dashboard Analytics**
- **Time Frame Selection**: View progress over different periods
- **Interactive Charts**: Smooth line charts with trend indicators  
- **Summary Cards**: Quick overview of current metrics
- **Progress Insights**: Automated analysis of trends and changes

### **Apple Health Sync**
- **Background Sync**: Automatic updates every 5 minutes
- **Smart Deduplication**: Prevents duplicate entries across sources
- **Bidirectional Sync**: Changes sync both ways seamlessly
- **Offline Support**: Works without internet, syncs when available

### **Data Management**
- **Local Storage**: Core Data for reliable local persistence
- **Cloud Backup**: Optional backend sync for multi-device access
- **Export Options**: CSV export for data portability
- **Privacy Controls**: Granular control over data sharing

## 🔒 Privacy & Security

- **Local-First**: All data stored locally by default
- **Encrypted Storage**: Sensitive data encrypted in keychain
- **Health Privacy**: Respects iOS Health app privacy settings
- **Optional Cloud**: Backend sync is completely optional
- **Data Control**: Full user control over data sharing and export

## 🛠️ Development

### **Technologies Used**
- **SwiftUI**: Modern declarative UI framework
- **HealthKit**: Apple Health integration
- **Core Data**: Local data persistence  
- **Combine**: Reactive programming
- **Swift Charts**: Native chart rendering
- **URLSession**: Network communications

### **Architecture Patterns**
- **MVVM**: Clean separation of concerns
- **Reactive Programming**: Combine for data flow
- **Repository Pattern**: Abstracted data access
- **Dependency Injection**: Testable and modular code

## 📄 Backend API

The app integrates with a comprehensive REST API for user management and data sync. See [backend.md](backend.md) for detailed API documentation including:

- User authentication and session management
- Metric data CRUD operations
- Admin dashboard and monitoring
- Hardware monitoring and statistics
- Email service integration

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/apptrackit/trackit-ios/issues)