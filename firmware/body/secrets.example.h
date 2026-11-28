// Copy this file to secrets.h (same folder) and fill it in.
// secrets.h is in .gitignore: it never goes to GitHub.
//
// Without secrets.h the body still builds and runs, just without Wi-Fi.
#pragma once

// Wi-Fi (the pocket Wi-Fi in the farm). 2.4 GHz only: the ESP32 cannot
// join a 5 GHz network.
#define WIFI_SSID      "your-wifi-name"
#define WIFI_PASSWORD  "your-wifi-password"

// Firebase console -> Project settings -> General -> Web API key
#define FB_API_KEY     "AIza..."

// Firebase console -> Realtime Database -> the URL at the top, no trailing /
#define FB_DB_URL      "https://your-project-default-rtdb.asia-southeast1.firebasedatabase.app"

// The ESP32's own user (Authentication -> Users -> Add user)
#define FB_EMAIL       "esp32@farm.local"
#define FB_PASSWORD    "the-password-you-gave-that-user"
