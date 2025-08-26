# SmartHaus ESP32-CAM Control App

A Flutter-based smart home IoT application for controlling ESP32-CAM devices with real-time monitoring and smart relay management.

## Features

- **ESP32-CAM video streaming**
- **Fingerprint door security monitoring** with push notifications
- **Water level monitoring** with alerts
- **Dynamic smart relay controls** (up to 6 relays)
- **Firebase Authentication** and real-time database
- **Custom Material Design UI**

## Setup

### Prerequisites
- Flutter SDK 3.9.0+
- Firebase project with Authentication, Realtime Database, and Cloud Messaging enabled

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/rul3zero/SmartHaus.git
   cd SmartHaus
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase**
   - Copy `lib/firebase_options.dart.template` to `lib/firebase_options.dart`
   - Replace placeholder values with your Firebase configuration
   - Or run: `flutterfire configure`

4. **Run the app**
   ```bash
   flutter run
   ```

## Database Structure

```json
{
  "devices": {
    "esp32cam_001": {
      "ip_address": "192.168.1.100",
      "ws_port": 81
    },
    "fingerprint_door_001": {
      "failed_attempts": 0,
      "last_updated": "2025-08-27 14:30:25",
      "status": "active",
      "logs": {
        "2025-08-27": {
          "14:25:30": {
            "status": "success",
            "user": "John"
          },
          "14:28:15": {
            "status": "failed",
            "user": "unknown"
          }
        }
      }
    },
    "water_level_001": {
      "status": "active",
      "water_level": 1,
      "last_updated": "2025-08-27 14:30:25",
      "logs": {
        "2025-08-27": {
          "14:25:30": {
            "water_level": 1,
            "status": "water_present",
            "tank_status": "normal"
          },
          "14:20:15": {
            "water_level": 0,
            "status": "water_empty",
            "tank_status": "alert"
          }
        }
      }
    }
  },
  "smart_controls": {
    "relays": {
      "1": {
        "id": 1,
        "name": "Living Room Light",
        "state": false,
        "last_updated": "2025-08-27 14:30:25"
      },
      "2": {
        "id": 2,
        "name": "Kitchen Fan",
        "state": true,
        "last_updated": "2025-08-27 14:30:25"
      },
      "3": {
        "id": 3,
        "name": "Garden Sprinkler",
        "state": false,
        "last_updated": "2025-08-27 14:30:25"
      }
    },
    "logs": {
      "relay_logs": {
        "log_1724762425": {
          "relay_id": 1,
          "relay_name": "Living Room Light",
          "action": "turned_on",
          "timestamp": "2025-08-27 14:30:25"
        }
      }
    },
    "system": {
      "last_sync": "2025-08-27 14:30:25",
      "total_relays": 3,
      "active_relays": 1
    }
  }
}
```

## Hardware Integration

ESP32-CAM should monitor these Firebase paths:

**Relay Control:**
```
smart_controls/relays/{id}/state  // true/false for relay control
```

**Device Status:**
```
devices/esp32cam_001/status       // "online"/"offline"
fingerprint_door_001/status       // "locked"/"unlocked"
water_level_001/level             // 0-100 percentage
```

## Tech Stack

- **Flutter/Dart** - Mobile app framework
- **Firebase** - Authentication, Realtime Database, Cloud Messaging
- **Material Design** - UI components
- **ESP32-CAM** - Hardware integration
